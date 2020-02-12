/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_EB_Rpt_Winloss_ProblemAccount_Agent_CustCount]
	@ReportMode			TINYINT = 1
	,@HeadlineId		INT
	,@CustId			INT
	,@FromDate			SMALLDATETIME
	,@ToDate			SMALLDATETIME
	,@MoveBetsDay		SMALLDATETIME
	,@SporttypeGroups	VARCHAR(MAX) = '0' -- all
	,@BettypeGroup		SMALLINT = 0 -- all
	,@IsLive			TINYINT = 2  -- all
	,@IsExcludedTest	BIT = 1
AS

/*
	Created: 20190926@Percy
	Task: CN88 - EB - Problem Account Settled Report - View Agents - Customer Count
	DB: DBAGE.bodb02
	
	Revisions:
		- 20190926@Percy: Initialize SP [Redmine: #118962]
		
	Param's Explanation:
		- @ReportMode: 1: current, 2: history
		- @HeadlineId: HeadlineId
		- @CustId: MasterId
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

		CREATE TABLE #tblBetType (ProductID INT, BetType INT, EventType TINYINT)
		INSERT INTO #tblBetType (ProductID, BetType, EventType)
		SELECT DISTINCT ProductID, BetType, EventType FROM dbo.CS_f_BettypeMatrix_Sel (0, @SporttypeGroups, @BetTypeGroup, @IsTest)
	END
	/* ===== End Get Sport/Bettype ===== */

	/* ===== Get date range when Super is belong to Headline (on bettrans) ===== */
	BEGIN
		DECLARE @SuperId INT
		SELECT  @SuperId = srecommend FROM dbo.Customer WITH (NOLOCK) WHERE custid = @CustId

		DECLARE @tblWinlostDate TABLE (FromDate SMALLDATETIME, ToDate SMALLDATETIME)
		INSERT INTO @tblWinlostDate (FromDate, ToDate)
		SELECT CASE WHEN FromDate < @FromDate THEN @FromDate ELSE FromDate END, CASE WHEN ToDate > @ToDate THEN @ToDate ELSE ToDate END
		FROM dbo.Acc_GroupExtraPTSetting WITH (NOLOCK)
		WHERE UplineId = @HeadlineId
			AND ProductId = 1
			AND Sporttype = 0
			AND SubProduct = ''
			AND @FromDate <= ToDate AND @ToDate >= FromDate
			AND SuperId = @SuperId
	END
	/* ===== End Get date range when Super is belong to Headline (on bettrans) ===== */

	/* ===== Get Member Problem Account Info ===== */
	BEGIN
		CREATE TABLE #MemberProblemAccount (recommend INT, custid INT)
		INSERT INTO #MemberProblemAccount (recommend, custid)
		SELECT c.recommend, pa.custid
		FROM dbo.Customer c WITH (NOLOCK)
			INNER JOIN dbo.CS_ProblemAccount pa WITH (NOLOCK) ON c.custid = pa.custid
		WHERE c.mrecommend = @CustId AND c.roleid = 1
			AND (@IsExcludedTest = 0 OR c.currency <> 20)
	END
	/* ===== End Get Member Problem Account Info ===== */

	/* ===== Get Data ===== */
	BEGIN
		CREATE TABLE #CustomerCounter
		(
			recommend	INT
			,custid		INT
		)

		DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME

		-- bettrans
		IF @ReportMode = 1 AND @ToDate > @MoveBetsDay
		BEGIN
			SELECT	@FDate = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
					,@TDate = @ToDate
		
			IF OBJECT_ID('tempdb..#tmpBettrans') IS NOT NULL
				DROP TABLE #tmpBettrans

			IF OBJECT_ID('tempdb..#__refno') IS NOT NULL
				DROP TABLE #__refno

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
			FROM dbo.bettrans b WITH (NOLOCK)
				CROSS APPLY (SELECT TOP 1 bm.matchid FROM dbo.bettransm bm WITH (NOLOCK) WHERE b.refno = bm.refno) AS bm
			WHERE b.mrecommend = @CustId AND b.matchid = 2799 AND b.winlostdate BETWEEN @FDate AND @TDate
				AND b.statusID NOT IN (0, 1)

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
				INNER JOIN #tblBetType bt ON b.bettype = bt.bettype
				OUTER APPLY (
					SELECT r.matchid FROM #__refno r WHERE b.refno = r.refno AND b.bettype = 2799
				) AS s
			WHERE b.mrecommend = @CustId AND b.winlostdate BETWEEN @FDate AND @TDate
				AND b.statusID NOT IN (0, 1)
				AND (
						@IsLive = 2
						OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
						OR (b.bettype = 2799 AND @IsLive = 0)
						OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
					)
				AND EXISTS (SELECT 1 FROM @tblWinlostDate wld WHERE b.winlostdate BETWEEN wld.FromDate AND wld.ToDate)
				AND EXISTS (SELECT 1 FROM #MemberProblemAccount m WHERE b.custid = m.custid)
			GROUP BY
				b.recommend
				,b.custid
				,CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END
				,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END

			DROP TABLE #__refno

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
					SELECT CASE WHEN b.matchid = 29 THEN 0 ELSE b.matchid END AS sporttype -- SB Parlay: sporttype = 0
					WHERE b.matchid <> 2799 AND b.eventtype = 0
				) AS m
				INNER JOIN #tblSportType s ON m.sporttype = s.SportType
			GROUP BY
				b.recommend
				,b.custid
			OPTION (HASH GROUP)

			DROP TABLE #tmpBettrans
		END
		-- End bettrans
		
		-- CS_SumWinloss
		IF (@ReportMode = 1 AND @FromDate <= @MoveBetsDay) OR @ReportMode = 2
		BEGIN
			SELECT	@FDate = @FromDate
					,@TDate = CASE WHEN @ReportMode = 1 AND @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

			IF @FDate <= @TDate
			BEGIN
				INSERT INTO #CustomerCounter
				(
					recommend
					,custid
				)
				SELECT
					m.recommend
					,m.custid
				FROM #MemberProblemAccount m
					CROSS APPLY (
						SELECT
							custid
						FROM bodb_Summary.dbo.CS_SumWinloss s WITH (NOLOCK)
						WHERE s.custid = m.custid
							AND s.WinlostDate BETWEEN @FDate AND @TDate
							AND EXISTS (SELECT 1 FROM @tblWinlostDate wld WHERE s.winlostdate BETWEEN wld.FromDate AND wld.ToDate)
							AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
							AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
							AND (@IsLive = 2 OR IsLive = @IsLive)
					) AS s
				GROUP BY
					m.recommend
					,m.custid

				INSERT INTO #CustomerCounter
				(
					recommend
					,custid
				)
				SELECT
					m.recommend
					,m.custid
				FROM #MemberProblemAccount m
					CROSS APPLY (
						SELECT
							custid
						FROM bodb_Summary.dbo.CS_SumCancelled s WITH (NOLOCK)
						WHERE s.custid = m.custid
							AND s.WinlostDate BETWEEN @FDate AND @TDate
							AND EXISTS (SELECT 1 FROM @tblWinlostDate wld WHERE s.winlostdate BETWEEN wld.FromDate AND wld.ToDate)
							AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
							AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
							AND (@IsLive = 2 OR IsLive = @IsLive)
					) AS s
				GROUP BY
					m.recommend
					,m.custid
			END
		END
		-- End CS_SumWinloss
	END
	/* ===== End Get Data ===== */

	/* ===== Return Data ===== */
	BEGIN
		SELECT
			COUNT(DISTINCT recommend)	AS AgentCount
			,COUNT(DISTINCT custid)		AS MemberCount
		FROM #CustomerCounter c
	END
	/* ===== End Return Data ===== */

	DROP TABLE #CustomerCounter
	DROP TABLE #tblBetType
	DROP TABLE #tblSportType
	DROP TABLE #MemberProblemAccount
END
GO