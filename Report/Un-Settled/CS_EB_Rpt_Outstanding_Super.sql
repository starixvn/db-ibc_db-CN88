/*<info serverAlias="DB042-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_EB_Rpt_Outstanding_Super]
	@HeadlineId			INT = 0
	,@CustId			INT = 0
	,@FromDate			SMALLDATETIME
	,@ToDate			SMALLDATETIME
	,@SporttypeGroups	VARCHAR(MAX) = '0' -- all
	,@BettypeGroup		SMALLINT = 0 -- all
	,@IsLive			TINYINT = 2 -- all
	,@IsExcludedTest	BIT = 1
AS

/*
	Created: 20190926@Percy
	Task: CN88 - EB - Un-Settled Reports - View Supers
	DB: DB042.bodb02
	
	Revisions:
		- 20190926@Percy: Initialize SP [Redmine: #118962]
		- 20200212@Percy: Fix wrong get setting from ExtraPT table [RedmineID: #128366]
		
	Param's Explanation:
		- @HeadlineId: 0: All Headlines, <> 0: HeadlineId
		- @CustId: 0: All Headlines, <> 0: HeadlineId
		- @SporttypeGroups: list of SporttypeGroup
		- @BettypeGroup: default = 0: All
		- @IsLive: (market) default = 2: All
									= 1: Live
									= 0: Dead
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

	/* ===== Get Super Info ===== */
	BEGIN
		CREATE TABLE #tmpSuper (UplineId INT, srecommend INT, FromDate SMALLDATETIME, ToDate SMALLDATETIME)
		INSERT INTO #tmpSuper (UplineId, srecommend, FromDate, ToDate)
		SELECT e.UplineId, cs.custid, CASE WHEN FromDate < @FromDate THEN @FromDate ELSE FromDate END, CASE WHEN ToDate > @ToDate THEN @ToDate ELSE ToDate END
		FROM dbo.CS_CustSuper cs WITH (NOLOCK)
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON cs.custid = c.custid
			CROSS APPLY (
				SELECT UplineId, FromDate, ToDate
				FROM dbo.Acc_GroupExtraPTSetting s WITH (NOLOCK)
				WHERE cs.custid = s.SuperId
					AND s.ProductId = 1
					AND s.Sporttype = 0
					AND s.SubProduct = ''
					AND @FromDate <= ToDate AND @ToDate >= FromDate
					AND (@HeadlineId = 0 OR s.UplineId = @HeadlineId)
			) AS e
		WHERE (c.currency <> 20 OR @IsExcludedTest = 0)
	END
	/* ===== End Get Super Info ===== */

	/* ===== Get Data ===== */
	BEGIN
		CREATE TABLE #tmpBettrans
		(
			srecommend	INT
			,UplineId	INT
			,matchid	INT
			,eventtype	TINYINT
			,Wagers		INT
			,Stake		MONEY
		)

		-- For VS Parlay (bettype = 2799)
		SELECT b.refno, b.matchid
		INTO #__refno
		FROM #tmpSuper ts
			CROSS APPLY (
				SELECT b.refno, bm.matchid
				FROM bodb02.dbo.bettrans b WITH (NOLOCK)
					CROSS APPLY (SELECT TOP 1 bm.matchid FROM bodb02.dbo.bettransm bm WITH (NOLOCK) WHERE b.refno = bm.refno) AS bm
				WHERE ts.srecommend = b.srecommend AND b.matchid = 2799 AND b.winlostdate BETWEEN ts.FromDate AND ts.ToDate
					 AND b.winlostdate BETWEEN @FromDate AND @ToDate
					 AND b.statusID IN (0, 1)
		) AS b

		-- bettrans
		INSERT INTO #tmpBettrans
		(
			srecommend
			,UplineId
			,matchid
			,eventtype
			,Wagers
			,Stake
		)
		SELECT
			b.srecommend
			,ts.UplineId
			,b.matchid
			,b.eventtype
			,COUNT(1) AS Wagers
			,SUM(b.stake) AS Stake
		FROM #tmpSuper ts
			CROSS APPLY (
				SELECT
					b.srecommend
					,CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END AS matchid
					,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END AS eventtype
					,b.stake
					,b.winlostdate
				FROM dbo.bettrans b WITH (NOLOCK)
					INNER JOIN #tblBetType bt ON b.bettype = bt.bettype AND bt.RefTable = 0
					OUTER APPLY (
						SELECT r.matchid FROM #__refno r WHERE b.refno = r.refno AND b.bettype = 2799
					) AS s
				WHERE ts.srecommend = b.srecommend
					AND b.statusID IN (0, 1)
					AND (
							@IsLive = 2
							OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
							OR (b.bettype = 2799 AND @IsLive = 0)
							OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
						)
			) AS b
		WHERE b.winlostdate BETWEEN @FromDate AND @ToDate -- prevent using index on winlostdate
			AND b.winlostdate BETWEEN ts.FromDate AND ts.ToDate
		GROUP BY
			b.srecommend
			,ts.UplineId
			,b.matchid
			,b.eventtype

		DROP TABLE #__refno

		-- translog
		INSERT INTO #tmpBettrans
		(
			srecommend
			,UplineId
			,matchid
			,eventtype
			,Wagers
			,Stake
		)
		SELECT
			b.srecommend
			,ts.UplineId
			,b.matchid
			,b.eventtype
			,COUNT(1) AS Wagers
			,SUM(b.stake) AS Stake
		FROM #tmpSuper ts
			CROSS APPLY (
				SELECT
					t.srecommend
					,CASE WHEN bt.eventtype = 0 THEN 0 ELSE t.eventid END AS matchid
					,bt.eventtype
					,bt.ProductID
					,t.stake
					,t.tpositiontaking
					,t.winlostdate
				FROM dbo.translog t WITH (NOLOCK)
					INNER JOIN #tblBetType bt ON t.gameId = bt.bettype AND bt.RefTable = 3
				WHERE ts.srecommend = t.srecommend
					AND t.statusID IN (0, 1)
					AND t.winlostdate BETWEEN @FromDate AND @ToDate
					AND t.winlostdate BETWEEN ts.FromDate AND ts.ToDate
					AND (@IsLive = 2 OR t.liveindicator = @IsLive)
			) AS b
		GROUP BY
			b.srecommend
			,ts.UplineId
			,b.matchid
			,b.eventtype
		
		-- sum data
		CREATE TABLE #SuperOutstanding
		(
			CustId		INT
			,UplineId	INT
			,Wagers		INT
			,Stake		MONEY
		)
	
		INSERT INTO #SuperOutstanding
		(
			CustId
			,UplineId
			,Wagers
			,Stake
		)
		SELECT
			b.srecommend	AS CustId
			,b.UplineId		AS UplineId
			,SUM(b.Wagers)	AS Wagers
			,SUM(b.Stake)	AS Stake
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
			b.srecommend
			,b.UplineId
		OPTION (HASH GROUP)
	END
	/* ===== End Get Data ===== */

	/* ===== Return data ===== */
	BEGIN
		SELECT
			u.CustId AS HeadlineId
			,u.Username AS HeadlineUsername
			,c.CustId
			,c.Username
			,c.FirstName AS Name
			,SUM(Wagers) AS Wagers
			,SUM(Stake) AS Stake
			,0 AS ValidStake
			,0 AS MemberIncome
			,0 AS Agent
			,0 AS AgentResult
			,0 AS Master
			,0 AS MasterResult
			,0 AS Super
			,0 AS SuperIncome
			,0 AS SuperResult
			,0 AS SuperStock
			,0 AS HeadlineIncome
			,0 AS HeadlineResult
			,0 AS HeadlineStock
			,0 AS Rebate
			,0 AS RebateRoundDown -- Round down abs 100
		FROM #SuperOutstanding o
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON o.CustID = c.CustID
			INNER JOIN dbo.Customer u WITH (NOLOCK) ON o.UplineId = u.CustID
		WHERE (c.currency <> 20 OR @IsExcludedTest = 0)
		GROUP BY
			u.CustId
			,u.Username
			,c.CustId
			,c.Username
			,c.FirstName
	END
	/* ===== End Return data ===== */

	DROP TABLE #SuperOutstanding
	DROP TABLE #tblBetType
	DROP TABLE #tblSportType
	DROP TABLE #tmpBettrans
END
GO