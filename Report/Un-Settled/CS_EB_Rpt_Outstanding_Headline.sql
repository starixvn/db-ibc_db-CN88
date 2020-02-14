/*<info serverAlias="DB042-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_EB_Rpt_Outstanding_Headline]
	@FromDate			SMALLDATETIME
	,@ToDate			SMALLDATETIME
	,@SporttypeGroups	VARCHAR(MAX) = '0' -- all
	,@BettypeGroup		SMALLINT = 0 -- all
	,@IsLive			TINYINT = 2 -- all
	,@IsExcludedTest	BIT = 1
	,@HeadlineGroupId   SMALLINT = 0 -- all
AS

/*
	Created: 20190812@Percy
	Task: CN88 - EB Un-Settled Report - View Headlines
	DB: DB042.bodb02
	
	Revisions:
		- 20190812@Percy: Initialize SP [Redmine: #116925]
		- 20191210@Percy: Apply new column epositiontaking instead of extra PT [RedmineID: #125158]
		- 20200210@Malcolm : New group of Headline XPG - Changes on EB [RedmineID : #127209]
		
	Param's Explanation:
		- @SporttypeGroup: default = 0: All
		- @BettypeGroup: default = 0: All
		- @IsLive: (market) default = 2: All
									= 1: Live
									= 0: Dead
		- @HeadlineGroupId: default = 0: all headlines
		                            = 1: TPG headlines
									= 2: XPG headlines
*/

