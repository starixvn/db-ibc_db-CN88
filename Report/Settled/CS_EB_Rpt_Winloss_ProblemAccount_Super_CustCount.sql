/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_EB_Rpt_Winloss_ProblemAccount_Super_CustCount]
	@ReportMode			TINYINT = 1
	,@HeadlineId		INT = 0
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
	Task: CN88 - EB - Problem Account Settled Report - View Supers - Customer Counter
	DB: DBAGE.bodb02
	
	Revisions:
		- 20190926@Percy: Initialize SP [Redmine: #118962]
		
	Param's Explanation:
		- @ReportMode: 1: current, 2: history
		- @HeadlineId: 0: All Headline, <> 0: HeadlineId
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

	/* ===== Get Super Info ===== */
	BEGIN
		CREATE TABLE #tmpSuper (UplineId INT, srecommend INT, FromDate SMALLDATETIME, ToDate SMALLDATETIME)
		INSERT INTO #tmpSuper (UplineId, srecommend, FromDate, ToDate)
		SELECT e.UplineId, cs.custid, CASE WHEN FromDate < @FromDate THEN @FromDate ELSE FromDate END, CASE WHEN ToDate > @ToDate THEN @ToDate ELSE ToDate END
		FROM dbo.CustSuper cs WITH (NOLOCK)
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

	/* ===== Get Member Problem Account Info ===== */
	BEGIN
		CREATE TABLE #MemberProblemAccount (srecommend INT, mrecommend INT, recommend INT, custid INT)
		INSERT INTO #MemberProblemAccount (srecommend, mrecommend, recommend, custid)
		SELECT c.srecommend, c.mrecommend, c.recommend, pa.custid
		FROM #tmpSuper ts
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON ts.srecommend = c.srecommend AND c.roleid = 1
			INNER JOIN dbo.CS_ProblemAccount pa WITH (NOLOCK) ON c.custid = pa.custid
	END
	/* ===== End Get Member Problem Account Info ===== */

	/* ===== Get Data ===== */
	BEGIN
		CREATE TABLE #CustomerCounter
		(
			srecommend	INT
			,mrecommend	INT
			,recommend	INT
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
			FROM #tmpSuper ts
				CROSS APPLY (
					SELECT b.refno, bm.matchid
					FROM dbo.bettrans b WITH (NOLOCK)
						CROSS APPLY (SELECT TOP 1 bm.matchid FROM dbo.bettransm bm WITH (NOLOCK) WHERE b.refno = bm.refno) AS bm
					WHERE ts.srecommend = b.srecommend AND b.matchid = 2799
						AND b.winlostdate BETWEEN @FDate AND @TDate
						AND b.winlostdate BETWEEN ts.FromDate AND ts.ToDate
						AND b.statusID NOT IN (0, 1)
			) AS b

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
			FROM #tmpSuper ts
				CROSS APPLY (
					SELECT
						b.srecommend
						,b.mrecommend
						,b.recommend
						,b.custid
						,CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END AS matchid
						,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END AS eventtype
					FROM dbo.bettrans b WITH (NOLOCK)
						INNER JOIN #tblBetType bt ON b.bettype = bt.bettype
						OUTER APPLY (
							SELECT r.matchid FROM #__refno r WHERE b.refno = r.refno AND b.bettype = 2799
						) AS s
					WHERE ts.srecommend = b.srecommend
						AND b.statusID NOT IN (0, 1)
						AND b.winlostdate BETWEEN @FDate AND @TDate
						AND b.winlostdate BETWEEN ts.FromDate AND ts.ToDate
						AND (
								@IsLive = 2
								OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
								OR (b.bettype = 2799 AND @IsLive = 0)
								OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
							)
						AND (@IsExcludedTest = 0 OR b.currency <> 20)
						AND EXISTS (SELECT 1 FROM #MemberProblemAccount m WHERE b.custid = m.custid)
				) AS b
			GROUP BY
				b.srecommend
				,b.mrecommend
				,b.recommend
				,b.custid
				,b.matchid
				,b.eventtype

			DROP TABLE #__refno

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
					SELECT CASE WHEN b.matchid = 29 THEN 0 ELSE b.matchid END AS sporttype -- SB Parlay: sporttype = 0
					WHERE b.matchid <> 2799 AND b.eventtype = 0
				) AS m
				INNER JOIN #tblSportType s ON m.sporttype = s.SportType
			GROUP BY
				b.srecommend
				,b.mrecommend
				,b.recommend
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
					srecommend
					,mrecommend
					,recommend
					,custid
				)
				SELECT
					m.srecommend
					,m.mrecommend
					,m.recommend
					,m.custid
				FROM #tmpSuper ts
					INNER JOIN #MemberProblemAccount m ON ts.srecommend = m.srecommend
					CROSS APPLY (
						SELECT
							custid
						FROM bodb_Summary.dbo.CS_SumWinloss s WITH (NOLOCK)
						WHERE s.custid = m.custid
							AND s.HeadlineId = ts.UplineId
							AND s.WinlostDate BETWEEN @FDate AND @TDate
							AND s.WinlostDate BETWEEN ts.FromDate AND ts.ToDate
							AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
							AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
							AND (@IsLive = 2 OR IsLive = @IsLive)
					) AS s
				GROUP BY
					m.srecommend
					,m.mrecommend
					,m.recommend
					,m.custid

				INSERT INTO #CustomerCounter
				(
					srecommend
					,mrecommend
					,recommend
					,custid
				)
				SELECT
					m.srecommend
					,m.mrecommend
					,m.recommend
					,m.custid
				FROM #tmpSuper ts
					INNER JOIN #MemberProblemAccount m ON ts.srecommend = m.srecommend
					CROSS APPLY (
						SELECT
							custid
						FROM bodb_Summary.dbo.CS_SumCancelled s WITH (NOLOCK)
						WHERE s.custid = m.custid
							AND s.HeadlineId = ts.UplineId
							AND s.WinlostDate BETWEEN @FDate AND @TDate
							AND s.WinlostDate BETWEEN ts.FromDate AND ts.ToDate
							AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
							AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
							AND (@IsLive = 2 OR IsLive = @IsLive)
					) AS s
				GROUP BY
					m.srecommend
					,m.mrecommend
					,m.recommend
					,m.custid
			END
		END
		-- End CS_SumWinloss
	END
	/* ===== End Get Data ===== */

	/* ===== Return Data ===== */
	BEGIN
		SELECT
			COUNT(DISTINCT srecommend)	AS SuperCount
			,COUNT(DISTINCT mrecommend) AS MasterCount
			,COUNT(DISTINCT recommend)	AS AgentCount
			,COUNT(DISTINCT custid)		AS MemberCount
		FROM #CustomerCounter c
	END
	/* ===== End Return Data ===== */

	DROP TABLE #CustomerCounter
	DROP TABLE #tblBetType
	DROP TABLE #tblSportType
	DROP TABLE #tmpSuper
	DROP TABLE #MemberProblemAccount
END
GO