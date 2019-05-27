/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Rpt_MemberStatement_Sel]
	@CustId			INT,
	@SportTypeGroup	INT = 0,
	@FromDate		SMALLDATETIME,
	@ToDate			SMALLDATETIME,
	@MoveBetsDay	SMALLDATETIME,
	@BalanceUpDay	SMALLDATETIME
AS

/*
	Created: 20190227@Percy
	DB: DBAGE.bodb02
	Task: Member Statement

	Revisions:
		- 20190227@Percy: Initialize SP [RedmineID: #105660]
		- 20190328@Percy: Implement Non-Sports [RedmineID: #109521]
*/

BEGIN
	SET NOCOUNT ON
	
	-- Check SP Version
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	-- Get Sport List
	DECLARE @SportTypeList TABLE (SportType SMALLINT PRIMARY KEY)
     
	INSERT INTO @SportTypeList (SportType)
	SELECT DISTINCT SportType FROM dbo.CS_f_SporttypeMatrix_Sel (0, @SporttypeGroup, 0, @isTest)
	-- End Get Sport List

	-- Get Bet Type List
	DECLARE @BetTypeList TABLE (BetType INT, EventType INT)

	INSERT INTO @BetTypeList (BetType, EventType)
	SELECT DISTINCT BetType, EventType FROM dbo.CS_f_BettypeMatrix_Sel (0, @SporttypeGroup, 0, @isTest)
	-- End Get Bet Type List

	-- Get data
	DECLARE @tempFromDate SMALLDATETIME, @tempToDate SMALLDATETIME

	CREATE TABLE #tmpData (WinlostDate SMALLDATETIME, MatchId INT, EventType TINYINT, Stake MONEY, ValidStake MONEY, WinLoss MONEY)
	CREATE TABLE #Statement (WinlostDate SMALLDATETIME, Stake MONEY, ValidStake MONEY, WinLoss MONEY)

	-- 1. bettrans
	IF @ToDate > @MoveBetsDay
	BEGIN
		SELECT @tempFromDate = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
		SELECT @tempToDate = @ToDate

		INSERT INTO #tmpData (WinlostDate, MatchId, EventType, Stake, ValidStake, WinLoss)
		SELECT b.winlostdate, b.matchid, bt.EventType
			,SUM(b.stake), SUM(ABS(b.winlost - b.actual_stake)), SUM(b.winlost - b.actual_stake + b.playercomm)
		FROM dbo.bettrans b WITH (NOLOCK)
			INNER JOIN @BetTypeList bt ON b.bettype = bt.bettype
		WHERE b.CustId = @CustId
			AND b.winlostdate BETWEEN @tempFromDate AND @tempToDate
			AND b.statusID NOT IN (0, 1)
		GROUP BY b.winlostdate, b.matchid, bt.EventType
	END

	-- 2. bettrans14
	IF @FromDate <= @MoveBetsDay
	BEGIN
		SELECT @tempFromDate = CASE WHEN @FromDate < @BalanceUpDay THEN @BalanceUpDay ELSE @FromDate END
		SELECT @tempToDate = CASE WHEN @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

		INSERT INTO #tmpData (WinlostDate, MatchId, EventType, Stake, ValidStake, WinLoss)
		SELECT b.winlostdate, b.matchid, bt.EventType
			,SUM(b.stake), SUM(ABS(b.winlost - b.actual_stake)), SUM(b.winlost - b.actual_stake + b.playercomm)
		FROM dbo.bettrans14 b WITH (NOLOCK)
			INNER JOIN @BetTypeList bt ON b.bettype = bt.bettype
		WHERE b.CustId = @CustId
			AND b.winlostdate BETWEEN @tempFromDate AND @tempToDate
		GROUP BY b.winlostdate, b.matchid, bt.EventType
	END

	-- Get final data
	BEGIN
		-- not event info: eventtype = 0
		INSERT INTO #Statement (WinlostDate, Stake, ValidStake, WinLoss)
		SELECT t.WinlostDate, t.Stake, t.ValidStake, t.WinLoss
		FROM #tmpData t
		WHERE t.EventType = 0
			AND (
				@SportTypeGroup = 0
				OR (@SportTypeGroup = 9 AND t.MatchId = 29) -- Sportsbook Parlay
				OR (@SportTypeGroup = 12 AND t.MatchId IN (202, 220)) -- Keno/Lottery
				OR (@SportTypeGroup = 13 AND t.MatchId = 2799) -- Virtual Sports Parlay
			)

		IF @ToDate > @MoveBetsDay
		BEGIN
			-- match: eventtype = 1
			INSERT INTO #Statement (WinlostDate, Stake, ValidStake, WinLoss)
			SELECT t.WinlostDate, t.Stake, t.ValidStake, t.WinLoss
			FROM #tmpData t
				INNER JOIN dbo.match m WITH (NOLOCK) ON t.MatchId = m.matchid
				INNER JOIN @SportTypeList s ON m.sporttype = s.SportType
			WHERE m.eventdate > @MoveBetsDay AND t.EventType = 1

			-- outright: eventtype = 2
			INSERT INTO #Statement (WinlostDate, Stake, ValidStake, WinLoss)
			SELECT t.WinlostDate, t.Stake, t.ValidStake, t.WinLoss
			FROM #tmpData t
				INNER JOIN dbo.outright o WITH (NOLOCK) ON t.MatchId = o.orid
				INNER JOIN dbo.League l WITH (NOLOCK) ON o.leagueid = l.leagueid
				INNER JOIN @SportTypeList s ON l.sporttype = s.SportType
			WHERE o.eventdate > @MoveBetsDay AND t.EventType = 2

			-- VSOutright/VSRaceInfo: eventtype = 3
			INSERT INTO #Statement (WinlostDate, Stake, ValidStake, WinLoss)
			SELECT t.WinlostDate, t.Stake, t.ValidStake, t.WinLoss
			FROM #tmpData t
				INNER JOIN dbo.VSRaceInfo r WITH (NOLOCK) ON t.MatchId = r.EventID
				INNER JOIN @SportTypeList s ON r.sporttype = s.SportType
			WHERE t.EventType = 3
				AND EXISTS (SELECT 1 FROM dbo.VSOutright o WITH (NOLOCK) WHERE o.EventID = r.EventID AND o.eventdate > @MoveBetsDay)
		END

		IF @FromDate <= @MoveBetsDay
		BEGIN
			-- match: eventtype = 1
			INSERT INTO #Statement (WinlostDate, Stake, ValidStake, WinLoss)
			SELECT t.WinlostDate, t.Stake, t.ValidStake, t.WinLoss
			FROM #tmpData t
				INNER JOIN dbo.match14 m WITH (NOLOCK) ON t.MatchId = m.matchid
				INNER JOIN @SportTypeList s ON m.sporttype = s.SportType
			WHERE m.eventdate <= @MoveBetsDay AND t.EventType = 1

			-- outright: eventtype = 2
			INSERT INTO #Statement (WinlostDate, Stake, ValidStake, WinLoss)
			SELECT t.WinlostDate, t.Stake, t.ValidStake, t.WinLoss
			FROM #tmpData t
				INNER JOIN dbo.outright14 o WITH (NOLOCK) ON t.MatchId = o.orid
				INNER JOIN dbo.League l WITH (NOLOCK) ON o.leagueid = l.leagueid
				INNER JOIN @SportTypeList s ON l.sporttype = s.SportType
			WHERE o.eventdate <= @MoveBetsDay AND t.EventType = 2

			-- VSOutright/VSRaceInfo: eventtype = 3
			INSERT INTO #Statement (WinlostDate, Stake, ValidStake, WinLoss)
			SELECT t.WinlostDate, t.Stake, t.ValidStake, t.WinLoss
			FROM #tmpData t
				INNER JOIN dbo.VSRaceInfo r WITH (NOLOCK) ON t.MatchId = r.EventID
				INNER JOIN @SportTypeList s ON r.sporttype = s.SportType
			WHERE t.EventType = 3
				AND EXISTS (SELECT 1 FROM dbo.VSOutright14 o WITH (NOLOCK) WHERE o.EventID = r.EventID AND o.eventdate <= @MoveBetsDay)
		END
	END
	
	-- Return data
	;WITH CTE_WinlostDate AS
	(
		SELECT @FromDate AS WinlostDate
		UNION ALL
		SELECT DATEADD(DAY, 1, WinlostDate)
		FROM CTE_WinlostDate
		WHERE WinlostDate < @ToDate
	)
	,CTE_Statement AS
	(
		SELECT
			WinlostDate
			,SUM(ISNULL(Stake, 0)) AS Stake
			,SUM(ISNULL(ValidStake, 0)) AS ValidStake
			,SUM(ISNULL(Winloss, 0)) AS Winloss
		FROM #Statement s
		GROUP BY WinlostDate
	)
	SELECT
		wld.WinlostDate
		,s.Stake
		,s.ValidStake
		,s.Winloss
	FROM CTE_WinlostDate wld
		LEFT JOIN CTE_Statement s ON wld.WinlostDate = s.WinlostDate
	ORDER BY
		WinlostDate DESC

	DROP TABLE #Statement
	DROP TABLE #tmpData
END
GO