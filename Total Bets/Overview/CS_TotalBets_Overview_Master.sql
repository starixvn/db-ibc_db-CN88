/*<info serverAlias="DB042-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_TotalBets_Overview_Master]
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
		@TypeName: Overview, In-play, Early, Outright
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
			-- Stake
			,InplayStake INT, EarlyStake INT, TodayStake INT, OutrightStake INT
		)

		-- In-play, Early, Today
		IF @TypeName IN ('Overview', 'In-play', 'Early', 'Today')
		BEGIN
			INSERT INTO #TotalBets (SportTypeGroup, InplayWager, EarlyWager, TodayWager, InplayStake, EarlyStake, TodayStake)
			SELECT s.SportTypeGroup
					-- Wager
					,SUM(CASE WHEN m.kickofftime <= @TimeNow THEN 1 ELSE 0 END) AS InplayWager
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate > @today THEN 1 ELSE 0 END) AS EarlyWager
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate <= @today THEN 1 ELSE 0 END) AS TodayWager
					-- Stake
					,SUM(CASE WHEN m.kickofftime <= @TimeNow THEN b.stake ELSE 0 END) AS InplayStake
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate > @today THEN b.stake ELSE 0 END) AS EarlyStake
					,SUM(CASE WHEN m.kickofftime > @TimeNow AND m.eventdate <= @today THEN b.stake ELSE 0 END) AS TodayStake
			FROM #Sports s
				INNER JOIN dbo.match m WITH (NOLOCK) ON s.SportType = m.sporttype
				INNER JOIN dbo.bettrans b WITH (NOLOCK) ON m.matchid = b.matchid
			GROUP BY s.SportTypeGroup
		END

		-- Outright
		IF @TypeName IN ('Overview', 'Outright')
		BEGIN
			INSERT INTO #TotalBets (SportTypeGroup, InplayWager, EarlyWager, TodayWager, InplayStake, EarlyStake, TodayStake)
			SELECT s.SportTypeGroup
					-- Wager
					,SUM(CASE WHEN o.kickofftime <= @TimeNow THEN 1 ELSE 0 END) AS InplayWager
					,SUM(CASE WHEN o.kickofftime > @TimeNow AND o.eventdate > @today THEN 1 ELSE 0 END) AS EarlyWager
					,SUM(CASE WHEN o.kickofftime > @TimeNow AND o.eventdate <= @today THEN 1 ELSE 0 END) AS TodayWager
					-- Stake
					,SUM(CASE WHEN o.kickofftime <= @TimeNow THEN b.stake ELSE 0 END) AS InplayStake
					,SUM(CASE WHEN o.kickofftime > @TimeNow AND o.eventdate > @today THEN b.stake ELSE 0 END) AS EarlyStake
					,SUM(CASE WHEN o.kickofftime > @TimeNow AND o.eventdate <= @today THEN b.stake ELSE 0 END) AS TodayStake
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
			,SUM(ISNULL(InplayStake, 0))	AS InplayStake
			,SUM(ISNULL(TodayStake, 0))		AS TodayStake
			,SUM(ISNULL(EarlyStake, 0))		AS EarlyStake
			,SUM(ISNULL(OutrightStake, 0))	AS OutrightStake
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
				,100 AS ParlayStake,	1 AS ParlayWager
			
			-- 1. Total
			SELECT 1 AS TotalWagers, 100 AS TotalStake
		END
	END

	DROP TABLE #Sports
	DROP TABLE #TotalBets
END
GO