BEGIN
	SET NOCOUNT ON

	/* ===== Get Sport/Bettype ===== */
	BEGIN
		DECLARE @isTest BIT
		SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

		CREATE TABLE #tblSportType (SportType INT)
		INSERT INTO #tblSportType (SportType)
		SELECT DISTINCT SportType FROM dbo.CS_f_SporttypeMatrix_Sel (0, @SporttypeGroups, @BetTypeGroup, @IsTest)

		CREATE TABLE #tblBetType (ProductID INT, BetType INT, EventType TINYINT, RefTable TINYINT)
		INSERT INTO #tblBetType (ProductID, BetType, EventType, RefTable)
		SELECT DISTINCT ProductID, BetType, EventType, RefTable FROM dbo.CS_f_BettypeMatrix_Sel (0, @SporttypeGroups, @BetTypeGroup, @IsTest)
	END
	/* ===== End Get Sport/Bettype ===== */

	/* ===== Get Cust Super ===== */
	BEGIN
	     CREATE TABLE #CS_CustSuper(CustID INT NOT NULL PRIMARY KEY)

		 INSERT INTO #CS_CustSuper(CustID)
		 SELECT c.CustId
	     FROM dbo.CS_CustSuper c 
		      LEFT JOIN dbo.f_GetHeadlineNoPT() f ON c.CustId = f.SuperId
		 WHERE @HeadlineGroupId = 0 OR (@HeadlineGroupId = 2 AND f.SuperId IS NOT NULL) OR (@HeadlineGroupId = 1 AND f.SuperId IS NULL)
	END 
	/* ===== Get End Cust Super ===== */

	/* ===== Get Data ===== */
	BEGIN
		CREATE TABLE #tmpBettrans
		(
			UplineId		INT
			,matchid		INT
			,eventtype		TINYINT
			,Wagers			INT
			,Stake			MONEY
			,HouseTurnover	MONEY
		)

		-- For VS Parlay (bettype = 2799)
		SELECT b.refno, b.matchid
		INTO #__refno
		FROM #CS_CustSuper c WITH (NOLOCK)
			CROSS APPLY (
				SELECT b.refno, bm.matchid
				FROM dbo.bettrans b WITH (NOLOCK)
					CROSS APPLY (SELECT TOP 1 bm.matchid FROM dbo.bettransm bm WITH (NOLOCK) WHERE b.refno = bm.refno) AS bm
				WHERE c.custid = b.srecommend AND b.matchid = 2799 AND b.statusID IN (0, 1) AND b.winlostdate BETWEEN @FromDate AND @ToDate
		) AS b

		-- bettrans
		INSERT INTO #tmpBettrans
		(
			UplineId
			,matchid
			,eventtype
			,Wagers
			,Stake
			,HouseTurnover
		)
		SELECT
			e.UplineId
			,b.matchid
			,b.eventtype
			,COUNT(1) AS Wagers
			,SUM(b.stake) AS Stake
			,SUM(b.stake * (1 - b.tpositiontaking - ISNULL(CONVERT(DECIMAL(9,8), b.epositiontaking), 0))) AS HouseTurnover
		FROM #CS_CustSuper cs WITH (NOLOCK)
			CROSS APPLY (
				SELECT
					b.srecommend
					,CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END AS matchid
					,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END AS eventtype
					,b.stake
					,b.tpositiontaking
					,b.epositiontaking
					,b.winlostdate
				FROM dbo.bettrans b WITH (NOLOCK)
					INNER JOIN #tblBetType bt ON b.bettype = bt.bettype AND bt.RefTable = 0
					OUTER APPLY (
						SELECT r.matchid FROM #__refno r WHERE b.refno = r.refno AND b.bettype = 2799
					) AS s
				WHERE cs.CustId = b.srecommend
					AND b.statusID IN (0, 1)
					AND (
							@IsLive = 2
							OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
							OR (b.bettype = 2799 AND @IsLive = 0)
							OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
						)
			) AS b
			CROSS APPLY (
				SELECT TOP 1 e.UplineId
				FROM dbo.Acc_GroupExtraPTSetting e WITH (NOLOCK)
				WHERE b.srecommend = e.SuperId
					AND b.winlostdate BETWEEN e.FromDate AND e.ToDate
			) e
		WHERE b.winlostdate BETWEEN @FromDate AND @ToDate -- prevent using index on winlostdate
		GROUP BY
			e.UplineId
			,b.matchid
			,b.eventtype

		DROP TABLE #__refno

		-- translog
		INSERT INTO #tmpBettrans
		(
			UplineId
			,matchid
			,eventtype
			,Wagers
			,Stake
			,HouseTurnover
		)
		SELECT
			e.UplineId
			,b.matchid
			,b.eventtype
			,COUNT(1) AS Wagers
			,SUM(b.stake) AS Stake
			,SUM(b.stake * (1 - b.tpositiontaking - ISNULL(CONVERT(DECIMAL(9,8), b.epositiontaking), 0))) AS HouseTurnover
		FROM #CS_CustSuper cs WITH (NOLOCK)
			CROSS APPLY (
				SELECT
					t.srecommend
					,CASE WHEN bt.eventtype = 0 THEN 0 ELSE t.eventid END AS matchid
					,bt.eventtype
					,t.stake
					,t.tpositiontaking
					,t.epositiontaking
					,t.winlostdate
				FROM dbo.translog t WITH (NOLOCK)
					INNER JOIN #tblBetType bt ON t.gameId = bt.bettype AND bt.RefTable = 3
				WHERE cs.CustId = t.srecommend
					AND t.statusID IN (0, 1)
					AND t.winlostdate BETWEEN @FromDate AND @ToDate
					AND (@IsLive = 2 OR t.liveindicator = @IsLive)
			) AS b
			CROSS APPLY (
				SELECT TOP 1 e.UplineId
				FROM dbo.Acc_GroupExtraPTSetting e WITH (NOLOCK)
				WHERE b.srecommend = e.SuperId
					AND b.winlostdate BETWEEN e.FromDate AND e.ToDate
			) e
		GROUP BY
			e.UplineId
			,b.matchid
			,b.eventtype
		
		-- sum data
		CREATE TABLE #HeadlineOutstanding
		(
			CustId			INT
			,Wagers			INT
			,Stake			MONEY
			,HouseTurnover	MONEY
		)
	
		INSERT INTO #HeadlineOutstanding
		(
			CustId
			,Wagers
			,Stake
			,HouseTurnover
		)
		SELECT
			b.UplineId				AS CustId
			,SUM(b.Wagers)			AS Wagers
			,SUM(b.Stake)			AS Stake
			,SUM(b.HouseTurnover)	AS HouseTurnover
		FROM #tmpBettrans b
			CROSS APPLY (
				SELECT m.sporttype
				FROM dbo.match m WITH (NOLOCK)
				WHERE b.matchid = m.matchid AND b.eventtype = 1 -- included Betradar VS Parlay

				UNION ALL
				SELECT l.sporttype
				FROM dbo.outright o WITH (NOLOCK)
					INNER JOIN dbo.League l WITH (NOLOCK) ON o.leagueid = l.leagueid
				WHERE b.matchid = o.orid AND b.eventtype = 2

				UNION ALL
				SELECT r.sporttype
				FROM dbo.VSRaceInfo r WITH (NOLOCK)
				WHERE b.matchid = r.EventID AND b.eventtype = 3

				UNION ALL
				SELECT 0 AS sporttype -- SB Parlay: sporttype = 0
				WHERE b.matchid <> 2799 AND b.eventtype = 0
			) AS m
		WHERE EXISTS (SELECT 1 FROM #tblSportType s WHERE m.sporttype = s.SportType OR m.sporttype = 0)
		GROUP BY
			b.UplineId
		OPTION (HASH GROUP)
	END
	/* ===== End Get Data ===== */

	/* ===== Return Data ===== */
	SELECT
		c.CustId
		,c.Username
		,SUM(Wagers) AS Wagers
		,SUM(Stake) AS Stake
		,0 AS ValidStake
		,0 AS MemberWinloss
		,0 AS MemberComm
		,0 AS MemberIncome
		,0 AS SuperComm
		,0 AS HouseWinloss
		,0 AS HouseComm
		,SUM(HouseTurnover) AS HouseTurnover
		,0 AS HouseIncome
		,0 AS HeadlineResult
		,0 AS HeadlineStock
		,0 AS RebateRoundDown
	FROM #HeadlineOutstanding o
		INNER JOIN dbo.Customer c WITH (NOLOCK) ON o.CustId = c.custid
	WHERE c.roleid = 0
		AND (c.currency <> 20 OR @IsExcludedTest = 0)
	GROUP BY
		c.CustId
		,c.Username
	/* ===== End Return Data ===== */

	DROP TABLE #HeadlineOutstanding
	DROP TABLE #tblBetType
	DROP TABLE #tblSportType
	DROP TABLE #tmpBettrans
	DROP TABLE #CS_CustSuper
END
GO