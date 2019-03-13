/*<info serverAlias="DB042-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_TotalBets_Overview_Master]
	@CustId		INT,
	@PossType	TINYINT = 0
AS

/*
	Created: 20190307@Percy
	DB: DB042.bodb02
	Task: Total Bets - Overview - Master view

	Revisions:
		- 20190307@Percy: Initialize SP [RedmineID: #109693]

	Param's Explanation:
		@PossType:
				= 0:	Full Percentage
				= 1:	Company %: Shown on SMA
				= 2:	SMA %: Shown on SMA
				= 3:	MA%: Shown on SMA, MA
				= 4:	Agent%: Shown on SMA, MA, Agent
				= 5:	SMA + MA + Agent%: Shown on SMA
				= 6:	SMA + MA %: Shown on SMA
				= 7:	MA + Agent %: Shown on SMA, MA
			--> @PossType: (0, 3, 4, 7)
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @TimeNow DATETIME = GETDATE()
	DECLARE @today DATETIME = CONVERT(DATE, @TimeNow)

	/* ===== Get Data ===== */
	BEGIN
		CREATE TABLE #Sports (SportTypeGroup SMALLINT, SportType INT)
		INSERT INTO #Sports (SportTypeGroup, SportType)
		SELECT DISTINCT SportTypeGroup, SportType FROM dbo.CS_SportBettypeMatrix WITH (NOLOCK) WHERE SportTypeGroup <> 9 -- Exclude Parlay

		CREATE TABLE #TotalBets
		(
			SportTypeGroup SMALLINT
			-- Wager
			,InplayWager INT, EarlyWager INT, TodayWager INT, OutrightWager INT
			-- Stake: original
			,InplayStake0 INT, EarlyStake0 INT, TodayStake0 INT, OutrightStake0 INT
			-- Stake: MA
			,InplayStake3 INT, EarlyStake3 INT, TodayStake3 INT, OutrightStake3 INT
			-- Stake: Agent
			,InplayStake4 INT, EarlyStake4 INT, TodayStake4 INT, OutrightStake4 INT
			-- Stake: MA + Agent
			,InplayStake7 INT, EarlyStake7 INT, TodayStake7 INT, OutrightStake7 INT
		)

		-- For Parlay
		CREATE TABLE #ParlayTotalBets
		(
			SelectionType TINYINT
			-- Wager
			,Wager INT
			-- Stake: original
			,Stake0 MONEY
			-- Stake: MA
			,Stake3 MONEY
			-- Stake: Agent
			,Stake4 MONEY
			-- Stake: MA + Agent
			,Stake7 MONEY
		)

		-- In-play, Early, Today
		BEGIN
			INSERT INTO #TotalBets
			(
				SportTypeGroup
				,InplayWager, EarlyWager, TodayWager
				,InplayStake0, EarlyStake0, TodayStake0
				,InplayStake3, EarlyStake3, TodayStake3
				,InplayStake4, EarlyStake4, TodayStake4
				,InplayStake7, EarlyStake7, TodayStake7
			)
			SELECT s.SportTypeGroup
					-- Wager
					,SUM(CASE WHEN m.kickofftime <= @TimeNow THEN 1 ELSE 0 END) AS InplayWager
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate > @today THEN 1 ELSE 0 END) AS EarlyWager
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate <= @today THEN 1 ELSE 0 END) AS TodayWager
					-- Stake: original
					,SUM(CASE WHEN m.kickofftime <= @TimeNow THEN b.stake ELSE 0 END) AS InplayStake0
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate > @today THEN b.stake ELSE 0 END) AS EarlyStake0
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate <= @today THEN b.stake ELSE 0 END) AS TodayStake0
					-- Stake: MA
					,SUM(CASE WHEN m.kickofftime <= @TimeNow THEN b.stake * b.mpositiontaking ELSE 0 END) AS InplayStake3
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate > @today THEN b.stake * b.mpositiontaking ELSE 0 END) AS EarlyStake3
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate <= @today THEN b.stake * b.mpositiontaking ELSE 0 END) AS TodayStake3
					-- Stake: Agent
					,SUM(CASE WHEN m.kickofftime <= @TimeNow THEN b.stake * b.apositiontaking ELSE 0 END) AS InplayStake4
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate > @today THEN b.stake * b.apositiontaking ELSE 0 END) AS EarlyStake4
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate <= @today THEN b.stake * b.apositiontaking ELSE 0 END) AS TodayStake4
					-- Stake: MA + Agent
					,SUM(CASE WHEN m.kickofftime <= @TimeNow THEN b.stake * (b.mpositiontaking + b.apositiontaking) ELSE 0 END) AS InplayStake7
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate > @today THEN b.stake * (b.mpositiontaking + b.apositiontaking) ELSE 0 END) AS EarlyStake7
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate <= @today THEN b.stake * (b.mpositiontaking + b.apositiontaking) ELSE 0 END) AS TodayStake7
			FROM #Sports s
				INNER JOIN dbo.match m WITH (NOLOCK) ON s.SportType = m.sporttype
				INNER JOIN dbo.bettrans b WITH (NOLOCK) ON m.matchid = b.matchid
			WHERE b.mrecommend = @CustId
				AND b.statusId IN (0, 1)
				AND m.eventstatus NOT IN ('closed', 'internal')
			GROUP BY s.SportTypeGroup
		END

		-- Outright
		BEGIN
			INSERT INTO #TotalBets
			(
				SportTypeGroup
				,OutrightWager
				,OutrightStake0
				,OutrightStake3
				,OutrightStake4
				,OutrightStake7
			)
			SELECT s.SportTypeGroup
					-- Wager
					,SUM(1) AS OutrightWager
					-- Stake: original
					,SUM(b.stake) AS OutrightStake0
					-- Stake: MA
					,SUM(b.stake * b.mpositiontaking) AS OutrightStake3
					-- Stake: Agent
					,SUM(b.stake * b.apositiontaking) AS OutrightStake4
					-- Stake: MA + Agent
					,SUM(b.stake * (b.mpositiontaking + b.apositiontaking)) AS OutrightStake7
			FROM #Sports s
				INNER JOIN dbo.League l WITH (NOLOCK) ON s.SportType = l.sporttype
				INNER JOIN dbo.outright o WITH (NOLOCK) ON l.leagueid = o.leagueid
				INNER JOIN dbo.bettrans b WITH (NOLOCK) ON o.orid = b.matchid
			WHERE b.mrecommend = @CustId
				AND b.statusId IN (0, 1)
				AND o.oddsstatus IN ('closed', 'running', 'suspend', 'closePrice')
			GROUP BY s.SportTypeGroup
		END

		-- Parlay
		BEGIN
			/*
			-- liveawayscore:
				1: Soccer only
				2: Other Sports except Soccer
				3: Soccer + Other Sports
			*/
			INSERT INTO #ParlayTotalBets (SelectionType, Wager, Stake0, Stake3, Stake4, Stake7)
			SELECT
				b.liveawayscore
				,SUM(1) AS Wager
				,SUM(b.stake) AS Stake0
				,SUM(b.stake * b.mpositiontaking) AS Stake3
				,SUM(b.stake * b.apositiontaking) AS Stake4
				,SUM(b.stake * (b.mpositiontaking + b.apositiontaking)) AS Stake7
			FROM dbo.bettrans b WITH (NOLOCK)
			WHERE b.mrecommend = @CustId
				AND b.statusId IN (0, 1)
				AND b.bettype = 29
			GROUP BY
				b.liveawayscore
		END
	END

	/* ===== Return data ===== */
	BEGIN
		-- 1. Detail by Sports
		;WITH CTE_Sports AS (
			SELECT DISTINCT SportTypeGroup FROM dbo.CS_SportBettypeMatrix WITH (NOLOCK)
			WHERE SportTypeGroup <> 9 -- Exclude Parlay
		)
		SELECT
			s.SportTypeGroup
			-- Wager
			,SUM(ISNULL(InplayWager, 0))	AS InplayWager
			,SUM(ISNULL(TodayWager, 0))		AS TodayWager
			,SUM(ISNULL(EarlyWager, 0))		AS EarlyWager
			,SUM(ISNULL(OutrightWager, 0))	AS OutrightWager
			-- Stake
			,SUM(ISNULL(CASE @PossType
							WHEN 0 THEN InplayStake0
							WHEN 3 THEN InplayStake3
							WHEN 4 THEN InplayStake4
							WHEN 7 THEN InplayStake7
							END, 0))					AS InplayStake
			,SUM(ISNULL(CASE @PossType
							WHEN 0 THEN TodayStake0
							WHEN 3 THEN TodayStake3
							WHEN 4 THEN TodayStake4
							WHEN 7 THEN TodayStake7
							END, 0))					AS TodayStake
			,SUM(ISNULL(CASE @PossType
							WHEN 0 THEN EarlyStake0
							WHEN 3 THEN EarlyStake3
							WHEN 4 THEN EarlyStake4
							WHEN 7 THEN EarlyStake7
							END, 0))					AS EarlyStake
			,SUM(ISNULL(CASE @PossType
							WHEN 0 THEN OutrightStake0
							WHEN 3 THEN OutrightStake3
							WHEN 4 THEN OutrightStake4
							WHEN 7 THEN OutrightStake7
							END, 0))					AS OutrightStake
		FROM CTE_Sports s
			LEFT JOIN #TotalBets t ON s.SportTypeGroup = t.SportTypeGroup
		GROUP BY s.SportTypeGroup
		ORDER BY s.SportTypeGroup

		-- 2. Parlay
		SELECT
			9 AS SportTypeGroup
			-- Soccer only
			,ISNULL(SUM(CASE WHEN SelectionType = 1 THEN 1 ELSE 0 END), 0)		AS SoccerParlayWager
			,ISNULL(SUM(CASE WHEN SelectionType = 1 THEN
									CASE @PossType
										WHEN 0 THEN Stake0
										WHEN 3 THEN Stake3
										WHEN 4 THEN Stake4
										WHEN 7 THEN Stake7
										END ELSE 0 END), 0)						AS SoccerParlayStake
			-- Other Sports except Soccer
			,ISNULL(SUM(CASE WHEN SelectionType = 2 THEN 1 ELSE 0 END), 0)		AS NonSoccerParlayWager
			,ISNULL(SUM(CASE WHEN SelectionType = 2 THEN
									CASE @PossType
										WHEN 0 THEN Stake0
										WHEN 3 THEN Stake3
										WHEN 4 THEN Stake4
										WHEN 7 THEN Stake7
										END ELSE 0 END), 0)						AS NonSoccerParlayStake
			-- Soccer + Other Sports
			,ISNULL(SUM(CASE WHEN SelectionType = 3 THEN 1 ELSE 0 END), 0)		AS MixSportsParlayWager
			,ISNULL(SUM(CASE WHEN SelectionType = 3 THEN
									CASE @PossType
										WHEN 0 THEN Stake0
										WHEN 3 THEN Stake3
										WHEN 4 THEN Stake4
										WHEN 7 THEN Stake7
										END ELSE 0 END), 0)						AS MixSportsParlayStake
		FROM #ParlayTotalBets
			
		-- 3. Total
		SELECT ISNULL(SUM(ISNULL(Wager, 0)), 0) AS TotalWagers, ISNULL(SUM(ISNULL(Stake, 0)), 0) AS TotalStake
		FROM
		(
			SELECT
				SUM(ISNULL(InplayWager, 0) + ISNULL(TodayWager, 0) + ISNULL(EarlyWager, 0) + ISNULL(OutrightWager, 0)) AS Wager
				,SUM(CASE @PossType
						WHEN 0 THEN ISNULL(InplayStake0, 0) + ISNULL(TodayStake0, 0) + ISNULL(EarlyStake0, 0) + ISNULL(OutrightStake0, 0)
						WHEN 3 THEN ISNULL(InplayStake3, 0) + ISNULL(TodayStake3, 0) + ISNULL(EarlyStake3, 0) + ISNULL(OutrightStake3, 0)
						WHEN 4 THEN ISNULL(InplayStake4, 0) + ISNULL(TodayStake4, 0) + ISNULL(EarlyStake4, 0) + ISNULL(OutrightStake4, 0)
						WHEN 7 THEN ISNULL(InplayStake7, 0) + ISNULL(TodayStake7, 0) + ISNULL(EarlyStake7, 0) + ISNULL(OutrightStake7, 0)
						END) AS Stake
			FROM #TotalBets

			UNION ALL
			SELECT
				SUM(ISNULL(Wager, 0)) AS Wager
				,SUM(CASE @PossType
						WHEN 0 THEN ISNULL(Stake0, 0)
						WHEN 3 THEN ISNULL(Stake3, 0)
						WHEN 4 THEN ISNULL(Stake4, 0)
						WHEN 7 THEN ISNULL(Stake7, 0)
						END) AS Stake
			FROM #ParlayTotalBets
		) AS Total
	END

	DROP TABLE #Sports
	DROP TABLE #TotalBets
	DROP TABLE #ParlayTotalBets
END
GO