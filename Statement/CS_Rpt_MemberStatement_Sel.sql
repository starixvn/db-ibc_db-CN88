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
*/

BEGIN
	SET NOCOUNT ON
	
	-- Check SP Version
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	-- Get Sport List
	DECLARE @SportTypeList TABLE (SportType SMALLINT PRIMARY KEY)
     
	INSERT INTO @SportTypeList (SportType)
	SELECT DISTINCT SportType FROM bodb02.dbo.CS_f_SporttypeMatrix_Sel (0, @SporttypeGroup, 0, @isTest)
	-- End Get Sport List

	-- Get data
	DECLARE @tempFromDate SMALLDATETIME, @tempToDate SMALLDATETIME

	CREATE TABLE #tmpData (WinlostDate SMALLDATETIME, MatchId INT, Bettype INT, Stake MONEY, ValidStake MONEY, WinLoss MONEY)
	CREATE TABLE #Statement (WinlostDate SMALLDATETIME, Stake MONEY, ValidStake MONEY, WinLoss MONEY)

	-- 1. bettrans
	IF @ToDate > @MoveBetsDay
	BEGIN
		SELECT @tempFromDate = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
		SELECT @tempToDate = @ToDate

		INSERT INTO #tmpData (WinlostDate, MatchId, Bettype, Stake, ValidStake, WinLoss)
		SELECT b.winlostdate, b.matchid, CASE WHEN b.bettype IN (10, 29) THEN b.bettype ELSE 0 END
			,SUM(b.actual_stake), SUM(ABS(b.winlost - b.actual_stake)), SUM(b.winlost - b.actual_stake + b.playercomm)
		FROM dbo.bettrans b WITH (NOLOCK)
		WHERE b.CustId = @CustId
			AND b.winlostdate BETWEEN @tempFromDate AND @tempToDate
			AND b.statusID NOT IN (0, 1)
		GROUP BY b.winlostdate, b.matchid, CASE WHEN b.bettype IN (10, 29) THEN b.bettype ELSE 0 END
	END

	-- 2. bettrans14
	IF @FromDate <= @MoveBetsDay
	BEGIN
		SELECT @tempFromDate = CASE WHEN @FromDate < @BalanceUpDay THEN @BalanceUpDay ELSE @FromDate END
		SELECT @tempToDate = CASE WHEN @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

		INSERT INTO #tmpData (WinlostDate, MatchId, Bettype, Stake, ValidStake, WinLoss)
		SELECT b.winlostdate, b.matchid, CASE WHEN b.bettype IN (10, 29) THEN b.bettype ELSE 0 END
			,SUM(b.actual_stake), SUM(ABS(b.winlost - b.actual_stake)), SUM(b.winlost - b.actual_stake + b.playercomm)
		FROM dbo.bettrans14 b WITH (NOLOCK)
		WHERE b.CustId = @CustId
			AND b.winlostdate BETWEEN @tempFromDate AND @tempToDate
		GROUP BY b.winlostdate, b.matchid, CASE WHEN b.bettype IN (10, 29) THEN b.bettype ELSE 0 END
	END

	-- Get final data
	BEGIN
		INSERT INTO #Statement (WinlostDate, Stake, ValidStake, WinLoss)
		SELECT WinlostDate, Stake, ValidStake, WinLoss
		FROM #tmpData WHERE bettype = 29 AND @SportTypeGroup IN (0,9) -- Parlay

		IF @ToDate > @MoveBetsDay
		BEGIN
			INSERT INTO #Statement (WinlostDate, Stake, ValidStake, WinLoss)
			SELECT WinlostDate, Stake, ValidStake, WinLoss
			FROM #tmpData t
				INNER JOIN dbo.match m WITH (NOLOCK) ON t.MatchId = m.matchid
				INNER JOIN @SportTypeList s ON m.sporttype = s.SportType
			WHERE m.eventdate > @MoveBetsDay AND t.Bettype = 0

			INSERT INTO #Statement (WinlostDate, Stake, ValidStake, WinLoss)
			SELECT WinlostDate, Stake, ValidStake, WinLoss
			FROM #tmpData t
				INNER JOIN dbo.outright o WITH (NOLOCK) ON t.MatchId = o.orid
				INNER JOIN dbo.League l WITH (NOLOCK) ON o.leagueid = l.leagueid
				INNER JOIN @SportTypeList s ON l.sporttype = s.SportType
			WHERE o.eventdate > @MoveBetsDay AND t.Bettype = 10
		END

		IF @FromDate <= @MoveBetsDay
		BEGIN
			INSERT INTO #Statement (WinlostDate, Stake, ValidStake, WinLoss)
			SELECT WinlostDate, Stake, ValidStake, WinLoss
			FROM #tmpData t
				INNER JOIN dbo.match14 m WITH (NOLOCK) ON t.MatchId = m.matchid
				INNER JOIN @SportTypeList s ON m.sporttype = s.SportType
			WHERE m.eventdate <= @MoveBetsDay AND t.Bettype = 0

			INSERT INTO #Statement (WinlostDate, Stake, ValidStake, WinLoss)
			SELECT WinlostDate, Stake, ValidStake, WinLoss
			FROM #tmpData t
				INNER JOIN dbo.outright14 o WITH (NOLOCK) ON t.MatchId = o.orid
				INNER JOIN dbo.League l WITH (NOLOCK) ON o.leagueid = l.leagueid
				INNER JOIN @SportTypeList s ON l.sporttype = s.SportType
			WHERE o.eventdate <= @MoveBetsDay AND t.Bettype = 10
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