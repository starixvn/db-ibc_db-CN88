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
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @IsTest BIT
	SELECT  @IsTest = dbo.f_CheckSPVersion(@@PROCID)

	CREATE TABLE #tblSportType (SportType INT)
	INSERT INTO #tblSportType (SportType)
	SELECT DISTINCT SportType FROM dbo.CS_f_SporttypeMatrix_Sel (1, @SportTypeGroup, @BetTypeGroup, @IsTest)

	CREATE TABLE #tblBetType (BetTypeGroup INT, BetType INT, EventType TINYINT)
	INSERT INTO #tblBetType (BetTypeGroup, BetType, EventType)
	SELECT DISTINCT BetTypeGroup, BetType, EventType FROM dbo.CS_f_BettypeMatrix_Sel (1, @SportTypeGroup, @BetTypeGroup, @IsTest)

	DECLARE @ExtraPT TABLE (SuperID INT , ExtraPT DECIMAL(9,8), WinlostDate SMALLDATETIME)
	INSERT INTO @ExtraPT (SuperID, ExtraPT, WinlostDate)
	SELECT DISTINCT c.CustId, ISNULL(e.ExtraPT, 0), @WinlostDate
	FROM dbo.CS_CustSuper c WITH (NOLOCK)
		LEFT JOIN dbo.Acc_GroupExtraPTSetting e WITH (NOLOCK)
			ON c.custid = e.SuperID
				AND e.ProductId = 1
				AND e.Sporttype = 0
				AND e.SubProduct = ''
				AND @WinlostDate BETWEEN e.FromDate AND e.ToDate

	CREATE TABLE #tmpBettrans (matchid INT, bettype INT, Wagers INT, Stake MONEY, ValidStake MONEY, MemberIncome MONEY, HouseIncome MONEY, HeadlineStock MONEY)

	IF @WinlostDate > @MoveBetsDay
	BEGIN
		INSERT INTO #tmpBettrans
		(
			matchid
			,bettype
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
			,COUNT(1) AS Wagers
			,SUM(b.stake) AS Stake
			,SUM(ABS(b.winlost - b.actual_stake)) AS ValidStake
			,SUM(b.winlost - b.actual_stake + b.playercomm) AS MemberIncome
			,-SUM(
				b.winlost - b.actual_stake + b.awinlost + b.mwinlost + b.swinlost + b.scomm
				- (CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.winlost - b.actual_stake + b.scomm / (1 - b.tpositiontaking) END) * e.ExtraPT
				) AS HouseIncome
			,SUM(ABS(b.winlost - b.actual_stake) * (1 - b.tpositiontaking - e.ExtraPT)) AS HeadlineStock
		FROM @ExtraPT e
			CROSS APPLY (
				SELECT
					b.matchid
					,b.bettype
					,b.stake
					,b.winlost
					,b.actual_stake
					,b.playercomm
					,awinlost
					,b.mwinlost
					,b.swinlost
					,b.scomm
					,b.tpositiontaking
				FROM dbo.bettrans b WITH (NOLOCK)
				WHERE e.SuperID = b.srecommend AND e.WinlostDate = b.winlostdate
					AND b.statusID IN (111, 112, 113)
					AND (
							@IsLive = 2
							OR (b.bettype = 29 AND (@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1))
							OR (b.bettype <> 29 AND b.liveindicator = @IsLive)
						)
					AND (@IsExcludedTest = 0 OR b.currency <> 20)
			) AS b
		GROUP BY
			b.matchid
			,b.bettype
		OPTION (HASH GROUP)

		SELECT
			m.leagueid, m.matchid, m.homeid, m.awayid, bt.bettypegroup
			,SUM(b.Wagers) AS Wagers, SUM(b.Stake) AS Stake, SUM(b.ValidStake) AS ValidStake, SUM(b.MemberIncome) AS MemberIncome
			,SUM(b.HouseIncome) AS HouseIncome, SUM(b.HeadlineStock) AS HeadlineStock
		FROM #tmpBettrans b
			INNER JOIN #tblBetType bt ON b.bettype = bt.bettype
			CROSS APPLY
				(
					SELECT m.leagueid, m.matchid, m.homeid, m.awayid, m.sporttype
					FROM dbo.match m WITH (NOLOCK)
					WHERE b.matchid = m.matchid AND bt.EventType = 1
						AND m.eventstatus = 'Completed' AND ISNULL(m.betstatus, '') <> 'Refund'
					
					UNION ALL
					SELECT l.leagueid, 0 AS matchid, 0 AS homeid, 0 AS awayid, l.sporttype
					FROM dbo.outright o WITH (NOLOCK)
						INNER JOIN dbo.League l WITH (NOLOCK) ON o.leagueid = l.leagueid
					WHERE b.matchid = o.orid AND bt.EventType = 2

					UNION ALL
					SELECT 0 AS leagueid, 0 AS matchid, 0 AS homeid, 0 AS awayid, 0 AS sporttype -- SB Parlay
					WHERE b.matchid = 29 AND bt.EventType = 0
				) AS m
			INNER JOIN #tblSportType s ON m.sporttype = s.SportType
		GROUP BY
			m.leagueid, m.matchid, m.homeid, m.awayid, bt.bettypegroup
	END
	ELSE
	BEGIN
		INSERT INTO #tmpBettrans
		(
			matchid
			,bettype
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
			,COUNT(1) AS Wagers
			,SUM(b.stake) AS Stake
			,SUM(ABS(b.winlost - b.actual_stake)) AS ValidStake
			,SUM(b.winlost - b.actual_stake + b.playercomm) AS MemberIncome
			,-SUM(
				b.winlost - b.actual_stake + b.awinlost + b.mwinlost + b.swinlost + b.scomm
				- (CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.winlost - b.actual_stake + b.scomm / (1 - b.tpositiontaking) END) * e.ExtraPT
				) AS HouseIncome
			,SUM(ABS(b.winlost - b.actual_stake) * (1 - b.tpositiontaking - e.ExtraPT)) AS HeadlineStock
		FROM @ExtraPT e
			CROSS APPLY (
				SELECT
					b.matchid
					,b.bettype
					,b.stake
					,b.winlost
					,b.actual_stake
					,b.playercomm
					,awinlost
					,b.mwinlost
					,b.swinlost
					,b.scomm
					,b.tpositiontaking
				FROM dbo.bettrans14 b WITH (NOLOCK)
				WHERE e.SuperID = b.srecommend AND e.WinlostDate = b.winlostdate
					AND b.statusID IN (111, 112, 113)
					AND (
							@IsLive = 2
							OR (b.bettype = 29 AND (@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1))
							OR (b.bettype <> 29 AND b.liveindicator = @IsLive)
						)
					AND (@IsExcludedTest = 0 OR b.currency <> 20)
			) AS b
		GROUP BY
			b.matchid
			,b.bettype
		OPTION (HASH GROUP)

		SELECT
			m.leagueid, m.matchid, m.homeid, m.awayid, bt.bettypegroup
			,SUM(b.Wagers) AS Wagers, SUM(b.Stake) AS Stake, SUM(b.ValidStake) AS ValidStake, SUM(b.MemberIncome) AS MemberIncome
			,SUM(b.HouseIncome) AS HouseIncome, SUM(b.HeadlineStock) AS HeadlineStock
		FROM #tmpBettrans b
			INNER JOIN #tblBetType bt ON b.bettype = bt.bettype
			OUTER APPLY
				(
					SELECT m.leagueid, m.matchid, m.homeid, m.awayid, m.sporttype
					FROM dbo.match14 m WITH (NOLOCK)
					WHERE b.matchid = m.matchid AND bt.EventType = 1
						AND m.eventstatus = 'Completed' AND ISNULL(m.betstatus, '') <> 'Refund'
					
					UNION ALL
					SELECT 0 AS leagueid, 0 AS matchid, 0 AS homeid, 0 AS awayid, l.sporttype
					FROM dbo.outright14 o WITH (NOLOCK)
						INNER JOIN dbo.League l WITH (NOLOCK) ON o.leagueid = l.leagueid
					WHERE b.matchid = o.orid AND bt.EventType = 2

					UNION ALL
					SELECT 0 AS leagueid, 0 AS matchid, 0 AS homeid, 0 AS awayid, 0 AS sporttype -- SB Parlay
					WHERE b.matchid = 29 AND bt.EventType = 0
				) AS m
			INNER JOIN #tblSportType s ON m.sporttype = s.SportType
		GROUP BY
			m.leagueid, m.matchid, m.homeid, m.awayid, bt.bettypegroup
	END

	DROP TABLE #tblBetType
	DROP TABLE #tblSportType
	DROP TABLE #tmpBettrans
END
GO