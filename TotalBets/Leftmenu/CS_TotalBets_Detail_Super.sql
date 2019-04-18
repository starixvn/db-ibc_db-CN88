/*<info serverAlias="DB042-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_TotalBets_Detail_Super]
	@CustId			INT,
	@Type			TINYINT = 1,
	@SportTypeGroup	SMALLINT = 1
AS

/*
	Created: 20190307@Percy
	DB: DB042.bodb02
	Task: Total Bets - Left menu of In-play/Early/Today/Outright - Drilldown by SportTypeGroup - SMA (Super) view

	Revisions:
		- 20190307@Percy: Initialize SP [RedmineID: #109693]
		- 20190418@Percy: Support SB only + Return IsNeutral [RedmineID: #109521]

	Param's Explanation:
		@Type:
			1 = 'Inplay'
			2 = 'Today'
			3 = 'Early'
			4 = 'Outright'
			5 = 'Started'
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @isTest BIT
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	/* ===== Get Data ===== */
	BEGIN
		CREATE TABLE #Sports (SportTypeGroup SMALLINT, SportType INT)
		INSERT INTO #Sports (SportTypeGroup, SportType)
		SELECT DISTINCT SportTypeGroup, SportType FROM dbo.CS_SportBettypeMatrix WITH (NOLOCK)
		WHERE SportTypeGroup = @SportTypeGroup
			AND ProductID = 1 -- Sportsbook only
			AND SportTypeGroup <> 9 -- Exclude Parlay
			AND IsTest <= @isTest

		CREATE TABLE #EventInfo (MatchId INT, SportType INT, LeagueId INT, HomeId INT, AwayId INT, IsNeutral BIT)

		CREATE TABLE #TotalBets
		(
			MatchId INT
			-- for outright (bettype = 10)
			,BetType INT
			-- Wager
			,Wager INT
			-- Stake
			,Stake MONEY
		)

		INSERT INTO #TotalBets
		(
			MatchId
			,BetType
			,Wager
			,Stake
		)
		SELECT
			b.matchid
			,CASE WHEN b.bettype IN (10) THEN b.bettype ELSE 0 END AS bettype
			-- Wager
			,COUNT(1) AS Wager
			-- Stake
			,SUM(b.stake) AS Stake
		FROM dbo.bettrans b WITH (NOLOCK)
		WHERE b.srecommend = @CustId
			AND b.statusId IN (0, 1)
		GROUP BY
			b.matchid
			,CASE WHEN b.bettype IN (10) THEN b.bettype ELSE 0 END

		IF @@ROWCOUNT <> 0
		BEGIN
			INSERT INTO #EventInfo (MatchId, SportType, LeagueId, HomeId, AwayId, IsNeutral)
			SELECT MatchId, SportType, LeagueId, HomeId, AwayId, IsNeutral FROM dbo.CS_f_TotalBets_Event_Sel (@Type, @isTest, 0, '')
		END
	END

	/* ===== Return data ===== */
	BEGIN
		SELECT
			r.MatchId, r.LeagueId, r.HomeId, r.AwayId, r.IsNeutral
			-- Wager
			,SUM(ISNULL(Wager, 0)) AS Wager
			-- Stake
			,SUM(ISNULL(Stake, 0)) AS Stake
		FROM #Sports s
			INNER JOIN (
				SELECT
					e.SportType, e.MatchId, e.LeagueId, e.HomeId, e.AwayId, e.IsNeutral
					,SUM(t.Wager) AS Wager
					,SUM(t.Stake) AS Stake
				FROM #TotalBets t
					INNER JOIN #EventInfo e ON t.MatchId = e.MatchId
				WHERE t.BetType <> 29
				GROUP BY
					e.SportType, e.MatchId, e.LeagueId, e.HomeId, e.AwayId, e.IsNeutral
			) AS r ON s.SportType = r.SportType
		GROUP BY
			r.MatchId, r.LeagueId, r.HomeId, r.AwayId, r.IsNeutral
	END

	DROP TABLE #Sports
	DROP TABLE #TotalBets
	DROP TABLE #EventInfo
END
GO