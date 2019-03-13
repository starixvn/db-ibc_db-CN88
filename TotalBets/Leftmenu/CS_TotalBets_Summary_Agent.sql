/*<info serverAlias="DB042-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_TotalBets_Summary_Agent]
	@CustId	INT,
	@Type	TINYINT = 1
AS

/*
	Created: 20190307@Percy
	DB: DB042.bodb02
	Task: Total Bets - Left menu of In-play/Early/Today/Outright - Agent (Agent) view

	Revisions:
		- 20190307@Percy: Initialize SP [RedmineID: #109693]

	Param's Explanation:
		@Type:
			0 = All
			1 = 'Inplay'
			2 = 'Today'
			3 = 'Early'
			4 = 'Outright'
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
		IF @Type IN (1,2,3)
		BEGIN
			INSERT INTO #TotalBets
			(
				SportTypeGroup
				,InplayWager, EarlyWager, TodayWager
				,InplayStake, EarlyStake, TodayStake
			)
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
			WHERE b.recommend = @CustId
				AND b.statusId IN (0, 1)
				AND m.eventstatus NOT IN ('closed', 'internal')
			GROUP BY s.SportTypeGroup
		END

		-- Outright
		IF @Type IN (4)
		BEGIN
			INSERT INTO #TotalBets
			(
				SportTypeGroup
				,OutrightWager
				,OutrightStake
			)
			SELECT s.SportTypeGroup
					-- Wager
					,SUM(1) AS OutrightWager
					-- Stake
					,SUM(b.stake) AS OutrightStake
			FROM #Sports s
				INNER JOIN dbo.League l WITH (NOLOCK) ON s.SportType = l.sporttype
				INNER JOIN dbo.outright o WITH (NOLOCK) ON l.leagueid = o.leagueid
				INNER JOIN dbo.bettrans b WITH (NOLOCK) ON o.orid = b.matchid
			WHERE b.recommend = @CustId
				AND b.statusId IN (0, 1)
				AND o.oddsstatus IN ('closed', 'running', 'suspend', 'closePrice')
			GROUP BY s.SportTypeGroup
		END
	END

	/* ===== Return data ===== */
	BEGIN
		BEGIN
			DECLARE @isInplay BIT = 0, @isToday BIT = 0, @isEarly BIT = 0, @isOutright BIT = 0
			
			IF @Type = 1
				SELECT @isInplay = 1
			ELSE IF @Type = 2
				SELECT @isToday = 1
			ELSE IF @Type = 3
				SELECT @isEarly = 1
			ELSE IF @Type = 4
				SELECT @isOutright = 1
			
			;WITH CTE_Sports AS (
				SELECT DISTINCT SportTypeGroup FROM #Sports
			)
			SELECT
				s.SportTypeGroup
				-- Wager
				,SUM(
					ISNULL(InplayWager, 0) * @isInplay
					+ ISNULL(TodayWager, 0) * @isToday
					+ ISNULL(EarlyWager, 0) * @isEarly
					+ ISNULL(OutrightWager, 0) * @isOutright
				) AS Wager
				-- Stake
				,SUM(
					ISNULL(InplayStake, 0) * @isInplay
					+ ISNULL(TodayStake, 0) * @isToday
					+ ISNULL(EarlyStake, 0) * @isEarly
					+ ISNULL(OutrightStake, 0) * @isOutright
					) AS Stake
			FROM CTE_Sports s
				LEFT JOIN #TotalBets t ON s.SportTypeGroup = t.SportTypeGroup
			GROUP BY s.SportTypeGroup
			ORDER BY s.SportTypeGroup
		END
	END

	DROP TABLE #Sports
	DROP TABLE #TotalBets
END
GO