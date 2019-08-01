/*<info serverAlias="DB042-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_TotalBets_Overview_Super]
	@CustId			INT,
	@SubAccId		INT = 0,
	@IsAllDownline	BIT = 1,
	@PossType		TINYINT = 0
AS

/*
	Created: 20190307@Percy
	DB: DB042.bodb02
	Task: Total Bets - Overview - Super view

	Revisions:
		- 20190307@Percy: Initialize SP [RedmineID: #109693]
		- 20190418@Percy: Support SB only [RedmineID: #109521]
		- 20190713@Percy: Add sub account - permission on downlines [RedmineID: #116825]

	Param's Explanation:
		@SubAccId: sub account
		@IsAllDownline: is view all downlines
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

	DECLARE @isTest BIT
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	/* ===== Get downline list by Sub Account ==== */
	DECLARE @Downlines TABLE (DownlineId INT)

	IF ISNULL(@SubAccId, 0) <> 0 AND ISNULL(@IsAllDownline, 0) = 0
	BEGIN
		INSERT INTO @Downlines (DownlineId)
		SELECT DownlineId FROM dbo.CS_f_GetDownlineBySubAcc(@SubAccId)
	END
	/* ===== End Get downline list by Sub Account ==== */

	/* ===== Get Data ===== */
	BEGIN
		CREATE TABLE #Sports (SportTypeGroup SMALLINT, SportType INT)
		INSERT INTO #Sports (SportTypeGroup, SportType)
		SELECT DISTINCT SportTypeGroup, SportType FROM dbo.CS_SportBettypeMatrix WITH (NOLOCK)
		WHERE ProductId = 1 -- Sportsbook only
			AND SportTypeGroup <> 9 -- Exclude Parlay
			AND IsTest <= @isTest

		CREATE TABLE #EventInfo (MatchId INT, SportType INT, Type TINYINT)

		CREATE TABLE #TotalBets
		(
			MatchId INT
			-- for outright (bettype = 10), parlay (bettype = 29, selectiontype = liveawayscore)
			,BetType INT, SelectionType TINYINT
			-- Wager
			,Wager INT
			-- Stake
			,Stake0 MONEY, Stake1 MONEY, Stake2 MONEY, Stake3 MONEY, Stake4 MONEY, Stake5 MONEY, Stake6 MONEY, Stake7 MONEY
		)
		
		INSERT INTO #TotalBets
		(
			MatchId, BetType, SelectionType
			,Wager
			,Stake0
			,Stake1
			,Stake2
			,Stake3
			,Stake4
			,Stake5
			,Stake6
			,Stake7
		)
		SELECT
			b.matchid
			,CASE WHEN b.bettype IN (10, 29) THEN b.bettype ELSE 0 END AS bettype
			/* <== liveawayscore <==> 1: Soccer only <==> 2: Other Sports except Soccer <==> 3: Soccer + Other Sports ==> */
			,CASE WHEN b.bettype IN (29) THEN b.liveawayscore ELSE 0 END AS SelectionType
			-- Wager
			,COUNT(1) AS Wager
			-- Stake: original
			,SUM(b.stake) AS Stake0
			-- Stake: Company
			,SUM(b.stake * (1 - b.tpositiontaking)) AS Stake1
			-- Stake: SMA
			,SUM(b.stake * b.spositiontaking) AS Stake2
			-- Stake: MA
			,SUM(b.stake * b.mpositiontaking) AS Stake3
			-- Stake: Agent
			,SUM(b.stake * b.apositiontaking) AS Stake4
			-- Stake: SMA + MA + Agent
			,SUM(b.stake * b.tpositiontaking) AS Stake5
			-- Stake: SMA + MA
			,SUM(b.stake * (b.spositiontaking + b.mpositiontaking)) AS Stake6
			-- Stake: MA + Agent
			,SUM(b.stake * (b.mpositiontaking + b.apositiontaking)) AS Stake7
		FROM dbo.bettrans b WITH (NOLOCK)
		WHERE b.srecommend = @CustId
			AND b.statusId IN (0, 1)
			AND (@IsAllDownline = 1 OR EXISTS (SELECT 1 FROM @Downlines d WHERE b.mrecommend = d.DownlineId))
		GROUP BY
			b.matchid
			,CASE WHEN b.bettype IN (10, 29) THEN b.bettype ELSE 0 END
			,CASE WHEN b.bettype IN (29) THEN b.liveawayscore ELSE 0 END

		IF @@ROWCOUNT <> 0
		BEGIN
			INSERT INTO #EventInfo (MatchId, SportType, Type)
			SELECT MatchId, SportType, Type FROM dbo.CS_f_TotalBets_Event_Sel (0, @isTest, 0, '')
			WHERE Type IN (1,2,3,4) -- In-play, Today, Early, Outright
		END
	END

	/* ===== Return data ===== */
	BEGIN
			-- 1. Detail by Sports
			SELECT
				s.SportTypeGroup
				-- Wager
				,SUM(CASE WHEN r.Type = 1 THEN ISNULL(Wager, 0) ELSE 0 END) AS InplayWager
				,SUM(CASE WHEN r.Type = 2 THEN ISNULL(Wager, 0) ELSE 0 END) AS TodayWager
				,SUM(CASE WHEN r.Type = 3 THEN ISNULL(Wager, 0) ELSE 0 END) AS EarlyWager
				,SUM(CASE WHEN r.Type = 4 THEN ISNULL(Wager, 0) ELSE 0 END) AS OutrightWager
				-- Stake
				,SUM(CASE WHEN r.Type = 1 THEN ISNULL(CASE @PossType
															WHEN 0 THEN Stake0
															WHEN 1 THEN Stake1
															WHEN 2 THEN Stake2
															WHEN 3 THEN Stake3
															WHEN 4 THEN Stake4
															WHEN 5 THEN Stake5
															WHEN 6 THEN Stake6
															WHEN 7 THEN Stake7
															END, 0) ELSE 0 END) AS InplayStake
				,SUM(CASE WHEN r.Type = 2 THEN ISNULL(CASE @PossType
															WHEN 0 THEN Stake0
															WHEN 1 THEN Stake1
															WHEN 2 THEN Stake2
															WHEN 3 THEN Stake3
															WHEN 4 THEN Stake4
															WHEN 5 THEN Stake5
															WHEN 6 THEN Stake6
															WHEN 7 THEN Stake7
															END, 0) ELSE 0 END) AS TodayStake
				,SUM(CASE WHEN r.Type = 3 THEN ISNULL(CASE @PossType
															WHEN 0 THEN Stake0
															WHEN 1 THEN Stake1
															WHEN 2 THEN Stake2
															WHEN 3 THEN Stake3
															WHEN 4 THEN Stake4
															WHEN 5 THEN Stake5
															WHEN 6 THEN Stake6
															WHEN 7 THEN Stake7
															END, 0) ELSE 0 END) AS EarlyStake
				,SUM(CASE WHEN r.Type = 4 THEN ISNULL(CASE @PossType
															WHEN 0 THEN Stake0
															WHEN 1 THEN Stake1
															WHEN 2 THEN Stake2
															WHEN 3 THEN Stake3
															WHEN 4 THEN Stake4
															WHEN 5 THEN Stake5
															WHEN 6 THEN Stake6
															WHEN 7 THEN Stake7
															END, 0) ELSE 0 END) AS OutrightStake
			FROM #Sports s
				INNER JOIN dbo.CS_f_SportTypeGroup_OrderSel(2) f ON s.SportTypeGroup = f.SportTypeGroup
				LEFT JOIN (
					SELECT
						e.SportType, e.Type
						,SUM(t.Wager) AS Wager
						,SUM(t.Stake0) AS Stake0
						,SUM(t.Stake1) AS Stake1
						,SUM(t.Stake2) AS Stake2
						,SUM(t.Stake3) AS Stake3
						,SUM(t.Stake4) AS Stake4
						,SUM(t.Stake5) AS Stake5
						,SUM(t.Stake6) AS Stake6
						,SUM(t.Stake7) AS Stake7
					FROM #TotalBets t
						INNER JOIN #EventInfo e ON t.MatchId = e.MatchId
					WHERE t.BetType <> 29
					GROUP BY
						e.SportType, e.Type
				) AS r ON s.SportType = r.SportType
			GROUP BY s.SportTypeGroup, f.OrderId
			ORDER BY f.OrderId

			-- 2. Parlay
			SELECT
				9 AS SportTypeGroup
				-- Soccer only
				,ISNULL(SUM(CASE WHEN SelectionType = 1 THEN Wager ELSE 0 END), 0)	AS SoccerParlayWager
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
				,ISNULL(SUM(CASE WHEN SelectionType = 2 THEN Wager ELSE 0 END), 0)	AS NonSoccerParlayWager
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
				,ISNULL(SUM(CASE WHEN SelectionType = 3 THEN Wager ELSE 0 END), 0)	AS MixSportsParlayWager
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
			FROM #TotalBets
			WHERE bettype = 29
			
			-- 3. Total
			SELECT
				ISNULL(SUM(Wager), 0) AS Wager
				,ISNULL(SUM(CASE @PossType
						WHEN 0 THEN Stake0
						WHEN 1 THEN Stake1
						WHEN 2 THEN Stake2
						WHEN 3 THEN Stake3
						WHEN 4 THEN Stake4
						WHEN 5 THEN Stake5
						WHEN 6 THEN Stake6
						WHEN 7 THEN Stake7
						END), 0) AS Stake
			FROM #TotalBets t
				LEFT JOIN #EventInfo e ON t.MatchId = e.MatchId
			WHERE t.BetType = 29 OR e.MatchId IS NOT NULL
	END

	DROP TABLE #Sports
	DROP TABLE #TotalBets
	DROP TABLE #EventInfo
END
GO