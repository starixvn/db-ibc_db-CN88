/*<info serverAlias="DB042-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_TotalBets_Overview_Super]
	@CustId		INT,
	@PossType	TINYINT = 0
AS

/*
	Created: 20190307@Percy
	DB: DB042.bodb02
	Task: Total Bets - Overview - Super view

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
			--> @PossType: full
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
			-- Stake: company
			,InplayStake1 INT, EarlyStake1 INT, TodayStake1 INT, OutrightStake1 INT
			-- Stake: SMA
			,InplayStake2 INT, EarlyStake2 INT, TodayStake2 INT, OutrightStake2 INT
			-- Stake: MA
			,InplayStake3 INT, EarlyStake3 INT, TodayStake3 INT, OutrightStake3 INT
			-- Stake: Agent
			,InplayStake4 INT, EarlyStake4 INT, TodayStake4 INT, OutrightStake4 INT
			-- Stake: SMA + MA + Agent
			,InplayStake5 INT, EarlyStake5 INT, TodayStake5 INT, OutrightStake5 INT
			-- Stake: SMA + MA
			,InplayStake6 INT, EarlyStake6 INT, TodayStake6 INT, OutrightStake6 INT
			-- Stake: MA + Agent
			,InplayStake7 INT, EarlyStake7 INT, TodayStake7 INT, OutrightStake7 INT
		)

		-- For Parlay
		CREATE TABLE #ParlayTotalBets
		(
			SelectionType TINYINT, Wager INT
			,Stake0 MONEY, Stake1 MONEY, Stake2 MONEY, Stake3 MONEY, Stake4 MONEY, Stake5 MONEY, Stake6 MONEY, Stake7 MONEY
		)

		-- In-play, Early, Today
		BEGIN
			INSERT INTO #TotalBets
			(
				SportTypeGroup
				,InplayWager, EarlyWager, TodayWager
				,InplayStake0, EarlyStake0, TodayStake0
				,InplayStake1, EarlyStake1, TodayStake1
				,InplayStake2, EarlyStake2, TodayStake2
				,InplayStake3, EarlyStake3, TodayStake3
				,InplayStake4, EarlyStake4, TodayStake4
				,InplayStake5, EarlyStake5, TodayStake5
				,InplayStake6, EarlyStake6, TodayStake6
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
					-- Stake: Company
					,SUM(CASE WHEN m.kickofftime <= @TimeNow THEN b.stake * (1 - b.tpositiontaking) ELSE 0 END) AS InplayStake1
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate > @today THEN b.stake * (1 - b.tpositiontaking) ELSE 0 END) AS EarlyStake1
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate <= @today THEN b.stake * (1 - b.tpositiontaking) ELSE 0 END) AS TodayStake1
					-- Stake: SMA
					,SUM(CASE WHEN m.kickofftime <= @TimeNow THEN b.stake * b.spositiontaking ELSE 0 END) AS InplayStake2
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate > @today THEN b.stake * b.spositiontaking ELSE 0 END) AS EarlyStake2
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate <= @today THEN b.stake * b.spositiontaking ELSE 0 END) AS TodayStake2
					-- Stake: MA
					,SUM(CASE WHEN m.kickofftime <= @TimeNow THEN b.stake * b.mpositiontaking ELSE 0 END) AS InplayStake3
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate > @today THEN b.stake * b.mpositiontaking ELSE 0 END) AS EarlyStake3
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate <= @today THEN b.stake * b.mpositiontaking ELSE 0 END) AS TodayStake3
					-- Stake: Agent
					,SUM(CASE WHEN m.kickofftime <= @TimeNow THEN b.stake * b.apositiontaking ELSE 0 END) AS InplayStake4
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate > @today THEN b.stake * b.apositiontaking ELSE 0 END) AS EarlyStake4
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate <= @today THEN b.stake * b.apositiontaking ELSE 0 END) AS TodayStake4
					-- Stake: SMA + MA + Agent
					,SUM(CASE WHEN m.kickofftime <= @TimeNow THEN b.stake * b.tpositiontaking ELSE 0 END) AS InplayStake5
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate > @today THEN b.stake * b.tpositiontaking ELSE 0 END) AS EarlyStake5
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate <= @today THEN b.stake * b.tpositiontaking ELSE 0 END) AS TodayStake5
					-- Stake: SMA + MA
					,SUM(CASE WHEN m.kickofftime <= @TimeNow THEN b.stake * (b.spositiontaking + b.mpositiontaking) ELSE 0 END) AS InplayStake6
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate > @today THEN b.stake * (b.spositiontaking + b.mpositiontaking) ELSE 0 END) AS EarlyStake6
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate <= @today THEN b.stake * (b.spositiontaking + b.mpositiontaking) ELSE 0 END) AS TodayStake6
					-- Stake: MA + Agent
					,SUM(CASE WHEN m.kickofftime <= @TimeNow THEN b.stake * (b.mpositiontaking + b.apositiontaking) ELSE 0 END) AS InplayStake7
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate > @today THEN b.stake * (b.mpositiontaking + b.apositiontaking) ELSE 0 END) AS EarlyStake7
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate <= @today THEN b.stake * (b.mpositiontaking + b.apositiontaking) ELSE 0 END) AS TodayStake7
			FROM #Sports s
				INNER JOIN dbo.match m WITH (NOLOCK) ON s.SportType = m.sporttype
				INNER JOIN dbo.bettrans b WITH (NOLOCK) ON m.matchid = b.matchid
			WHERE b.srecommend = @CustId
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
				,OutrightStake1
				,OutrightStake2
				,OutrightStake3
				,OutrightStake4
				,OutrightStake5
				,OutrightStake6
				,OutrightStake7
			)
			SELECT s.SportTypeGroup
					-- Wager
					,SUM(1) AS OutrightWager
					-- Stake: original
					,SUM(b.stake) AS OutrightStake0
					-- Stake: Company
					,SUM(b.stake * (1 - b.tpositiontaking)) AS OutrightStake1
					-- Stake: SMA
					,SUM(b.stake * b.spositiontaking) AS OutrightStake2
					-- Stake: MA
					,SUM(b.stake * b.mpositiontaking) AS OutrightStake3
					-- Stake: Agent
					,SUM(b.stake * b.apositiontaking) AS OutrightStake4
					-- Stake: SMA + MA + Agent
					,SUM(b.stake * b.tpositiontaking) AS OutrightStake5
					-- Stake: SMA + MA
					,SUM(b.stake * (b.spositiontaking + b.mpositiontaking)) AS OutrightStake6
					-- Stake: MA + Agent
					,SUM(b.stake * (b.mpositiontaking + b.apositiontaking)) AS OutrightStake7
			FROM #Sports s
				INNER JOIN dbo.League l WITH (NOLOCK) ON s.SportType = l.sporttype
				INNER JOIN dbo.outright o WITH (NOLOCK) ON l.leagueid = o.leagueid
				INNER JOIN dbo.bettrans b WITH (NOLOCK) ON o.orid = b.matchid
			WHERE b.srecommend = @CustId
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
			INSERT INTO #ParlayTotalBets (SelectionType, Wager, Stake0, Stake1, Stake2, Stake3, Stake4, Stake5, Stake6, Stake7)
			SELECT
				b.liveawayscore
				,SUM(1) AS Wager
				,SUM(b.stake) AS Stake0
				,SUM(b.stake * (1 - b.tpositiontaking)) AS Stake1
				,SUM(b.stake * b.spositiontaking) AS Stake2
				,SUM(b.stake * b.mpositiontaking) AS Stake3
				,SUM(b.stake * b.apositiontaking) AS Stake4
				,SUM(b.stake * b.tpositiontaking) AS Stake5
				,SUM(b.stake * (b.spositiontaking + b.mpositiontaking)) AS Stake6
				,SUM(b.stake * (b.mpositiontaking + b.apositiontaking)) AS Stake7
			FROM dbo.bettrans b WITH (NOLOCK)
			WHERE b.srecommend = @CustId
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
								WHEN 1 THEN InplayStake1
								WHEN 2 THEN InplayStake2
								WHEN 3 THEN InplayStake3
								WHEN 4 THEN InplayStake4
								WHEN 5 THEN InplayStake5
								WHEN 6 THEN InplayStake6
								WHEN 7 THEN InplayStake7
								END, 0))					AS InplayStake
				,SUM(ISNULL(CASE @PossType
								WHEN 0 THEN TodayStake0
								WHEN 1 THEN TodayStake1
								WHEN 2 THEN TodayStake2
								WHEN 3 THEN TodayStake3
								WHEN 4 THEN TodayStake4
								WHEN 5 THEN TodayStake5
								WHEN 6 THEN TodayStake6
								WHEN 7 THEN TodayStake7
								END, 0))					AS TodayStake
				,SUM(ISNULL(CASE @PossType
								WHEN 0 THEN EarlyStake0
								WHEN 1 THEN EarlyStake1
								WHEN 2 THEN EarlyStake2
								WHEN 3 THEN EarlyStake3
								WHEN 4 THEN EarlyStake4
								WHEN 5 THEN EarlyStake5
								WHEN 6 THEN EarlyStake6
								WHEN 7 THEN EarlyStake7
								END, 0))					AS EarlyStake
				,SUM(ISNULL(CASE @PossType
								WHEN 0 THEN OutrightStake0
								WHEN 1 THEN OutrightStake1
								WHEN 2 THEN OutrightStake2
								WHEN 3 THEN OutrightStake3
								WHEN 4 THEN OutrightStake4
								WHEN 5 THEN OutrightStake5
								WHEN 6 THEN OutrightStake6
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
											WHEN 1 THEN Stake1
											WHEN 2 THEN Stake2
											WHEN 3 THEN Stake3
											WHEN 4 THEN Stake4
											WHEN 5 THEN Stake5
											WHEN 6 THEN Stake6
											WHEN 7 THEN Stake7
											END ELSE 0 END), 0)						AS SoccerParlayStake
				-- Other Sports except Soccer
				,ISNULL(SUM(CASE WHEN SelectionType = 2 THEN 1 ELSE 0 END), 0)		AS NonSoccerParlayWager
				,ISNULL(SUM(CASE WHEN SelectionType = 2 THEN
										CASE @PossType
											WHEN 0 THEN Stake0
											WHEN 1 THEN Stake1
											WHEN 2 THEN Stake2
											WHEN 3 THEN Stake3
											WHEN 4 THEN Stake4
											WHEN 5 THEN Stake5
											WHEN 6 THEN Stake6
											WHEN 7 THEN Stake7
											END ELSE 0 END), 0)						AS NonSoccerParlayStake
				-- Soccer + Other Sports
				,ISNULL(SUM(CASE WHEN SelectionType = 3 THEN 1 ELSE 0 END), 0)		AS MixSportsParlayWager
				,ISNULL(SUM(CASE WHEN SelectionType = 3 THEN
										CASE @PossType
											WHEN 0 THEN Stake0
											WHEN 1 THEN Stake1
											WHEN 2 THEN Stake2
											WHEN 3 THEN Stake3
											WHEN 4 THEN Stake4
											WHEN 5 THEN Stake5
											WHEN 6 THEN Stake6
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
							WHEN 1 THEN ISNULL(InplayStake1, 0) + ISNULL(TodayStake1, 0) + ISNULL(EarlyStake1, 0) + ISNULL(OutrightStake1, 0)
							WHEN 2 THEN ISNULL(InplayStake2, 0) + ISNULL(TodayStake2, 0) + ISNULL(EarlyStake2, 0) + ISNULL(OutrightStake2, 0)
							WHEN 3 THEN ISNULL(InplayStake3, 0) + ISNULL(TodayStake3, 0) + ISNULL(EarlyStake3, 0) + ISNULL(OutrightStake3, 0)
							WHEN 4 THEN ISNULL(InplayStake4, 0) + ISNULL(TodayStake4, 0) + ISNULL(EarlyStake4, 0) + ISNULL(OutrightStake4, 0)
							WHEN 5 THEN ISNULL(InplayStake5, 0) + ISNULL(TodayStake5, 0) + ISNULL(EarlyStake5, 0) + ISNULL(OutrightStake5, 0)
							WHEN 6 THEN ISNULL(InplayStake6, 0) + ISNULL(TodayStake6, 0) + ISNULL(EarlyStake6, 0) + ISNULL(OutrightStake6, 0)
							WHEN 7 THEN ISNULL(InplayStake7, 0) + ISNULL(TodayStake7, 0) + ISNULL(EarlyStake7, 0) + ISNULL(OutrightStake7, 0)
							END) AS Stake
				FROM #TotalBets

				UNION ALL
				SELECT
					SUM(ISNULL(Wager, 0)) AS Wager
					,SUM(CASE @PossType
							WHEN 0 THEN ISNULL(Stake0, 0)
							WHEN 1 THEN ISNULL(Stake1, 0)
							WHEN 2 THEN ISNULL(Stake2, 0)
							WHEN 3 THEN ISNULL(Stake3, 0)
							WHEN 4 THEN ISNULL(Stake4, 0)
							WHEN 5 THEN ISNULL(Stake5, 0)
							WHEN 6 THEN ISNULL(Stake6, 0)
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