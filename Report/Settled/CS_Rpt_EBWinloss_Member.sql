/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_Rpt_EBWinloss_Member]
	@ReportMode			TINYINT = 1
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
	Created: 20190812@Percy
	Task: CN88 - EB - Settled Report - View Members
	DB: DBAGE.bodb02
	
	Revisions:
		- 20190812@Percy: Initialize SP [Redmine: #116925]
		
	Param's Explanation:
		- @ReportMode: 1: current, 2: history
		- @CustId: AgentId
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

		CREATE TABLE #tblBetType (ProductID INT, BetType INT, EventType TINYINT)
		INSERT INTO #tblBetType (ProductID, BetType, EventType)
		SELECT DISTINCT ProductID, BetType, EventType FROM dbo.CS_f_BettypeMatrix_Sel (0, @SporttypeGroups, @BetTypeGroup, @IsTest)
	END
	/* ===== End Get Sport/Bettype ===== */

	/* ===== Get Data ===== */
	BEGIN
		CREATE TABLE #MemberWinLoss
		(
			CustId			INT
			,Wagers			INT
			,Stake			MONEY
			,ValidStake		MONEY
			,MemberIncome	MONEY
			,AgentResultA	MONEY
		)

		DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME

		-- bettrans
		IF @ReportMode = 1 AND @ToDate > @MoveBetsDay
		BEGIN
			SELECT	@FDate = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
					,@TDate = @ToDate
		
			IF OBJECT_ID('tempdb..#tmpBettrans') IS NOT NULL
				DROP TABLE #tmpBettrans

			CREATE TABLE #tmpBettrans
			(
				custid			INT
				,matchid		INT
				,eventtype		TINYINT
				,Wagers			INT
				,Stake			MONEY
				,ValidStake		MONEY
				,MemberIncome	MONEY
				,AgentResultA	MONEY
			)

			INSERT INTO #tmpBettrans
			(
				custid
				,matchid
				,eventtype
				,Wagers
				,Stake
				,ValidStake
				,MemberIncome
				,AgentResultA
			)
			SELECT
				b.custid
				,CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END AS matchid
				,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END AS eventtype
				,COUNT(1) AS Wagers
				,SUM(b.stake) AS Stake
				,SUM(ABS(b.winlost - b.actual_stake)) AS ValidStake
				,SUM(b.winlost - b.actual_stake + b.playercomm) AS MemberIncome
				,SUM((b.winlost - b.actual_stake + b.playercomm) * (1 - b.apositiontaking)) AS AgentResultA
			FROM dbo.bettrans b WITH (NOLOCK)
				INNER JOIN #tblBetType bt ON b.bettype = bt.bettype
				OUTER APPLY (
					SELECT TOP 1 bm.matchid
					FROM dbo.bettransm bm WITH (NOLOCK)
					WHERE b.refno = bm.refno AND b.bettype = 2799
				) AS s
			WHERE b.recommend = @CustId AND b.winlostdate BETWEEN @FDate AND @TDate
				AND b.statusID IN (111, 112, 113)
				AND (
						@IsLive = 2
						OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
						OR (b.bettype = 2799 AND @IsLive = 0)
						OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
					)
				AND (@IsExcludedTest = 0 OR b.currency <> 20)
			GROUP BY
				b.custid
				,CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END
				,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END

			INSERT INTO #MemberWinLoss
			(
				CustId
				,Wagers
				,Stake
				,ValidStake
				,MemberIncome
				,AgentResultA
			)
			SELECT
				b.custid
				,SUM(Wagers)		AS Wagers
				,SUM(Stake)			AS Stake
				,SUM(ValidStake)	AS ValidStake
				,SUM(MemberIncome)	AS MemberIncome
				,SUM(AgentResultA)	AS AgentResultA
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
				b.custid
			OPTION (HASH GROUP)

			DROP TABLE #tmpBettrans
		END

		-- CS_SumWinloss
		IF (@ReportMode = 1 AND @FromDate <= @MoveBetsDay) OR @ReportMode = 2
		BEGIN
			SELECT	@FDate = @FromDate
					,@TDate = CASE WHEN @ReportMode = 1 AND @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

			IF @FDate <= @TDate
			BEGIN
				INSERT INTO #MemberWinLoss
				(
					CustId
					,Wagers
					,Stake
					,ValidStake
					,MemberIncome
					,AgentResultA
				)
				SELECT
					c.CustId
					,SUM(Wagers)		AS Wagers
					,SUM(Stake)			AS Stake
					,SUM(ValidStake)	AS ValidStake
					,SUM(MemberWinloss + MemberComm) AS MemberIncome
					,SUM(AgentResultA)	AS AgentResultA
				FROM dbo.Customer c WITH (NOLOCK)
					CROSS APPLY (
						SELECT
							Wagers
							,Stake
							,ValidStake
							,MemberWinloss
							,MemberComm
							,AgentResultA
						FROM bodb_Summary.dbo.CS_SumWinloss s WITH (NOLOCK)
						WHERE c.custid = s.custid
							AND s.WinlostDate BETWEEN @FDate AND @TDate
							AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
							AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
							AND (@IsLive = 2 OR IsLive = @IsLive)
					) AS s
				WHERE c.recommend = @CustId AND c.roleid = 1
				GROUP BY
					c.CustId
			END
		END
		-- End CS_SumWinloss
	END
	/* ===== End Get Data ===== */

	/* ===== Return Data ===== */
	BEGIN
		SELECT
			c.CustId
			,c.Username
			,SUM(s.Wagers)			AS Wagers
			,SUM(s.Stake)			AS Stake
			,SUM(s.ValidStake)		AS ValidStake
			,SUM(s.MemberIncome)	AS MemberIncome
			,SUM(s.AgentResultA)		AS AgentResult
		FROM #MemberWinLoss s
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON s.custid = c.custid
		WHERE (c.currency <> 20 OR @IsExcludedTest = 0)
		GROUP BY
			c.CustId
			,c.Username
	END
	/* ===== End Return Data ===== */

	DROP TABLE #MemberWinLoss
	DROP TABLE #tblBetType
	DROP TABLE #tblSportType
END
GO