/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Rpt_EBWinloss_Headline]
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
	Created: 20190812@Percy
	Task: CN88 - EB Settled Report - View Headlines
	DB: DBAGE.bodb02
	
	Revisions:
		- 20190812@Percy: Initialize SP [Redmine: #116925]
		
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

	/* ===== Get Sport/Bettype ===== */
	BEGIN
		DECLARE @isTest BIT
		SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

		CREATE TABLE #tblSportType (SportType INT)
		INSERT INTO #tblSportType (SportType)
		SELECT DISTINCT SportType FROM dbo.CS_f_SporttypeMatrix_Sel (0, @SportTypeGroup, @BetTypeGroup, @IsTest)

		CREATE TABLE #tblBetType (ProductID INT, BetType INT, EventType TINYINT)
		INSERT INTO #tblBetType (ProductID, BetType, EventType)
		SELECT DISTINCT ProductID, BetType, EventType FROM dbo.CS_f_BettypeMatrix_Sel (0, @SportTypeGroup, @BetTypeGroup, @IsTest)
	END
	/* ===== End Get Sport/Bettype ===== */

	/* ===== Get Data ===== */
	BEGIN
		CREATE TABLE #SuperWinLoss
		(
			CustId			INT
			,Wagers			INT
			,Stake			MONEY
			,ValidStake		MONEY
			,MemberWinloss	MONEY
			,MemberComm		MONEY
			,SuperComm		MONEY
			,HouseWinloss	MONEY
			,HouseComm		MONEY
			,HouseTurnover	MONEY
			,HeadlineStock	MONEY
		)

		DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME

		-- bettrans
		IF @ReportMode = 1 AND @ToDate > @MoveBetsDay
		BEGIN
			SELECT	@FDate = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
					,@TDate = @ToDate
		
			IF OBJECT_ID('tempdb..#tmpBettrans') IS NOT NULL
				DROP TABLE #tmpBettrans

			CREATE TABLE #tmpBettrans
			(
				srecommend		INT
				,matchid		INT
				,eventtype		TINYINT
				,Wagers			INT
				,Stake			MONEY
				,ValidStake		MONEY
				,MemberWinloss	MONEY
				,MemberComm		MONEY
				,SuperComm		MONEY
				,HouseWinloss	MONEY
				,HouseComm		MONEY
				,HouseTurnover	MONEY
				,HeadlineStock	MONEY
			)

			INSERT INTO #tmpBettrans
			(
				srecommend
				,matchid
				,eventtype
				,Wagers
				,Stake
				,ValidStake
				,MemberWinloss
				,MemberComm
				,SuperComm
				,HouseWinloss
				,HouseComm
				,HouseTurnover
				,HeadlineStock
			)
			SELECT
				b.srecommend
				,b.matchid
				,b.eventtype
				,COUNT(1) AS Wagers
				,SUM(b.stake) AS Stake
				,SUM(ABS(b.winlost - b.actual_stake)) AS ValidStake
				,SUM(b.winlost - b.actual_stake) AS MemberWinloss
				,SUM(b.playercomm) AS MemberComm
				,SUM(b.scomm - b.acomm) AS SuperComm
				,-SUM(b.winlost - b.actual_stake + b.swinlost + b.mwinlost + b.awinlost - ((b.winlost - b.actual_stake) * ISNULL(e.ExtraPT, 0))) AS HouseWinloss
				,-SUM(b.scomm - CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm / (1 - b.tpositiontaking) * ISNULL(e.ExtraPT, 0) END) AS HouseComm
				,SUM(b.stake * (1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0))) AS HouseTurnover
				,SUM(ABS(b.winlost - b.actual_stake) * (1 - b.tpositiontaking - ISNULL(e.ExtraPT, 0))) AS HeadlineStock
			FROM dbo.CS_CustSuper cs WITH (NOLOCK)
				CROSS APPLY (
					SELECT
						b.srecommend
						,CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END AS matchid
						,b.bettype
						,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END AS eventtype
						,bt.ProductID
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
						,b.winlostdate
					FROM dbo.bettrans b WITH (NOLOCK)
						INNER JOIN #tblBetType bt ON b.bettype = bt.bettype
						OUTER APPLY (
							SELECT TOP 1 bm.matchid
							FROM dbo.bettransm bm WITH (NOLOCK)
							WHERE b.refno = bm.refno AND b.bettype = 2799
						) AS s
					WHERE cs.CustId = b.srecommend AND b.winlostdate BETWEEN @FDate AND @TDate
						AND b.statusID IN (111, 112, 113)
						AND (
								@IsLive = 2
								OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
								OR (b.bettype = 2799 AND @IsLive = 0)
								OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
							)
						AND (@IsExcludedTest = 0 OR b.currency <> 20)
				) AS b
				OUTER APPLY (
					SELECT SUM(ag.ExtraPT) AS ExtraPT
					FROM dbo.Acc_GroupExtraPTSetting ag WITH (NOLOCK)
					WHERE cs.CustId = ag.SuperId
						AND b.winlostdate BETWEEN ag.FromDate AND ag.ToDate
						AND b.ProductID = ag.ProductId
						AND ag.Sporttype = 0
						AND ag.SubProduct = ''
				) AS e
			GROUP BY
				b.srecommend
				,b.matchid
				,b.eventtype

			INSERT INTO #SuperWinLoss
			(
				CustId
				,Wagers
				,Stake
				,ValidStake
				,MemberWinloss
				,MemberComm
				,SuperComm
				,HouseWinloss
				,HouseComm
				,HouseTurnover
				,HeadlineStock
			)
			SELECT
				b.srecommend			AS CustId
				,SUM(Wagers)			AS Wagers
				,SUM(Stake)				AS Stake
				,SUM(ValidStake)		AS ValidStake
				,SUM(MemberWinloss)		AS MemberWinloss
				,SUM(MemberComm)		AS MemberComm
				,SUM(SuperComm)			AS SuperComm
				,SUM(HouseWinloss)		AS HouseWinloss
				,SUM(HouseComm)			AS HouseComm
				,SUM(HouseTurnover)		AS HouseTurnover
				,SUM(HeadlineStock)		AS HeadlineStock
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

			DROP TABLE #tmpBettrans
		END
		-- End bettrans

		-- CS_SumWinloss
		IF @ToDate > @ArchiveDate -- (@ReportMode = 1 AND @FromDate <= @MoveBetsDay) OR (@ReportMode = 2 AND @ToDate > @ArchiveDate)
		BEGIN
			SELECT	@FDate = CASE WHEN @FromDate < @ArchiveDate THEN @ArchiveDate ELSE @FromDate END
					,@TDate = CASE WHEN @ReportMode = 1 AND @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

			IF @FDate <= @TDate
			BEGIN
				INSERT INTO #SuperWinLoss
				(
					CustId
					,Wagers
					,Stake
					,ValidStake
					,MemberWinloss
					,MemberComm
					,SuperComm
					,HouseWinloss
					,HouseComm
					,HouseTurnover
					,HeadlineStock
				)
				SELECT
					cs.CustId
					,SUM(Wagers)		AS Wagers
					,SUM(Stake)			AS Stake
					,SUM(ValidStake)	AS ValidStake
					,SUM(MemberWinloss) AS MemberWinloss
					,SUM(MemberComm)	AS MemberComm
					,SUM(SuperComm)		AS SuperComm
					,-SUM(HeadlineWinloss + MemberWinloss + AgentWinloss + MasterWinloss + SuperWinloss) AS HouseWinloss
					,-SUM(HeadlineComm + MemberComm + AgentComm + MasterComm + SuperComm) AS HouseComm
					,SUM(HouseTurnover) AS HouseTurnover
					,SUM(HeadlineStock) AS HeadlineStock
				FROM dbo.CS_CustSuper cs WITH (NOLOCK)
					CROSS APPLY (
						SELECT
							Wagers
							,Stake
							,ValidStake
							,MemberWinloss
							,AgentWinloss
							,MasterWinloss
							,SuperWinloss
							,HeadlineWinloss
							,MemberComm
							,AgentComm
							,MasterComm
							,SuperComm
							,HeadlineComm
							,HouseTurnover
							,HeadlineStock
						FROM bodb_Summary.dbo.CS_SumWinloss s WITH (NOLOCK)
						WHERE s.custid = cs.custid
							AND s.WinlostDate BETWEEN @FDate AND @TDate
							AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
							AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
							AND (@IsLive = 2 OR IsLive = @IsLive)
					) AS s
				GROUP BY
					cs.CustId
			END
		END
		-- End CS_SumWinloss

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
				,MemberWinloss
				,MemberComm
				,SuperComm
				,HouseWinloss
				,HouseComm
				,HouseTurnover
				,HeadlineStock
			)
			SELECT
				cs.CustId
				,SUM(Wagers)		AS Wagers
				,SUM(Stake)			AS Stake
				,SUM(ValidStake)	AS ValidStake
				,SUM(MemberWinloss) AS MemberWinloss
				,SUM(MemberComm)	AS MemberComm
				,SUM(SuperComm)		AS SuperComm
				,-SUM(HeadlineWinloss + MemberWinloss + AgentWinloss + MasterWinloss + SuperWinloss) AS HouseWinloss
				,-SUM(HeadlineComm + MemberComm + AgentComm + MasterComm + SuperComm) AS HouseComm
				,SUM(HouseTurnover) AS HouseTurnover
				,SUM(HeadlineStock) AS HeadlineStock
			FROM dbo.CS_CustSuper cs WITH (NOLOCK)
				CROSS APPLY (
					SELECT
						Wagers
						,Stake
						,ValidStake
						,MemberWinloss
						,AgentWinloss
						,MasterWinloss
						,SuperWinloss
						,HeadlineWinloss
						,MemberComm
						,AgentComm
						,MasterComm
						,SuperComm
						,HeadlineComm
						,HouseTurnover
						,HeadlineStock
					FROM bodb_Summary.dbo.CS_SumWinloss_Old s WITH (NOLOCK)
					WHERE s.custid = cs.custid
						AND s.WinlostDate BETWEEN @FDate AND @TDate
						AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
						AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
						AND (@IsLive = 2 OR IsLive = @IsLive)
				) AS s
			GROUP BY
				cs.CustId
		END
		-- End CS_SumWinloss_Old
	END
	/* ===== End Get Data ===== */

	/* ===== Return Data ===== */
	BEGIN
		SELECT
			c.CustId
			,c.Username
			,SUM(s.Wagers)			AS Wagers
			,SUM(s.Stake)			AS Stake
			,SUM(s.ValidStake)		AS ValidStake
			,SUM(s.MemberWinloss)	AS MemberWinloss
			,SUM(s.MemberComm)		AS MemberComm
			,SUM(s.MemberWinloss + MemberComm)	AS MemberIncome
			,SUM(s.SuperComm)		AS SuperComm
			,SUM(s.HouseWinloss)	AS HouseWinloss
			,SUM(s.HouseComm)		AS HouseComm
			,SUM(s.HouseTurnover)	AS HouseTurnover
			,SUM(s.HouseWinloss + HouseComm)	AS HouseIncome
			,-SUM(s.HouseWinloss + HouseComm)	AS HeadlineResult
			,SUM(s.HeadlineStock)	AS HeadlineStock
		FROM #SuperWinLoss s
			INNER JOIN dbo.CustSuper cs WITH (NOLOCK) ON s.CustId = cs.custid
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON cs.UplineId = c.custid
		WHERE c.roleid = 0
			AND (c.currency <> 20 OR @IsExcludedTest = 0)
		GROUP BY
			c.CustId
			,c.Username
	END
	/* ===== End Return Data ===== */

	DROP TABLE #SuperWinLoss
	DROP TABLE #tblBetType
	DROP TABLE #tblSportType
END
GO