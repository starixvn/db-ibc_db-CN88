/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Rpt_Winloss_Headline]
	@ReportMode			TINYINT = 1,
	@FromDate			SMALLDATETIME,
	@ToDate				SMALLDATETIME,
	@ArchiveDate		SMALLDATETIME,
	@MoveBetsDay		SMALLDATETIME,
	@SporttypeGroup		SMALLINT = 0, -- all
	@BettypeGroup		SMALLINT = 0, -- all
	@IsLive				TINYINT = 2,  -- all
	@IsExcludedTest		BIT = 1
AS

/*
	Created: 20190521@Percy
	Task: CN88 - Headline Settled Report - Company view all Headlines
	DB: DBAGE.bodb02
	
	Revisions:
		- 20190521@Percy: Initialize SP [Redmine: #113828]
		- 20190703@Percy: Temporarily add @ReportMode for web input - will implement later [RedmineID: #116082]
		- 20190801@Percy: Change way get ExtraPT amount [RedmineID: #117909]
		
	Param's Explanation:
		- @ReportMode: 1: current, 2: history
		- @SporttypeGroup: default = 0: All
		- @BettypeGroup: default = 0: All
		- @IsLive: (market) default = 2: All
									= 1: Live
									= 0: Dead
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @isTest BIT
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	CREATE TABLE #tblSportType (SportType INT)
	INSERT INTO #tblSportType (SportType)
	SELECT DISTINCT SportType FROM dbo.CS_f_SporttypeMatrix_Sel (0, @SportTypeGroup, @BetTypeGroup, @IsTest)

	CREATE TABLE #tblBetType (ProductID INT, BetType INT, EventType TINYINT)
	INSERT INTO #tblBetType (ProductID, BetType, EventType)
	SELECT DISTINCT ProductID, BetType, EventType FROM dbo.CS_f_BettypeMatrix_Sel (0, @SportTypeGroup, @BetTypeGroup, @IsTest)

	DECLARE @ExtraPT TABLE (SuperID INT, ProductID INT, ExtraPT DECIMAL(9,8), FromDate DATETIME, ToDate DATETIME, RowNum INT)
	INSERT INTO @ExtraPT (SuperID, ProductID, ExtraPT, FromDate, ToDate, RowNum)
	SELECT cs.CustID, e.ProductID, e.ExtraPT, e.FromDate, e.ToDate, ROW_NUMBER() OVER(PARTITION BY cs.CustID, e.ProductID ORDER BY e.FromDate) AS RowNum
	FROM dbo.CS_CustSuper cs WITH (NOLOCK)
		CROSS APPLY (
			SELECT DISTINCT e.ProductID, e.ExtraPT
					,CASE WHEN e.FromDate < @FromDate THEN @FromDate ELSE e.FromDate END AS FromDate
					,CASE WHEN e.ToDate > @ToDate THEN @ToDate ELSE e.ToDate END AS ToDate
			FROM dbo.Acc_GroupExtraPTSetting e WITH (NOLOCK)
			WHERE cs.CustId = e.SuperId
				AND e.Sporttype = 0
				AND e.SubProduct = ''
				AND @FromDate <= e.ToDate
				AND @ToDate >= e.FromDate
		) AS e

	DELETE e
	FROM @ExtraPT e
	WHERE NOT EXISTS (SELECT 1 FROM #tblBetType bt WHERE e.ProductId = bt.ProductId)

	INSERT INTO @ExtraPT (SuperID, ProductId, ExtraPT, FromDate, ToDate)
	SELECT SuperID, ProductId, 0 AS ExtraPT, FromDate, ToDate
	FROM (
		SELECT
			ISNULL(e1.SuperID, e2.SuperID) AS SuperID
			,ISNULL(e1.ProductId, e2.ProductId) AS ProductId
			,CASE	WHEN e1.FromDate IS NULL THEN @FromDate
					WHEN e2.FromDate IS NULL THEN DATEADD(DAY, 1, e1.ToDate)
					ELSE DATEADD(DAY, 1, e1.ToDate)
					END AS FromDate
			,CASE	WHEN e1.ToDate IS NULL THEN DATEADD(DAY, -1, e2.FromDate)
					WHEN e2.ToDate IS NULL THEN @ToDate
					ELSE DATEADD(DAY, -1, e2.FromDate)
					END AS ToDate
		FROM @ExtraPT e1
			FULL OUTER JOIN @ExtraPT e2 ON e1.SuperID = e2.SuperID AND e1.ProductId = e2.ProductId AND e1.RowNum + 1 = e2.RowNum
	) AS c
	WHERE FromDate <= ToDate

	-- Products not have setting ExtraPT on this date range
	DECLARE @Products TABLE (ProductId INT)
	INSERT INTO @Products (ProductId)
	SELECT DISTINCT ProductId FROM #tblBetType

	INSERT INTO @ExtraPT (SuperID, ProductId, ExtraPT, FromDate, ToDate)
	SELECT cs.CustId, p.ProductId, 0 AS ExtraPT, @FromDate, @ToDate
	FROM dbo.CS_CustSuper cs WITH (NOLOCK)
		CROSS APPLY (
			SELECT p.ProductId FROM @Products p WHERE NOT EXISTS (SELECT 1 FROM @ExtraPT e WHERE e.ProductID = p.ProductID AND cs.CustId = e.SuperID)
		) AS p

	CREATE TABLE #SuperWinLoss
	(
		CustId			INT
		,Wagers			INT
		,Stake			MONEY
		,ValidStake		MONEY
		,MemberIncome	MONEY
		,SuperComm		MONEY
		,HouseWinloss	MONEY
		,HouseComm		MONEY
		,HouseIncome	MONEY
		,HeadlineStock	MONEY
	)
	
	CREATE TABLE #tmpBettrans
	(
		srecommend		INT
		,matchid		INT
		,eventtype		TINYINT
		,Wagers			INT
		,Stake			MONEY
		,ValidStake		MONEY
		,MemberIncome	MONEY
		,SuperComm		MONEY
		,HouseWinloss	MONEY
		,HouseComm		MONEY
		,HouseIncome	MONEY
		,HeadlineStock	MONEY
	)

	DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME

	-- bettrans
	IF @ToDate > @MoveBetsDay
	BEGIN
		SELECT	@FDate = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
				,@TDate = @ToDate

		INSERT INTO #tmpBettrans
		(
			srecommend
			,matchid
			,eventtype
			,Wagers
			,Stake
			,ValidStake
			,MemberIncome
			,SuperComm
			,HouseWinloss
			,HouseComm
			,HouseIncome
			,HeadlineStock
		)
		SELECT
			b.srecommend
			,b.matchid
			,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END AS eventtype
			,COUNT(1) AS Wagers
			,SUM(b.stake) AS Stake
			,SUM(ABS(b.winlost - b.actual_stake)) AS ValidStake
			,SUM(b.winlost - b.actual_stake + b.playercomm) AS MemberIncome
			,SUM(b.scomm - b.acomm) AS SuperComm
			,-SUM(b.winlost - b.actual_stake + b.swinlost + b.mwinlost + b.awinlost - ((b.winlost - b.actual_stake) * e.ExtraPT)) AS HouseWinloss
			,-SUM(b.scomm - CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm / (1 - b.tpositiontaking) * e.ExtraPT END) AS HouseComm
			,-SUM( -- HouseIncome = HouseWinloss + HouseComm
				b.winlost - b.actual_stake + b.swinlost + b.mwinlost + b.awinlost - ((b.winlost - b.actual_stake) * e.ExtraPT) -- HouseWinloss
				+ b.scomm - CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm / (1 - b.tpositiontaking) * e.ExtraPT END -- HouseComm
				) AS HouseIncome 
			,SUM(ABS(b.winlost - b.actual_stake) * (1 - b.tpositiontaking - e.ExtraPT)) AS HeadlineStock
		FROM @ExtraPT e
			CROSS APPLY (
				SELECT
					b.srecommend
					,CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END AS matchid
					,b.bettype
					,b.stake
					,b.winlost
					,b.actual_stake
					,b.playercomm
					,b.awinlost
					,b.mwinlost
					,b.swinlost
					,b.scomm
					,b.acomm
					,b.tpositiontaking
				FROM dbo.bettrans b WITH (NOLOCK)
					OUTER APPLY (
						SELECT TOP 1 bm.matchid
						FROM dbo.bettransm bm WITH (NOLOCK)
						WHERE b.refno = bm.refno AND b.bettype = 2799
					) AS s
				WHERE e.SuperID = b.srecommend AND b.winlostdate BETWEEN e.FromDate AND e.ToDate AND b.winlostdate BETWEEN @FDate AND @TDate
					AND b.statusID IN (111, 112, 113)
					AND (
							@IsLive = 2
							OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
							OR (b.bettype = 2799 AND @IsLive = 0)
							OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
						)
					AND (@IsExcludedTest = 0 OR b.currency <> 20)
			) AS b
			INNER JOIN #tblBetType bt ON b.bettype = bt.bettype AND bt.ProductID = e.ProductID
		GROUP BY
			b.srecommend
			,b.matchid
			,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END
		OPTION (HASH GROUP)

		INSERT INTO #SuperWinLoss
		(
			CustId
			,Wagers
			,Stake
			,ValidStake
			,MemberIncome
			,SuperComm
			,HouseWinloss
			,HouseComm
			,HouseIncome
			,HeadlineStock
		)
		SELECT
			b.srecommend AS CustId
			,SUM(b.Wagers) AS Wagers
			,SUM(b.Stake) AS Stake
			,SUM(b.ValidStake) AS ValidStake
			,SUM(b.MemberIncome) AS MemberIncome
			,SUM(b.SuperComm) AS SuperComm
			,SUM(b.HouseWinloss) AS HouseWinloss
			,SUM(b.HouseComm) AS HouseComm
			,SUM(b.HouseIncome) AS HouseIncome
			,SUM(b.HeadlineStock) AS HeadlineStock
		FROM #tmpBettrans b
			CROSS APPLY (
				SELECT m.sporttype
				FROM dbo.match m WITH (NOLOCK)
				WHERE b.matchid = m.matchid AND b.eventtype = 1 -- included Betradar VS Parlay

				UNION ALL
				SELECT l.sporttype
				FROM dbo.outright o WITH (NOLOCK)
					INNER JOIN dbo.League l WITH (NOLOCK) ON o.leagueid = l.leagueid
				WHERE b.matchid = o.orid AND b.eventtype = 2

				UNION ALL
				SELECT r.sporttype
				FROM dbo.VSRaceInfo r WITH (NOLOCK)
				WHERE b.matchid = r.EventID AND b.eventtype = 3

				UNION ALL
				SELECT CASE WHEN b.matchid = 29 THEN 0 ELSE b.matchid END AS sporttype -- SB Parlay: sporttype = 0
				WHERE b.matchid <> 2799 AND b.eventtype = 0
			) AS m
			INNER JOIN #tblSportType s ON m.sporttype = s.SportType
		GROUP BY
			b.srecommend
		OPTION (HASH GROUP)
	END

	DROP TABLE #tmpBettrans
	
	-- CS_SumWinloss
	IF @FromDate <= @MoveBetsDay
	BEGIN
		SELECT	@FDate = CASE WHEN @FromDate < @ArchiveDate THEN @ArchiveDate ELSE @FromDate END
				,@TDate = CASE WHEN @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

		INSERT INTO #SuperWinLoss
		(
			CustId
			,Wagers
			,Stake
			,ValidStake
			,MemberIncome
			,SuperComm
			,HouseWinloss
			,HouseComm
			,HouseIncome
			,HeadlineStock
		)
		SELECT
			CustId
			,SUM(Wagers) AS Wagers
			,SUM(Stake) AS Stake
			,SUM(ValidStake) AS ValidStake
			,SUM(MemberWinloss + MemberComm) AS MemberIncome
			,SUM(SuperComm) AS SuperComm
			,-SUM(HeadlineWinloss + MemberWinloss + AgentWinloss + MasterWinloss + SuperWinloss) AS HouseWinloss
			,-SUM(HeadlineComm + MemberComm + AgentComm + MasterComm + SuperComm) AS HouseComm
			,-SUM( -- HouseIncome = HouseWinloss + HouseComm
				HeadlineWinloss + MemberWinloss + AgentWinloss + MasterWinloss + SuperWinloss -- HouseWinloss
				+ HeadlineComm + MemberComm + AgentComm + MasterComm + SuperComm -- HouseComm
				) AS HouseIncome
			,SUM(HeadlineStock) AS HeadlineStock
		FROM bodb_Summary.dbo.CS_SumWinloss s WITH (NOLOCK)
		WHERE s.WinlostDate BETWEEN @FDate AND @TDate
			AND EXISTS (SELECT 1 FROM @ExtraPT e WHERE s.CustID = e.SuperID)
			AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
			AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
			AND (@IsLive = 2 OR IsLive = @IsLive)
		GROUP BY
			CustId
	END

	-- CS_SumWinloss_Old
	IF @FromDate < @ArchiveDate
	BEGIN
		SELECT	@FDate = @FromDate
				,@TDate = CASE WHEN @ToDate >= @ArchiveDate THEN DATEADD(DAY, -1, @ArchiveDate) ELSE @ToDate END

		INSERT INTO #SuperWinLoss
		(
			CustId
			,Wagers
			,Stake
			,ValidStake
			,MemberIncome
			,SuperComm
			,HouseWinloss
			,HouseComm
			,HouseIncome
			,HeadlineStock
		)
		SELECT
			CustId
			,SUM(Wagers) AS Wagers
			,SUM(Stake) AS Stake
			,SUM(ValidStake) AS ValidStake
			,SUM(MemberWinloss + MemberComm) AS MemberIncome
			,SUM(SuperComm) AS SuperComm
			,-SUM(HeadlineWinloss + MemberWinloss + AgentWinloss + MasterWinloss + SuperWinloss) AS HouseWinloss
			,-SUM(HeadlineComm + MemberComm + AgentComm + MasterComm + SuperComm) AS HouseComm
			,-SUM( -- HouseIncome = HouseWinloss + HouseComm
				HeadlineWinloss + MemberWinloss + AgentWinloss + MasterWinloss + SuperWinloss -- HouseWinloss
				+ HeadlineComm + MemberComm + AgentComm + MasterComm + SuperComm -- HouseComm
				) AS HouseIncome
			,SUM(HeadlineStock) AS HeadlineStock
		FROM bodb_Summary.dbo.CS_SumWinloss_Old s WITH (NOLOCK)
		WHERE s.WinlostDate BETWEEN @FDate AND @TDate
			AND EXISTS (SELECT 1 FROM @ExtraPT e WHERE s.CustID = e.SuperID)
			AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
			AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
			AND (@IsLive = 2 OR IsLive = @IsLive)
		GROUP BY
			CustId
	END

	SELECT
		c.CustId
		,c.Username
		,SUM(s.Wagers) AS Wagers
		,SUM(s.Stake) AS Stake
		,SUM(s.ValidStake) AS ValidStake
		,SUM(s.MemberIncome) AS MemberIncome
		,SUM(s.SuperComm) AS SuperComm
		,SUM(s.HouseWinloss) AS HouseWinloss
		,SUM(s.HouseComm) AS HouseComm
		,SUM(s.HouseIncome) AS HouseIncome
		,SUM(s.HeadlineStock) AS HeadlineStock
	FROM #SuperWinLoss s
		INNER JOIN dbo.CustSuper cs WITH (NOLOCK) ON s.CustId = cs.custid
		INNER JOIN dbo.Customer c WITH (NOLOCK) ON cs.UplineId = c.custid
	WHERE c.roleid = 0
		AND (c.currency <> 20 OR @IsExcludedTest = 0)
	GROUP BY
		c.CustId
		,c.Username

	DROP TABLE #SuperWinLoss
	DROP TABLE #tblBetType
	DROP TABLE #tblSportType
END
GO