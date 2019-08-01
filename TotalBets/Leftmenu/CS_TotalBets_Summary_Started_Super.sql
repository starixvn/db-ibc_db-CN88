/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_TotalBets_Summary_Started_Super]
	@CustId			INT,
	@SubAccId		INT = 0,
	@IsAllDownline	BIT = 1,
	@Type			TINYINT = 5
AS

/*
	Created: 20190419@Sophia
	DB: DBAGE.bodb02
	Task: Total Bets - Left menu of Started  - SMA (Super) view

	Revisions:
		- 20190419@Sophia: initial SP [Redmine: #112032] 

	Param's Explanation:
		@SubAccId: sub account
		@IsAllDownline: is view all downlines
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

		CREATE TABLE #EventInfo (MatchId INT, SportType INT)

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
			AND b.statusId IN (0, 1, 111, 112, 113)
			AND (@IsAllDownline = 1 OR EXISTS (SELECT 1 FROM @Downlines d WHERE b.mrecommend = d.DownlineId))
		GROUP BY
			b.matchid
			,CASE WHEN b.bettype IN (10) THEN b.bettype ELSE 0 END

		IF @@ROWCOUNT <> 0
		BEGIN
			INSERT INTO #EventInfo (MatchId, SportType)
			SELECT MatchId, SportType FROM dbo.CS_f_TotalBets_Event_Sel (@Type, @isTest, 0, '')
		END
	END

	/* ===== Return data ===== */
	BEGIN
		SELECT
			s.SportTypeGroup
			-- Wager
			,SUM(ISNULL(Wager, 0)) AS Wager
			-- Stake
			,SUM(ISNULL(Stake, 0)) AS Stake
		FROM #Sports s
			INNER JOIN dbo.CS_f_SportTypeGroup_OrderSel(2) f ON s.SportTypeGroup = f.SportTypeGroup
			LEFT JOIN (
				SELECT
					e.SportType
					,SUM(t.Wager) AS Wager
					,SUM(t.Stake) AS Stake
				FROM #TotalBets t
					INNER JOIN #EventInfo e ON t.MatchId = e.MatchId
				WHERE t.BetType <> 29
				GROUP BY
					e.SportType
			) AS r ON s.SportType = r.SportType
		GROUP BY s.SportTypeGroup, f.OrderId
		ORDER BY f.OrderId
	END

	DROP TABLE #Sports
	DROP TABLE #TotalBets
	DROP TABLE #EventInfo
END
GO