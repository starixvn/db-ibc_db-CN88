/*<info serverAlias="DB042-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_TotalBets_Overview_Super]
	@CustId		INT,
	@TypeName	VARCHAR(20) = 'Overview',
	@PossType	TINYINT = 0
AS

/*
	Created: 20190307@Percy
	DB: DB042.bodb02
	Task: Total Bets - Overview - Super view

	Revisions:
		- 20190307@Percy: Initialize SP [RedmineID: #109693]

	Param's Explanation:
		@TypeName: Overview, Inplay, Early, Outright
		@PossType:
				= 0:	Full Percentage
				= 1:	Company %: Shown on SMA
				= 2:	SMA %: Shown on SMA
				= 3:	MA%: Shown on SMA, MA
				= 4:	Agent%
				= 5:	SMA + MA + Agent%: Shown on SMA
				= 6:	SMA + MA %: Shown on SMA
				= 7:	MA + Agent %: Shown on SMA, MA
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

		-- In-play, Early, Today
		IF @TypeName IN ('Overview', 'Inplay', 'Early', 'Today')
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
		IF @TypeName IN ('Overview', 'Outright')
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
			GROUP BY s.SportTypeGroup
		END

		-- Parlay
		--IF @TypeName IN ('Overview', 'Parlay')
		--BEGIN
		--	INSERT INTO #TotalBets (SportTypeGroup, 
		--END
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

		-- 2. Parlay & Total
		IF @TypeName = 'Overview'
		BEGIN
			-- 3. Parlay
			SELECT
				1 AS SportTypeGroup
				,100 AS SoccerParlayStake,	1 AS SoccerParlayWager
				,200 AS NonSoccerParlayStake,	2 AS NonSoccerParlayWager
				,300 AS MixSportsParlayStake,	3 AS MixSportsParlayWager
			
			-- 1. Total
			SELECT 1 AS TotalWagers, 100 AS TotalStake
		END
	END

	DROP TABLE #Sports
	DROP TABLE #TotalBets
END
GO