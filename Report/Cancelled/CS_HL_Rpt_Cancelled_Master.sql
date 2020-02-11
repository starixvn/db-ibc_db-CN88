/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_HL_Rpt_Cancelled_Master]
	@HeadlineId			INT
	,@CustId			INT
	,@FromDate			SMALLDATETIME
	,@ToDate			SMALLDATETIME
	,@MoveBetsDay		SMALLDATETIME
	,@SporttypeGroups	VARCHAR(MAX) = '0' -- all
	,@BettypeGroup		SMALLINT = 0 -- all
	,@IsLive			TINYINT = 2 -- all
	,@ReportType 		TINYINT = 1
AS

/*
	Created: 20190926@Percy
	Task: CN88 - HL - Cancelled Report - View Masters
	DB: DBAGE.bodb02
	
	Revisions:
		- 20190926@Percy: Initialize SP [Redmine: #118962]
		
	Param's Explanation:
		- @HeadlineId: HeadlineId
		- @CustId: SuperId
		- @SporttypeGroups: list of SporttypeGroup
		- @BettypeGroup: default = 0: All
		- @IsLive: (market) default = 2: All
									= 1: Live
									= 0: Dead
		- @ReportType:  = 1: Cancelled Bets
						= 2: Abnormal Bets
*/

BEGIN
	SET NOCOUNT ON

	/* ===== Get SportBettypeMatrix ===== */
	BEGIN
		DECLARE @isTest BIT = 0
		SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

		CREATE TABLE #tblSportType (SportType INT)
		INSERT INTO #tblSportType (SportType)
		SELECT DISTINCT SportType FROM dbo.CS_f_SporttypeMatrix_Sel (0, @SportTypeGroups, @BetTypeGroup, @IsTest)

		CREATE TABLE #tblBetType (BetType INT, EventType TINYINT)
		INSERT INTO #tblBetType (BetType, EventType)
		SELECT DISTINCT BetType, EventType FROM dbo.CS_f_BettypeMatrix_Sel (0, @SportTypeGroups, @BetTypeGroup, @IsTest)
	END
	/* ===== End Get SportBettypeMatrix ===== */

	/* ===== Get date range when Super is belong to Headline ===== */
	BEGIN
		DECLARE @tblWinlostDate TABLE (FromDate SMALLDATETIME, ToDate SMALLDATETIME)
		INSERT INTO @tblWinlostDate (FromDate, ToDate)
		SELECT DISTINCT CASE WHEN FromDate < @FromDate THEN @FromDate ELSE FromDate END, CASE WHEN ToDate > @ToDate THEN @ToDate ELSE ToDate END
		FROM dbo.Acc_GroupExtraPTSetting WITH (NOLOCK)
		WHERE UplineId = @HeadlineId AND @FromDate <= ToDate AND @ToDate >= FromDate
			AND SuperId = @CustId
	END
	/* ===== End Get date range when Super is belong to Headline ===== */

	/* ===== Get data ===== */
	BEGIN
		DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME

		CREATE TABLE #tmpSumCancelled
		(
			CustId	INT
			,Wagers	INT
			,Stake	MONEY
		)

		-- bettrans
		IF @ToDate > @MoveBetsDay
		BEGIN
			SELECT	@FDate = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
					,@TDate = @ToDate

			IF OBJECT_ID('tempdb..#tmpBettrans') IS NOT NULL
				DROP TABLE #tmpBettrans

			IF OBJECT_ID('tempdb..#__refno') IS NOT NULL
				DROP TABLE #__refno

			CREATE TABLE #tmpBettrans
			(
				mrecommend	INT
				,matchid	INT
				,eventtype	TINYINT
				,Wagers		INT
				,Stake		MONEY
			)

			-- For VS Parlay (bettype = 2799)
			SELECT b.refno, bm.matchid
			INTO #__refno
			FROM dbo.bettrans b WITH (NOLOCK)
				CROSS APPLY (SELECT TOP 1 bm.matchid FROM dbo.bettransm bm WITH (NOLOCK) WHERE b.refno = bm.refno) AS bm
			WHERE b.srecommend = @CustId AND b.matchid = 2799 AND b.winlostdate BETWEEN @FDate AND @TDate
				AND b.statusID IN (101, 102, 103)
		
			INSERT INTO #tmpBettrans
			(
				mrecommend
				,matchid
				,eventtype
				,Wagers
				,Stake
			)
			SELECT
				b.mrecommend
				,CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END AS matchid
				,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END AS eventtype
				,COUNT(1) AS Wagers
				,SUM(b.stake) AS Stake
			FROM dbo.bettrans b WITH (NOLOCK)
				INNER JOIN #tblBetType bt ON b.bettype = bt.bettype
				OUTER APPLY (
					SELECT r.matchid FROM #__refno r WHERE b.refno = r.refno AND b.bettype = 2799
				) AS s
				OUTER APPLY (SELECT CAST(('<xml>' + ISNULL(b.ExtraInfo, '') + '</xml>') AS XML).value('data(/xml/p1/@ab)[1]','TINYINT')) AS t(c)
			WHERE b.srecommend = @CustId AND b.winlostdate BETWEEN @FDate AND @TDate
				AND b.statusID IN (101, 102, 103)
				AND @ReportType = CASE	WHEN b.ExtraInfo LIKE '%p1%' AND t.c = 1 THEN 2  --- Abnormal bet
										ELSE 1  --- Cancelled
									END
				AND (
					@IsLive = 2
					OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
					OR (b.bettype = 2799 AND @IsLive = 0)
					OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
				)
				AND EXISTS (SELECT 1 FROM @tblWinlostDate wld WHERE b.winlostdate BETWEEN wld.FromDate AND wld.ToDate)
			GROUP BY
				b.mrecommend
				,CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END
				,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END

			INSERT INTO #tmpSumCancelled
			(
				CustId
				,Wagers
				,Stake
			)
			SELECT
				b.mrecommend AS CustId
				,SUM(b.Wagers) AS Wagers
				,SUM(b.Stake) AS Stake
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
				b.mrecommend

			DROP TABLE #tmpBettrans
		END
		-- End bettrans

		-- CS_SumCancelled
		IF @FromDate <= @MoveBetsDay
		BEGIN
			SELECT	@FDate = @FromDate
					,@TDate = CASE WHEN @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

			INSERT INTO #tmpSumCancelled
			(
				CustId
				,Wagers
				,Stake
			)
			SELECT
				s.CustId
				,SUM(s.Wagers) AS Wagers
				,SUM(s.Stake) AS Stake
			FROM dbo.Customer c WITH (NOLOCK)
				CROSS APPLY (
					SELECT
						s.CustId
						,s.Wagers
						,s.Stake
					FROM bodb_Summary.dbo.CS_SumCancelled s WITH (NOLOCK)
					WHERE c.custid = s.custid
						AND s.WinlostDate BETWEEN @FDate AND @TDate
						AND EXISTS (SELECT 1 FROM @tblWinlostDate wld WHERE s.winlostdate BETWEEN wld.FromDate AND wld.ToDate)
						AND s.CancelType = @ReportType
						AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
						AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
						AND (@IsLive = 2 OR IsLive = @IsLive)
				) AS s
			WHERE c.srecommend = @CustId AND c.roleid = 3
			GROUP BY
				s.CustId
		END
		-- End CS_SumCancelled
	END
	/* ===== End Get data ===== */

	/* ===== Return result ===== */
	BEGIN
		SELECT
			c.CustId
			,c.Username
			,c.FirstName	AS Name
			,SUM(Wagers)	AS Wagers
			,SUM(Stake)		AS Stake
			,NULL AS ValidStake
			,NULL AS MemberIncome
			,NULL AS Agent
			,NULL AS AgentResult
			,NULL AS MasterIncome
			,NULL AS MasterResult
			,NULL AS MasterStock
			,NULL AS Super
			,NULL AS SuperIncome
			,NULL AS SuperResult
			,NULL AS SuperStock
		FROM #tmpSumCancelled s
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON c.CustID = s.CustID
		GROUP BY
			c.CustId
			,c.Username
			,c.FirstName
	END
	/* ===== End Return result ===== */

	DROP TABLE #tmpSumCancelled
	DROP TABLE #tblBetType
	DROP TABLE #tblSportType
END
GO