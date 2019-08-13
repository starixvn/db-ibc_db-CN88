/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Rpt_MatchWinLoss_Headline]
	@WinlostDate	SMALLDATETIME,
	@SportTypeGroup	SMALLINT = 0,
	@BetTypeGroup	SMALLINT = 0,
	@IsLive			TINYINT = 2, -- market
	@IsExcludedTest	BIT = 0,
	@MoveBetsDay	SMALLDATETIME
AS

/*
	Created: 20190520@Percy
	DB: DBAGE.bodb02
	Task: Match Win Loss - View all healines

	Revisions:
		- 20190520@Percy: Initiliaze SP [RedmineID: #113849]
		- 20180719@Percy: Add Non-Sports [RedmineID: #11701]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @n INT = 2147483647

	DECLARE @IsTest BIT
	SELECT  @IsTest = dbo.f_CheckSPVersion(@@PROCID)

	CREATE TABLE #tblSportType (ProductID INT, SportType INT, SportTypeGroup INT)
	INSERT INTO #tblSportType (ProductID, SportType, SportTypeGroup)
	SELECT DISTINCT ProductID, SportType, SportTypeGroup
	FROM dbo.CS_f_SporttypeMatrix_Sel (0, @SportTypeGroup, @BetTypeGroup, @IsTest)

	CREATE TABLE #tblBetType (ProductID INT, BetTypeGroup INT, BetType INT, EventType TINYINT, IsNonSports BIT)
	INSERT INTO #tblBetType (ProductID, BetTypeGroup, BetType, EventType, IsNonSports)
	SELECT DISTINCT ProductID, BetTypeGroup, BetType, EventType, 0
	FROM dbo.CS_f_BettypeMatrix_Sel (0, @SportTypeGroup, @BetTypeGroup, @IsTest)

	UPDATE bt
	SET bt.BetTypeGroup = st.SportTypeGroup, bt.IsNonSports = 1
	FROM #tblBetType bt
		INNER JOIN #tblSportType st ON bt.ProductID = st.ProductID
	WHERE bt.ProductID IN (3,8,28,5,27)

	DECLARE @ExtraPT TABLE (SuperID INT, ProductID INT, ExtraPT DECIMAL(9,8), winlostdate SMALLDATETIME)
	INSERT INTO @ExtraPT (SuperID, ProductID, ExtraPT, winlostdate)
	SELECT cs.CustID, e.ProductID, ISNULL(e.ExtraPT, 0), @WinlostDate
	FROM dbo.CS_CustSuper cs WITH (NOLOCK)
		CROSS APPLY (
			SELECT ProductId, MAX(ExtraPT) AS ExtraPT
			FROM (
				SELECT DISTINCT e.ProductID, e.ExtraPT
				FROM dbo.Acc_GroupExtraPTSetting e WITH (NOLOCK)
				WHERE cs.CustId = e.SuperId
					AND e.Sporttype = 0
					AND e.SubProduct = ''
					AND @WinlostDate BETWEEN e.FromDate AND e.ToDate

				UNION ALL
				SELECT DISTINCT ProductID AS ProductID, 0 AS ExtraPT
				FROM #tblBetType
			) AS r
			GROUP BY ProductId
		) AS e

	DELETE e
	FROM @ExtraPT e
	WHERE ProductID <> 0
		AND NOT EXISTS (SELECT 1 FROM #tblBetType bt WHERE e.ProductID = bt.ProductID)

	CREATE TABLE #tmpBettrans
	(
		matchid			INT
		,bettype		INT
		,bettypegroup	INT
		,productid		INT
		,IsNonSports	BIT
		,eventtype		TINYINT
		,Wagers			INT
		,Stake			MONEY
		,ValidStake		MONEY
		,MemberIncome	MONEY
		,HouseIncome	MONEY
		,HeadlineStock	MONEY
	)

	IF @WinlostDate > @MoveBetsDay
	BEGIN
		INSERT INTO #tmpBettrans
		(
			matchid
			,bettype
			,bettypegroup
			,productid
			,IsNonSports
			,eventtype
			,Wagers
			,Stake
			,ValidStake
			,MemberIncome
			,HouseIncome
			,HeadlineStock
		)
		SELECT
			b.matchid
			,b.bettype
			,bt.BetTypeGroup
			,bt.ProductId
			,bt.IsNonSports
			,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END AS eventtype
			,COUNT(1) AS Wagers
			,SUM(b.stake) AS Stake
			,SUM(ABS(b.winlost - b.actual_stake)) AS ValidStake
			,SUM(b.winlost - b.actual_stake + b.playercomm) AS MemberIncome
			,-SUM( -- HouseIncome = HouseWinloss + HouseComm
				b.winlost - b.actual_stake + b.swinlost + b.mwinlost + b.awinlost - ((b.winlost - b.actual_stake) * e.ExtraPT) -- HouseWinloss
				+ b.scomm - CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm / (1 - b.tpositiontaking) * e.ExtraPT END -- HouseComm
				) AS HouseIncome
			,SUM(ABS(b.winlost - b.actual_stake) * (1 - b.tpositiontaking - e.ExtraPT)) AS HeadlineStock
		FROM @ExtraPT e
			CROSS APPLY (
				SELECT TOP (@n)
					CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END AS matchid
					,b.bettype
					,b.stake
					,b.winlost
					,b.actual_stake
					,b.playercomm
					,b.awinlost
					,b.mwinlost
					,b.swinlost
					,b.scomm
					,b.tpositiontaking
				FROM dbo.bettrans b WITH (NOLOCK)
					OUTER APPLY (
						SELECT TOP 1 bm.matchid
						FROM dbo.bettransm bm WITH (NOLOCK)
						WHERE b.refno = bm.refno AND b.bettype = 2799
					) AS s
				WHERE e.SuperID = b.srecommend AND e.WinlostDate = b.winlostdate
					AND b.statusID IN (111, 112, 113)
					AND (
							@IsLive = 2
							OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
							OR (b.bettype = 2799 AND @IsLive = 0)
							OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
						)
					AND (@IsExcludedTest = 0 OR b.currency <> 20)
			) AS b
			INNER JOIN #tblBetType bt ON b.bettype = bt.bettype AND e.ProductID = bt.ProductID
		GROUP BY
			b.matchid
			,b.bettype
			,bt.BetTypeGroup
			,bt.ProductId
			,bt.IsNonSports
			,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END
		OPTION (HASH GROUP, OPTIMIZE FOR (@n = 1))

		SELECT
			m.leagueid, m.matchid, m.homeid, m.awayid, b.bettypegroup, b.IsNonSports
			,SUM(b.Wagers) AS Wagers, SUM(b.Stake) AS Stake, SUM(b.ValidStake) AS ValidStake, SUM(b.MemberIncome) AS MemberIncome
			,SUM(b.HouseIncome) AS HouseIncome, SUM(b.HeadlineStock) AS HeadlineStock
		FROM #tmpBettrans b
			CROSS APPLY
				(
					SELECT m.leagueid, m.matchid, m.homeid, m.awayid, m.sporttype
					FROM dbo.match m WITH (NOLOCK)
					WHERE b.matchid = m.matchid AND b.EventType = 1
						AND m.eventstatus = 'Completed' AND b.IsNonSports = 0

					UNION ALL
					SELECT 0 AS leagueid, 0 AS matchid, 0 AS homeid, 0 AS awayid, m.sporttype
					FROM dbo.match m WITH (NOLOCK)
					WHERE b.matchid = m.matchid AND b.EventType = 1
						AND m.eventstatus = 'Completed' AND b.IsNonSports = 1
					
					UNION ALL
					SELECT l.leagueid, 0 AS matchid, 0 AS homeid, 0 AS awayid, l.sporttype
					FROM dbo.outright o WITH (NOLOCK)
						INNER JOIN dbo.League l WITH (NOLOCK) ON o.leagueid = l.leagueid
					WHERE b.matchid = o.orid AND b.EventType = 2

					UNION ALL
					SELECT 0 AS leagueid, 0 AS matchid, 0 AS homeid, 0 AS awayid, l.sporttype
					FROM dbo.VSRaceInfo r WITH (NOLOCK)
						INNER JOIN dbo.League l WITH (NOLOCK) ON r.leagueid = l.leagueid
					WHERE b.matchid = r.EventID AND b.EventType = 3

					UNION ALL
					SELECT 0 AS leagueid, 0 AS matchid, 0 AS homeid, 0 AS awayid, CASE WHEN b.matchid = 29 THEN 0 ELSE b.matchid END AS sporttype -- SB Parlay: sporttype = 0
					WHERE b.matchid <> 2799 AND b.EventType = 0
				) AS m
			INNER JOIN #tblSportType s ON m.sporttype = s.SportType
		GROUP BY
			m.leagueid, m.matchid, m.homeid, m.awayid, b.bettypegroup, b.IsNonSports
		OPTION (HASH GROUP)
	END
	ELSE
	BEGIN
		INSERT INTO #tmpBettrans
		(
			matchid
			,bettype
			,bettypegroup
			,productid
			,IsNonSports
			,eventtype
			,Wagers
			,Stake
			,ValidStake
			,MemberIncome
			,HouseIncome
			,HeadlineStock
		)
		SELECT
			b.matchid
			,b.bettype
			,bt.BetTypeGroup
			,bt.ProductId
			,bt.IsNonSports
			,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END AS eventtype
			,COUNT(1) AS Wagers
			,SUM(b.stake) AS Stake
			,SUM(ABS(b.winlost - b.actual_stake)) AS ValidStake
			,SUM(b.winlost - b.actual_stake + b.playercomm) AS MemberIncome
			,-SUM( -- HouseIncome = HouseWinloss + HouseComm
				b.winlost - b.actual_stake + b.swinlost + b.mwinlost + b.awinlost - ((b.winlost - b.actual_stake) * e.ExtraPT) -- HouseWinloss
				+ b.scomm - CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm / (1 - b.tpositiontaking) * e.ExtraPT END -- HouseComm
				) AS HouseIncome
			,SUM(ABS(b.winlost - b.actual_stake) * (1 - b.tpositiontaking - e.ExtraPT)) AS HeadlineStock
		FROM @ExtraPT e
			CROSS APPLY (
				SELECT TOP (@n)
					CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END AS matchid
					,b.bettype
					,b.stake
					,b.winlost
					,b.actual_stake
					,b.playercomm
					,b.awinlost
					,b.mwinlost
					,b.swinlost
					,b.scomm
					,b.tpositiontaking
				FROM dbo.bettrans14 b WITH (NOLOCK)
					OUTER APPLY (
						SELECT TOP 1 bm.matchid
						FROM dbo.bettransm14 bm WITH (NOLOCK)
						WHERE b.refno = bm.refno AND b.bettype = 2799
					) AS s
				WHERE e.SuperID = b.srecommend AND e.WinlostDate = b.winlostdate
					AND b.statusID IN (111, 112, 113)
					AND (
							@IsLive = 2
							OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
							OR (b.bettype = 2799 AND @IsLive = 0)
							OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
						)
					AND (@IsExcludedTest = 0 OR b.currency <> 20)
			) AS b
			INNER JOIN #tblBetType bt ON b.bettype = bt.bettype AND e.ProductID = bt.ProductID
		GROUP BY
			b.matchid
			,b.bettype
			,bt.BetTypeGroup
			,bt.ProductId
			,bt.IsNonSports
			,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END
		OPTION (HASH GROUP, OPTIMIZE FOR (@n = 1))

		SELECT
			m.leagueid, m.matchid, m.homeid, m.awayid, b.bettypegroup, b.IsNonSports
			,SUM(b.Wagers) AS Wagers, SUM(b.Stake) AS Stake, SUM(b.ValidStake) AS ValidStake, SUM(b.MemberIncome) AS MemberIncome
			,SUM(b.HouseIncome) AS HouseIncome, SUM(b.HeadlineStock) AS HeadlineStock
		FROM #tmpBettrans b
			CROSS APPLY
				(
					SELECT m.leagueid, m.matchid, m.homeid, m.awayid, m.sporttype
					FROM dbo.match14 m WITH (NOLOCK)
					WHERE b.matchid = m.matchid AND b.EventType = 1
						AND m.eventstatus = 'Completed' AND b.IsNonSports = 0

					UNION ALL
					SELECT 0 AS leagueid, 0 AS matchid, 0 AS homeid, 0 AS awayid, m.sporttype
					FROM dbo.match14 m WITH (NOLOCK)
					WHERE b.matchid = m.matchid AND b.EventType = 1
						AND m.eventstatus = 'Completed' AND b.IsNonSports = 1
					
					UNION ALL
					SELECT l.leagueid, 0 AS matchid, 0 AS homeid, 0 AS awayid, l.sporttype
					FROM dbo.outright14 o WITH (NOLOCK)
						INNER JOIN dbo.League l WITH (NOLOCK) ON o.leagueid = l.leagueid
					WHERE b.matchid = o.orid AND b.EventType = 2

					UNION ALL
					SELECT 0 AS leagueid, 0 AS matchid, 0 AS homeid, 0 AS awayid, l.sporttype
					FROM dbo.VSRaceInfo r WITH (NOLOCK)
						INNER JOIN dbo.League l WITH (NOLOCK) ON r.leagueid = l.leagueid
					WHERE b.matchid = r.EventID AND b.EventType = 3

					UNION ALL
					SELECT 0 AS leagueid, 0 AS matchid, 0 AS homeid, 0 AS awayid, CASE WHEN b.matchid = 29 THEN 0 ELSE b.matchid END AS sporttype -- SB Parlay: sporttype = 0
					WHERE b.matchid <> 2799 AND b.EventType = 0
				) AS m
			INNER JOIN #tblSportType s ON m.sporttype = s.SportType
		GROUP BY
			m.leagueid, m.matchid, m.homeid, m.awayid, b.bettypegroup, b.IsNonSports
		OPTION (HASH GROUP)
	END

	DROP TABLE #tblBetType
	DROP TABLE #tblSportType
	DROP TABLE #tmpBettrans
END
GO