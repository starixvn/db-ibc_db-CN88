/*<info serverAlias="DB042-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_EB_Rpt_Outstanding_Headline_CustCount]
	@FromDate			SMALLDATETIME
	,@ToDate			SMALLDATETIME
	,@SporttypeGroups	VARCHAR(MAX) = '0' -- all
	,@BettypeGroup		SMALLINT = 0 -- all
	,@IsLive			TINYINT = 2 -- all
	,@IsExcludedTest	BIT = 1
AS

/*
	Created: 20191021@Percy
	Task: CN88 - EB - Un-Settled Report - View Headlines - Customer Counter
	DB: DB042.bodb02
	
	Revisions:
		- 20191021@Percy: Initialize SP [Redmine: #122191]
		
	Param's Explanation:
		- @SporttypeGroup: default = 0: All
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

	/* ===== Get Data ===== */
	BEGIN
		CREATE TABLE #tmpBettrans
		(
			srecommend	INT
			,mrecommend	INT
			,recommend	INT
			,custid		INT
			,matchid	INT
			,eventtype	TINYINT
		)

		-- For VS Parlay (bettype = 2799)
		SELECT b.refno, b.matchid
		INTO #__refno
		FROM dbo.CS_CustSuper c WITH (NOLOCK)
			CROSS APPLY (
				SELECT b.refno, bm.matchid
				FROM dbo.bettrans b WITH (NOLOCK)
					CROSS APPLY (SELECT TOP 1 bm.matchid FROM dbo.bettransm bm WITH (NOLOCK) WHERE b.refno = bm.refno) AS bm
				WHERE c.custid = b.srecommend AND b.matchid = 2799 AND b.statusID IN (0, 1) AND b.winlostdate BETWEEN @FromDate AND @ToDate
		) AS b

		-- bettrans
		INSERT INTO #tmpBettrans
		(
			srecommend
			,mrecommend
			,recommend
			,custid
			,matchid
			,eventtype
		)
		SELECT
			b.srecommend
			,b.mrecommend
			,b.recommend
			,b.custid
			,b.matchid
			,b.eventtype
		FROM dbo.CS_CustSuper cs WITH (NOLOCK)
			CROSS APPLY (
				SELECT
					b.srecommend
					,b.mrecommend
					,b.recommend
					,b.custid
					,CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END AS matchid
					,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END AS eventtype
					,bt.ProductID
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
					AND (b.currency <> 20 AND @IsExcludedTest = 0)
			) AS b
			OUTER APPLY (
				SELECT ag.ExtraPT
				FROM dbo.Acc_GroupExtraPTSetting ag WITH (NOLOCK)
				WHERE cs.CustId = ag.SuperId
					AND b.winlostdate BETWEEN ag.FromDate AND ag.ToDate
					AND b.ProductID = ag.ProductId
					AND ag.Sporttype = 0
					AND ag.SubProduct = ''
			) AS e
		WHERE b.winlostdate BETWEEN @FromDate AND @ToDate -- prevent using index on winlostdate
		GROUP BY
			b.srecommend
			,b.mrecommend
			,b.recommend
			,b.custid
			,b.matchid
			,b.eventtype

		DROP TABLE #__refno

		-- translog
		INSERT INTO #tmpBettrans
		(
			srecommend
			,mrecommend
			,recommend
			,custid
			,matchid
			,eventtype
		)
		SELECT
			b.srecommend
			,b.mrecommend
			,b.recommend
			,b.custid
			,b.matchid
			,b.eventtype
		FROM dbo.CS_CustSuper cs WITH (NOLOCK)
			CROSS APPLY (
				SELECT
					t.srecommend
					,t.mrecommend
					,t.recommend
					,t.custid
					,CASE WHEN bt.eventtype = 0 THEN 0 ELSE t.eventid END AS matchid
					,bt.eventtype
					,bt.ProductID
					,t.winlostdate
				FROM dbo.translog t WITH (NOLOCK)
					INNER JOIN #tblBetType bt ON t.gameId = bt.bettype AND bt.RefTable = 3
				WHERE cs.CustId = t.srecommend
					AND t.statusID IN (0, 1)
					AND t.winlostdate BETWEEN @FromDate AND @ToDate
					AND (@IsLive = 2 OR t.liveindicator = @IsLive)
					AND (t.currency <> 20 AND @IsExcludedTest = 0)
			) AS b
			OUTER APPLY (
				SELECT SUM(ag.ExtraPT) AS ExtraPT
				FROM dbo.Acc_GroupExtraPTSetting ag WITH (NOLOCK)
				WHERE cs.CustId = ag.SuperId
					AND b.winlostdate BETWEEN ag.FromDate AND ag.ToDate
					AND b.ProductID = ag.ProductId
					AND ag.Sporttype = 0
					AND ag.SubProduct = ''
			) AS e
		GROUP BY
			b.srecommend
			,b.mrecommend
			,b.recommend
			,b.custid
			,b.matchid
			,b.eventtype
		
		-- sum data
		CREATE TABLE #CustomerCounter
		(
			srecommend	INT
			,mrecommend	INT
			,recommend	INT
			,custid		INT
		)
	
		INSERT INTO #CustomerCounter
		(
			srecommend
			,mrecommend
			,recommend
			,custid
		)
		SELECT
			b.srecommend
			,b.mrecommend
			,b.recommend
			,b.custid
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
			,b.mrecommend
			,b.recommend
			,b.custid
		OPTION (HASH GROUP)
	END
	/* ===== End Get Data ===== */

	/* ===== Return Data ===== */
	BEGIN
		SELECT
			COUNT(DISTINCT cs.UplineId)		AS HeadlineCount
			,COUNT(DISTINCT c.srecommend)	AS SuperCount
			,COUNT(DISTINCT c.mrecommend)	AS MasterCount
			,COUNT(DISTINCT c.recommend)	AS AgentCount
			,COUNT(DISTINCT c.custid)		AS MemberCount
		FROM #CustomerCounter c
			INNER JOIN dbo.CustSuper cs WITH (NOLOCK) ON c.srecommend = cs.custid
	END
	/* ===== End Return Data ===== */

	DROP TABLE #CustomerCounter
	DROP TABLE #tblBetType
	DROP TABLE #tblSportType
	DROP TABLE #tmpBettrans
END
GO