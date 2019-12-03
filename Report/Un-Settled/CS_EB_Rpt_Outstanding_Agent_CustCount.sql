/*<info serverAlias="DB042-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_EB_Rpt_Outstanding_Agent_CustCount]
	@HeadlineId			INT
	,@CustId			INT
	,@FromDate			SMALLDATETIME
	,@ToDate			SMALLDATETIME
	,@SporttypeGroups	VARCHAR(MAX) = '0' -- all
	,@BettypeGroup		SMALLINT = 0 -- all
	,@IsLive			TINYINT = 2 -- all
	,@IsExcludedTest	BIT = 1
AS

/*
	Created: 20191021@Percy
	Task: CN88 - EB - Un-Settled Report - View Agents - Customer Counter
	DB: DB042.bodb02
	
	Revisions:
		- 20191021@Percy: Initialize SP [Redmine: #122191]
		
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

	/* ===== Get date range when Super is belong to Headline ===== */
	BEGIN
		DECLARE @SuperId INT
		SELECT  @SuperId = srecommend FROM dbo.Customer WITH (NOLOCK) WHERE custid = @CustId AND (currency <> 20 OR @IsExcludedTest = 0)

		DECLARE @tblWinlostDate TABLE (FromDate SMALLDATETIME, ToDate SMALLDATETIME)
		INSERT INTO @tblWinlostDate (FromDate, ToDate)
		SELECT DISTINCT CASE WHEN FromDate < @FromDate THEN @FromDate ELSE FromDate END, CASE WHEN ToDate > @ToDate THEN @ToDate ELSE ToDate END
		FROM dbo.Acc_GroupExtraPTSetting WITH (NOLOCK)
		WHERE UplineId = @HeadlineId AND @FromDate <= ToDate AND @ToDate >= FromDate
			AND SuperId = @SuperId
	END
	/* ===== End Get date range when Super is belong to Headline ===== */

	/* ===== Get Data ===== */
	BEGIN
		CREATE TABLE #tmpBettrans
		(
			recommend	INT
			,custid		INT
			,matchid	INT
			,eventtype	TINYINT
		)

		-- For VS Parlay (bettype = 2799)
		SELECT b.refno, bm.matchid
		INTO #__refno
		FROM bodb02.dbo.bettrans b WITH (NOLOCK)
			CROSS APPLY (SELECT TOP 1 bm.matchid FROM bodb02.dbo.bettransm bm WITH (NOLOCK) WHERE b.refno = bm.refno) AS bm
		WHERE b.mrecommend = @CustId AND b.matchid = 2799 AND b.winlostdate BETWEEN @FromDate AND @ToDate
			AND b.statusID IN (0, 1)

		-- bettrans
		INSERT INTO #tmpBettrans
		(
			recommend
			,custid
			,matchid
			,eventtype
		)
		SELECT
			b.recommend
			,b.custid
			,CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END AS matchid
			,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END AS eventtype
		FROM dbo.bettrans b WITH (NOLOCK)
			INNER JOIN #tblBetType bt ON b.bettype = bt.bettype AND bt.RefTable = 0
			OUTER APPLY (
				SELECT r.matchid FROM #__refno r WHERE b.refno = r.refno AND b.bettype = 2799
			) AS s
		WHERE b.mrecommend = @CustId AND b.winlostdate BETWEEN @FromDate AND @ToDate
			AND b.statusID IN (0, 1)
			AND (
					@IsLive = 2
					OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
					OR (b.bettype = 2799 AND @IsLive = 0)
					OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
				)
			AND (b.currency <> 20 OR @IsExcludedTest = 0)
			AND EXISTS (SELECT 1 FROM @tblWinlostDate wld WHERE b.winlostdate BETWEEN wld.FromDate AND wld.ToDate)
		GROUP BY
			b.recommend
			,b.custid
			,CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END
			,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END

		DROP TABLE #__refno

		-- translog
		INSERT INTO #tmpBettrans
		(
			recommend
			,custid
			,matchid
			,eventtype
		)
		SELECT
			t.recommend
			,t.custid
			,CASE WHEN bt.eventtype = 0 THEN 0 ELSE t.eventid END AS matchid
			,bt.eventtype
		FROM dbo.translog t WITH (NOLOCK)
			INNER JOIN #tblBetType bt ON t.gameId = bt.bettype AND bt.RefTable = 3
		WHERE t.mrecommend = @CustId
			AND t.statusID IN (0, 1)
			AND t.winlostdate BETWEEN @FromDate AND @ToDate
			AND EXISTS (SELECT 1 FROM @tblWinlostDate wld WHERE t.winlostdate BETWEEN wld.FromDate AND wld.ToDate)
			AND (@IsLive = 2 OR t.liveindicator = @IsLive)
			AND (t.currency <> 20 OR @IsExcludedTest = 0)
		GROUP BY
			t.recommend
			,t.custid
			,CASE WHEN bt.eventtype = 0 THEN 0 ELSE t.eventid END
			,bt.eventtype
		
		-- sum data
		CREATE TABLE #CustomerCounter
		(
			recommend	INT
			,custid		INT
		)
	
		INSERT INTO #CustomerCounter
		(
			recommend
			,custid
		)
		SELECT
			b.recommend
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
			b.recommend
			,b.custid
		OPTION (HASH GROUP)
	END
	/* ===== End Get Data ===== */

	/* ===== Return data ===== */
	BEGIN
		SELECT
			COUNT(DISTINCT recommend)	AS AgentCount
			,COUNT(DISTINCT custid)		AS MemberCount
		FROM #CustomerCounter c
	END
	/* ===== End Return data ===== */

	DROP TABLE #CustomerCounter
	DROP TABLE #tblBetType
	DROP TABLE #tblSportType
	DROP TABLE #tmpBettrans
END
GO