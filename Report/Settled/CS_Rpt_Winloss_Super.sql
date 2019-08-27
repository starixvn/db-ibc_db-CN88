/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_Rpt_Winloss_Super]
	@CustId				INT = 0,
	@IsOwner			BIT = 1,
	@SubAccId			INT = 0,
	@IsAllDownline		BIT = 1,
	@FromDate			SMALLDATETIME,
	@ToDate				SMALLDATETIME,
	@ArchiveDate		SMALLDATETIME,
	@MoveBetsDay		SMALLDATETIME,
	@SporttypeGroup		SMALLINT = 0, -- all
	@BettypeGroup		SMALLINT = 0, -- all
	@IsLive				TINYINT = 2  -- all
AS

/*
	Created: 20190214@Sophia
	Task: CN88 - Super report
	DB: DBAGE.bodb02	
	
	Revisions:
		- 20190214@Sophia: Create new [RedmineID: #105660] 
		- 20190329@Sophia: Implement Non Sports [Redmine: #109521]
		- 20190528@Sophia: Fix bug VS [Redmine: #113482]
		- 20190708@Percy: Remove column HeadlineStock [RedmineID: #116088]
		- 20190713@Percy: Add sub account - permission on downlines [RedmineID: #116825]
		- 20190719@Percy: Add back column HeadlineStock [RedmineID: #117297]
		- 20190801@Percy: Change way get ExtraPT amount [RedmineID: #117909]
		
	Param's Explanation:
		- @CustId: SuperID or HeadlineID 
		- @SubAccId: sub account
		- @IsAllDownline: is view all downlines
		- @IsOwner: Is Super view super or not (if @CustId = SuperID then @IsOwner = 1, if @CustId = HeadlineID then @IsOwner = 0)
		- @ProductId: default = 1: Sportsbook
		- @Bettype: default = 0: All
		- @SporttypeGroup: default = 0: All
		- @BettypeGroup: default = 0: All
		- @IsLive: default = 2: All
						= 1: Live
						= 0: Dead
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @n INT = 2147483647

	/* ===== Get SportBettypeMatrix ===== */
	BEGIN
		DECLARE @isTest BIT = 0
		SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

		CREATE TABLE #tblSportType (SportType INT)
		INSERT INTO #tblSportType (SportType)
		SELECT DISTINCT SportType FROM dbo.CS_f_SporttypeMatrix_Sel (0, @SportTypeGroup, @BetTypeGroup, @IsTest)

		CREATE TABLE #tblBetType (ProductId INT, BetType INT, EventType TINYINT)
		INSERT INTO #tblBetType (ProductId, BetType, EventType)
		SELECT DISTINCT ProductId, BetType, EventType FROM dbo.CS_f_BettypeMatrix_Sel (0, @SportTypeGroup, @BetTypeGroup, @IsTest)
	END
	/* ===== End Get SportBettypeMatrix ===== */

	/* ===== Get Customer List ===== */
	BEGIN
		DECLARE @CustList  TABLE (CustId INT)
		DECLARE @Customers TABLE (CustId INT, ProductId INT, ExtraPT DECIMAL(9,8), FromDate DATETIME, ToDate DATETIME, RowNum INT)
		DECLARE @Downlines TABLE (DownlineId INT)
		
		IF @IsOwner = 1 -- View owner
		BEGIN
			INSERT INTO @CustList (CustId)
			VALUES (@CustId)

			/* ===== Get downline list by Sub Account ==== */
			IF ISNULL(@SubAccId, 0) <> 0 AND ISNULL(@IsAllDownline, 0) = 0
			BEGIN
				INSERT INTO @Downlines (DownlineId)
				SELECT DownlineId FROM dbo.CS_f_GetDownlineBySubAcc(@SubAccId)
			END
			/* ===== End Get downline list by Sub Account ==== */
		END
		ELSE -- Upline view
		BEGIN
			/* ===== Get downline list by Sub Account ==== */
			IF ISNULL(@SubAccId, 0) <> 0 AND ISNULL(@IsAllDownline, 0) = 0
			BEGIN
				INSERT INTO @CustList (CustId)
				SELECT DownlineId FROM dbo.CS_f_GetDownlineBySubAcc(@SubAccId)
			END
			/* ===== End Get downline list by Sub Account ==== */
			ELSE
			BEGIN
				INSERT INTO @CustList (CustId)
				SELECT CustId
				FROM dbo.CustSuper WITH (NOLOCK)
				WHERE UplineId = @CustId
			END

			SELECT @IsAllDownline = 1
		END

		INSERT INTO @Customers (CustId, ProductId, ExtraPT, FromDate, ToDate, RowNum)
		SELECT SuperId, ProductId, ExtraPT, FromDate, ToDate, ROW_NUMBER() OVER(PARTITION BY SuperId, ProductId ORDER BY FromDate) AS RowNum
		FROM @CustList c
			CROSS APPLY (
				SELECT DISTINCT e.SuperId, e.ProductId, e.ExtraPT
						,CASE WHEN e.FromDate < @FromDate THEN @FromDate ELSE e.FromDate END AS FromDate
						,CASE WHEN e.ToDate > @ToDate THEN @ToDate ELSE e.ToDate END AS ToDate
				FROM dbo.Acc_GroupExtraPTSetting e WITH (NOLOCK)
				WHERE e.SuperId = c.CustId
					AND e.Sporttype = 0
					AND e.SubProduct = ''
					AND @FromDate <= e.ToDate
					AND @ToDate >= e.FromDate
			) AS e

		DELETE c
		FROM @Customers c
		WHERE NOT EXISTS (SELECT 1 FROM #tblBetType bt WHERE c.ProductId = bt.ProductId)

		INSERT INTO @Customers (CustId, ProductId, ExtraPT, FromDate, ToDate)
		SELECT CustId, ProductId, 0 AS ExtraPT, FromDate, ToDate
		FROM (
			SELECT
				ISNULL(c1.CustId, c2.CustId) AS CustId
				,ISNULL(c1.ProductId, c2.ProductId) AS ProductId
				,CASE	WHEN c1.FromDate IS NULL THEN @FromDate
						WHEN c2.FromDate IS NULL THEN DATEADD(DAY, 1, c1.ToDate)
						ELSE DATEADD(DAY, 1, c1.ToDate)
						END AS FromDate
				,CASE	WHEN c1.ToDate IS NULL THEN DATEADD(DAY, -1, c2.FromDate)
						WHEN c2.ToDate IS NULL THEN @ToDate
						ELSE DATEADD(DAY, -1, c2.FromDate)
						END AS ToDate
			FROM @Customers c1
				FULL OUTER JOIN @Customers c2 ON c1.CustId = c2.CustId AND c1.ProductId = c2.ProductId AND c1.RowNum + 1 = c2.RowNum
		) AS c
		WHERE FromDate <= ToDate

		-- Products not have setting ExtraPT on this date range
		DECLARE @Products TABLE (ProductId INT)
		INSERT INTO @Products (ProductId)
		SELECT DISTINCT ProductId FROM #tblBetType

		INSERT INTO @Customers (CustId, ProductId, ExtraPT, FromDate, ToDate)
		SELECT l.CustId, p.ProductId, 0 AS ExtraPT, @FromDate, @ToDate
		FROM @CustList l
			CROSS APPLY (
				SELECT p.ProductId FROM @Products p WHERE NOT EXISTS (SELECT 1 FROM @Customers c WHERE c.ProductID = p.ProductID AND c.CustId = l.CustId)
			) AS p
	END
	/* ===== End Get Customer List ===== */

	/* ===== Get data ===== */
	BEGIN
		DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME

		CREATE TABLE #tmpSumWinloss
		(
			CustId			INT
			,Wagers			INT
			,Stake			MONEY
			,ValidStake		MONEY
			,MemberIncome	MONEY
			,Agent			MONEY
			,AgentResult	MONEY
			,Master			MONEY
			,Super			MONEY
			,SuperIncome	MONEY
			,SuperResult	MONEY
			,SuperStock		MONEY
			,HeadlineIncome	MONEY
			,HeadlineResult	MONEY
			,HeadlineStock	MONEY
		)

		-- bettrans
		CREATE TABLE #tmpBettrans
		(
			srecommend		INT
			,matchid		INT
			,eventtype		TINYINT
			,Wagers			INT
			,Stake			MONEY
			,ValidStake		MONEY
			,MemberIncome	MONEY
			,Agent			MONEY
			,AgentResult	MONEY
			,Master			MONEY
			,Super			MONEY
			,SuperIncome	MONEY
			,SuperResult	MONEY
			,SuperStock		MONEY
			,HeadlineIncome	MONEY
			,HeadlineResult	MONEY
			,HeadlineStock	MONEY
		)

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
				,Agent
				,AgentResult
				,Master
				,Super
				,SuperIncome
				,SuperResult
				,SuperStock
				,HeadlineIncome
				,HeadlineResult
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
				,SUM((b.winlost - b.actual_stake)  + (ABS(b.winlost - b.actual_stake) * b.discount)) AS Agent
				,SUM(b.winlost - b.actual_stake + b.awinlost + b.comm) AS AgentResult
				,SUM((b.winlost - b.actual_stake) * (1 - b.apositiontaking)
						+ ABS(b.winlost - b.actual_stake) * (1 - b.apositiontaking) * b.adiscount) AS Master
				,SUM((b.winlost - b.actual_stake) * (1 - b.apositiontaking - b.mpositiontaking)
						+ ABS(b.winlost - b.actual_stake) * (1 - b.apositiontaking - b.mpositiontaking) * b.sdiscount
									) AS Super
				,SUM(b.swinlost + b.scomm - b.acomm) AS SuperIncome
				,SUM(b.winlost - b.actual_stake + b.swinlost + b.mwinlost + b.awinlost + b.scomm) AS SuperResult
				,SUM(ABS(b.winlost - b.actual_stake) * (1 - b.tpositiontaking)) AS SuperStock
				,-SUM(CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE (b.winlost - b.actual_stake + b.scomm / (1 - b.tpositiontaking)) * c.ExtraPT END) AS HeadlineIncome
				,SUM(b.winlost - b.actual_stake + b.swinlost + b.mwinlost + b.awinlost + b.scomm
					- CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE (b.winlost - b.actual_stake + b.scomm / (1 - b.tpositiontaking)) * c.ExtraPT END
					) AS HeadlineResult
				,SUM(ABS(b.winlost - b.actual_stake) * (1 - b.tpositiontaking - c.ExtraPT)) AS HeadlineStock
			FROM @Customers c
				CROSS APPLY (
					SELECT TOP (@n)
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
						,b.comm
						,b.discount
						,b.adiscount
						,b.sdiscount
						,b.apositiontaking
						,b.mpositiontaking
						,b.tpositiontaking
					FROM dbo.bettrans b WITH (NOLOCK)
						OUTER APPLY (
							SELECT TOP 1 bm.matchid
							FROM dbo.bettransm bm WITH (NOLOCK)
							WHERE b.refno = bm.refno AND b.bettype = 2799
						) AS s
					WHERE c.CustId = b.srecommend AND b.winlostdate BETWEEN c.FromDate AND c.ToDate AND b.winlostdate BETWEEN @FDate AND @TDate
						AND (@IsAllDownline = 1 OR EXISTS (SELECT 1 FROM @Downlines d WHERE b.mrecommend = d.DownlineId))
						AND b.statusID IN (111, 112, 113)
						AND (
							@IsLive = 2
							OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
							OR (b.bettype = 2799 AND @IsLive = 0)
							OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
						)
				) AS b
				INNER JOIN #tblBetType bt ON b.bettype = bt.bettype AND bt.ProductId = c.ProductId
			GROUP BY
				b.srecommend
				,b.matchid
				,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END
			OPTION (OPTIMIZE FOR (@n = 1))

			INSERT INTO #tmpSumWinloss
			(
				CustId
				,Wagers
				,Stake
				,ValidStake
				,MemberIncome
				,Agent
				,AgentResult
				,Master
				,Super
				,SuperIncome
				,SuperResult
				,SuperStock
				,HeadlineIncome
				,HeadlineResult
				,HeadlineStock
			)
			SELECT
				b.srecommend			AS CustId
				,SUM(Wagers)			AS Wagers
				,SUM(Stake)				AS Stake
				,SUM(ValidStake)		AS ValidStake
				,SUM(MemberIncome)		AS MemberIncome
				,SUM(Agent)				AS Agent
				,SUM(AgentResult)		AS AgentResult
				,SUM(Master)			AS Master
				,SUM(Super)				AS Super
				,SUM(SuperIncome)		AS SuperIncome
				,SUM(SuperResult)		AS SuperResult
				,SUM(SuperStock)		AS SuperStock
				,SUM(HeadlineIncome)	AS HeadlineIncome
				,SUM(HeadlineResult)	AS HeadlineResult
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
		END
		-- End bettrans

		DROP TABLE #tmpBettrans

		-- CS_SumWinloss
		IF @FromDate <= @MoveBetsDay
		BEGIN
			SELECT	@FDate = CASE WHEN @FromDate < @ArchiveDate THEN @ArchiveDate ELSE @FromDate END
					,@TDate = CASE WHEN @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

			IF @IsAllDownline = 1
			BEGIN
				INSERT INTO #tmpSumWinloss
				(
					CustId
					,Wagers
					,Stake
					,ValidStake
					,MemberIncome
					,Agent
					,AgentResult
					,Master
					,Super
					,SuperIncome
					,SuperResult
					,SuperStock
					,HeadlineIncome
					,HeadlineResult
					,HeadlineStock
				)
				SELECT
					s.CustId
					,SUM(Wagers)			AS Wagers
					,SUM(Stake)				AS Stake
					,SUM(ValidStake)		AS ValidStake
					,SUM(MemberWinloss + MemberComm)		AS MemberIncome
					,SUM(Agent)				AS Agent
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm)			AS AgentResult
					,SUM(Master)			AS Master
					,SUM(Super)				AS Super
					,SUM(SuperWinloss + SuperComm)			AS SuperIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm
						+ MasterWinloss + MasterComm
						+ SuperWinloss + SuperComm)			AS SuperResult
					,SUM(SuperStock)		AS SuperStock
					,SUM(HeadlineWinloss + HeadlineComm)	AS HeadlineIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm
						+ MasterWinloss + MasterComm
						+ SuperWinloss + SuperComm
						+ HeadlineWinloss + HeadlineComm)	AS HeadlineResult
					,SUM(HeadlineStock)		AS HeadlineStock
				FROM bodb_Summary.dbo.CS_SumWinloss s WITH (NOLOCK)
				WHERE s.WinlostDate BETWEEN @FDate AND @TDate
					AND EXISTS (SELECT 1 FROM @Customers c WHERE s.CustID = c.CustId)
					AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
					AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
					AND (@IsLive = 2 OR IsLive = @IsLive)
				GROUP BY
					s.CustId
			END
			ELSE
			BEGIN
				INSERT INTO #tmpSumWinloss
				(
					CustId
					,Wagers
					,Stake
					,ValidStake
					,MemberIncome
					,Agent
					,AgentResult
					,Master
					,Super
					,SuperIncome
					,SuperResult
					,SuperStock
					,HeadlineIncome
					,HeadlineResult
					,HeadlineStock
				)
				SELECT
					@CustId
					,SUM(Wagers)			AS Wagers
					,SUM(Stake)				AS Stake
					,SUM(ValidStake)		AS ValidStake
					,SUM(MemberWinloss + MemberComm)		AS MemberIncome
					,SUM(Agent)				AS Agent
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm)			AS AgentResult
					,SUM(Master)			AS Master
					,SUM(Super)				AS Super
					,SUM(SuperWinloss + SuperComm)			AS SuperIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm
						+ MasterWinloss + MasterComm
						+ SuperWinloss + SuperComm)			AS SuperResult
					,SUM(SuperStock)		AS SuperStock
					,SUM(HeadlineWinloss + HeadlineComm)	AS HeadlineIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm
						+ MasterWinloss + MasterComm
						+ SuperWinloss + SuperComm
						+ HeadlineWinloss + HeadlineComm)	AS HeadlineResult
					,SUM(HeadlineStock)		AS HeadlineStock
				FROM bodb_Summary.dbo.CS_SumWinloss s WITH (NOLOCK)
				WHERE s.WinlostDate BETWEEN @FDate AND @TDate
					AND EXISTS (SELECT 1 FROM @Downlines c WHERE s.CustID = c.DownlineId)
					AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
					AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
					AND (@IsLive = 2 OR IsLive = @IsLive)
				HAVING COUNT(1) > 0
			END
		END

		-- CS_SumCancelled_Old
		IF @FromDate < @ArchiveDate
		BEGIN
			SELECT	@FDate = @FromDate
					,@TDate = CASE WHEN @ToDate >= @ArchiveDate THEN DATEADD(DAY, -1, @ArchiveDate) ELSE @ToDate END

			IF @IsAllDownline = 1
			BEGIN
				INSERT INTO #tmpSumWinloss
				(
					CustId
					,Wagers
					,Stake
					,ValidStake
					,MemberIncome
					,Agent
					,AgentResult
					,Master
					,Super
					,SuperIncome
					,SuperResult
					,SuperStock
					,HeadlineIncome
					,HeadlineResult
					,HeadlineStock
				)
				SELECT
					s.CustId
					,SUM(Wagers)			AS Wagers
					,SUM(Stake)				AS Stake
					,SUM(ValidStake)		AS ValidStake
					,SUM(MemberWinloss + MemberComm)		AS MemberIncome
					,SUM(Agent)				AS Agent
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm)			AS AgentResult
					,SUM(Master)			AS Master
					,SUM(Super)				AS Super
					,SUM(SuperWinloss + SuperComm)			AS SuperIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm
						+ MasterWinloss + MasterComm
						+ SuperWinloss + SuperComm)			AS SuperResult
					,SUM(SuperStock)		AS SuperStock
					,SUM(HeadlineWinloss + HeadlineComm)	AS HeadlineIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm
						+ MasterWinloss + MasterComm
						+ SuperWinloss + SuperComm
						+ HeadlineWinloss + HeadlineComm)	AS HeadlineResult
					,SUM(HeadlineStock)		AS HeadlineStock
				FROM bodb_Summary.dbo.CS_SumWinloss_Old s WITH (NOLOCK)
				WHERE s.WinlostDate BETWEEN @FDate AND @TDate
					AND EXISTS (SELECT 1 FROM @Customers c WHERE s.CustID = c.CustId)
					AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
					AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
					AND (@IsLive = 2 OR IsLive = @IsLive)
				GROUP BY
					s.CustId
			END
			ELSE
			BEGIN
				INSERT INTO #tmpSumWinloss
				(
					CustId
					,Wagers
					,Stake
					,ValidStake
					,MemberIncome
					,Agent
					,AgentResult
					,Master
					,Super
					,SuperIncome
					,SuperResult
					,SuperStock
					,HeadlineIncome
					,HeadlineResult
					,HeadlineStock
				)
				SELECT
					@CustId
					,SUM(Wagers)			AS Wagers
					,SUM(Stake)				AS Stake
					,SUM(ValidStake)		AS ValidStake
					,SUM(MemberWinloss + MemberComm)		AS MemberIncome
					,SUM(Agent)				AS Agent
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm)			AS AgentResult
					,SUM(Master)			AS Master
					,SUM(Super)				AS Super
					,SUM(SuperWinloss + SuperComm)			AS SuperIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm
						+ MasterWinloss + MasterComm
						+ SuperWinloss + SuperComm)			AS SuperResult
					,SUM(SuperStock)		AS SuperStock
					,SUM(HeadlineWinloss + HeadlineComm)	AS HeadlineIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm
						+ MasterWinloss + MasterComm
						+ SuperWinloss + SuperComm
						+ HeadlineWinloss + HeadlineComm)	AS HeadlineResult
					,SUM(HeadlineStock)		AS HeadlineStock
				FROM bodb_Summary.dbo.CS_SumWinloss_Old s WITH (NOLOCK)
				WHERE s.WinlostDate BETWEEN @FDate AND @TDate
					AND EXISTS (SELECT 1 FROM @Downlines c WHERE s.CustID = c.DownlineId)
					AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
					AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
					AND (@IsLive = 2 OR IsLive = @IsLive)
				HAVING COUNT(1) > 0
			END
		END
	END
	/* ===== End Get data ===== */

	DROP TABLE #tblBetType
	DROP TABLE #tblSportType

	/* ===== Return result ===== */
	BEGIN
		SELECT
			c.CustId
			,c.Username
			,c.FirstName			AS Name
			,SUM(Wagers)			AS Wagers
			,SUM(Stake)				AS Stake
			,SUM(ValidStake)		AS ValidStake
			,SUM(MemberIncome)		AS MemberIncome
			,SUM(Agent)				AS Agent
			,SUM(AgentResult)		AS AgentResult
			,SUM(Master)			AS Master
			,SUM(Super)				AS Super
			,SUM(SuperIncome)		AS SuperIncome
			,SUM(SuperResult)		AS SuperResult
			,SUM(SuperStock)		AS SuperStock
			,SUM(HeadlineIncome)	AS HeadlineIncome
			,SUM(HeadlineResult)	AS HeadlineResult
			,SUM(HeadlineStock)		AS HeadlineStock
		FROM #tmpSumWinloss s
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON c.CustID = s.CustID
		GROUP BY
			c.CustId
			,c.Username
			,c.FirstName
	END
	/* ===== End Return result ===== */

	DROP TABLE #tmpSumWinloss
END
GO