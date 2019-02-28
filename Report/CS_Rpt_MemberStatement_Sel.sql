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
	DECLARE @SportTypeList TABLE (SportType SMALLINT PRIMARY KEY, ProductID INT)
     
	INSERT INTO @SportTypeList (SportType, ProductID)
	SELECT DISTINCT SportType, ProductID FROM bodb02.dbo.f_CS_SporttypeMatrix_Sel (0, @SporttypeGroup, 0, @isTest)
	-- End Get Sport List

	-- Get data
	DECLARE @tempFromDate SMALLDATETIME, @tempToDate SMALLDATETIME

	CREATE TABLE #Statement (WinlostDate SMALLDATETIME, Stake MONEY, ValidStake MONEY, WinLoss MONEY)

	-- 1. bettrans
	IF @ToDate > @MoveBetsDay
	BEGIN
		SELECT @tempFromDate = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
		SELECT @tempToDate = @ToDate

		INSERT INTO #Statement (WinlostDate, Stake, ValidStake, WinLoss)
		SELECT b.winlostdate, SUM(b.stake), SUM(ABS(b.winlost - b.actual_stake)), SUM(b.winlost - b.actual_stake + b.playercomm)
		FROM dbo.bettrans b WITH (NOLOCK)
			INNER JOIN dbo.match m WITH (NOLOCK) ON b.matchid = m.matchid
			INNER JOIN @SportTypeList st ON m.SportType = st.SportType
		WHERE b.CustId = @CustId
			AND b.winlostdate BETWEEN @tempFromDate AND @tempToDate
		GROUP BY b.winlostdate
	END

	-- 2. bettrans14
	IF @FromDate <= @MoveBetsDay
	BEGIN
		SELECT @tempFromDate = CASE WHEN @FromDate < @BalanceUpDay THEN @BalanceUpDay ELSE @FromDate END
		SELECT @tempToDate = CASE WHEN @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

		INSERT INTO #Statement (WinlostDate, Stake, ValidStake, WinLoss)
		SELECT b.winlostdate, SUM(b.stake), SUM(ABS(b.winlost - b.actual_stake)), SUM(b.winlost - b.actual_stake + b.playercomm)
		FROM dbo.bettrans14 b WITH (NOLOCK)
			INNER JOIN dbo.match14 m WITH (NOLOCK) ON b.matchid = m.matchid
			INNER JOIN @SportTypeList st ON m.SportType = st.SportType
		WHERE b.CustId = @CustId
			AND b.winlostdate BETWEEN @tempFromDate AND @tempToDate
		GROUP BY b.winlostdate
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
	SELECT
		wld.WinlostDate
		,SUM(ISNULL(s.Stake, 0)) AS Stake
		,SUM(ISNULL(s.ValidStake, 0)) AS ValidStake
		,SUM(ISNULL(s.Winloss, 0)) AS Winloss
	FROM CTE_WinlostDate wld
		LEFT JOIN #Statement s ON wld.WinlostDate = s.WinlostDate
	GROUP BY
		wld.WinlostDate
	ORDER BY
		WinlostDate DESC

	DROP TABLE #Statement
END
GO