/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Rpt_Winloss_Agent]
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
	@IsLive				TINYINT = 2 -- all
AS

/*
	Created: 20190214@Sophia
	Task: CN88 - Agent report
	DB: DBAGE.bodb02	
	
	Revisions:
		- 20190214@Sophia: Create new [RedmineID: #105660] 
		- 20190329@Sophia: Implement Non Sports [Redmine: #109521]
		- 20190528@Sophia: Fix bug VS [Redmine: #113482]
		- 20190713@Percy: Add sub account - permission on downlines [RedmineID: #116825]
		
	Param's Explanation:
		- @CustId: MasterID or AgentID
		- @SubAccId: sub account
		- @IsAllDownline: is view all downlines
		- @IsOwner: Upline view Agent or not (if @CustId = AgentId then @IsOwner = 1, if @CustId = MasterId then @IsOwner = 0)
		- @ProductId: default = 1: Sportsbook
		- @BettypeGroup: default = 0: All
		- @SporttypeGroup: default = 0: All
		- @IsLive: default = 2: All
						= 1: Live
						= 0: Dead
*/

BEGIN
	SET NOCOUNT ON

	/* ===== Get SportBettypeMatrix ===== */
	BEGIN
		DECLARE @isTest BIT = 0
		SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

		CREATE TABLE #tblSportType (SportType INT)
		INSERT INTO #tblSportType (SportType)
		SELECT DISTINCT SportType FROM dbo.CS_f_SporttypeMatrix_Sel (0, @SportTypeGroup, @BetTypeGroup, @IsTest)

		CREATE TABLE #tblBetType (BetType INT, EventType TINYINT)
		INSERT INTO #tblBetType (BetType, EventType)
		SELECT DISTINCT BetType, EventType FROM dbo.CS_f_BettypeMatrix_Sel (0, @SportTypeGroup, @BetTypeGroup, @IsTest)
	END
	/* ===== End Get SportBettypeMatrix ===== */

	/* ===== Get Customer List ===== */
	BEGIN
		DECLARE @Customers TABLE (CustId INT)
		DECLARE @Downlines TABLE (DownlineId INT)
		
		IF @IsOwner = 1 -- View owner
		BEGIN
			INSERT INTO @Customers (CustId)
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
				INSERT INTO @Customers (CustId)
				SELECT DownlineId FROM dbo.CS_f_GetDownlineBySubAcc(@SubAccId)
			END
			/* ===== End Get downline list by Sub Account ==== */
			ELSE
			BEGIN
				INSERT INTO @Customers (CustId)
				SELECT CustId
				FROM dbo.Customer WITH (NOLOCK)
				WHERE mrecommend = @CustId AND roleid = 2
			END

			SELECT @IsAllDownline = 1
		END
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
			,AgentIncome	MONEY
			,AgentResult	MONEY
			,AgentStock		MONEY
			,MasterIncome	MONEY
			,MasterResult	MONEY
		)

		-- bettrans
		CREATE TABLE #tmpBettrans
		(
			recommend		INT
			,matchid		INT
			,eventtype		TINYINT
			,Wagers			INT
			,Stake			MONEY
			,ValidStake		MONEY
			,MemberIncome	MONEY
			,Agent			MONEY
			,AgentIncome	MONEY
			,AgentResult	MONEY
			,AgentStock		MONEY
			,MasterIncome	MONEY
			,MasterResult	MONEY
		)
		
		IF @ToDate > @MoveBetsDay
		BEGIN
			SELECT	@FDate = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
					,@TDate = @ToDate
		
			INSERT INTO #tmpBettrans
			(
				recommend
				,matchid
				,eventtype
				,Wagers
				,Stake
				,ValidStake
				,MemberIncome
				,Agent
				,AgentIncome
				,AgentResult
				,AgentStock
				,MasterIncome
				,MasterResult
			)
			SELECT
				b.recommend
				,b.matchid
				,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END AS eventtype
				,COUNT(1) AS Wagers
				,SUM(b.stake) AS Stake
				,SUM(ABS(b.winlost - b.actual_stake)) AS ValidStake
				,SUM(b.winlost - b.actual_stake + b.playercomm) AS MemberIncome
				,SUM((b.winlost - b.actual_stake)  + (ABS(b.winlost - b.actual_stake) * b.discount)) AS Agent
				,SUM(b.awinlost + b.comm - b.playercomm) AS AgentIncome
				,SUM(b.winlost - b.actual_stake + b.awinlost + b.comm) AS AgentResult
				,SUM(ABS(b.winlost - b.actual_stake) * (1 - b.apositiontaking)) AS AgentStock
				,SUM(b.mwinlost + b.acomm - b.comm) AS MasterIncome
				,SUM(b.winlost - b.actual_stake + b.mwinlost + b.awinlost + b.acomm) AS MasterResult
			FROM @Customers c
				CROSS APPLY (
					SELECT
						b.recommend
						,CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END AS matchid
						,b.bettype
						,b.stake
						,b.winlost
						,b.actual_stake
						,b.playercomm
						,b.awinlost
						,b.mwinlost
						,b.acomm
						,b.comm
						,b.discount
						,b.apositiontaking
					FROM dbo.bettrans b WITH (NOLOCK)
						OUTER APPLY (
							SELECT TOP 1 bm.matchid
							FROM dbo.bettransm bm WITH (NOLOCK)
							WHERE b.refno = bm.refno AND b.bettype = 2799
						) AS s
					WHERE c.CustId = b.recommend AND b.winlostdate BETWEEN @FDate AND @TDate
						AND (@IsAllDownline = 1 OR EXISTS (SELECT 1 FROM @Downlines d WHERE b.custid = d.DownlineId))
						AND b.statusID IN (111, 112, 113)
						AND (
							@IsLive = 2
							OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
							OR (b.bettype = 2799 AND @IsLive = 0)
							OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
						)
				) AS b
				INNER JOIN #tblBetType bt ON b.bettype = bt.bettype
			GROUP BY
				b.recommend
				,b.matchid
				,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END
			OPTION (HASH GROUP)

			INSERT INTO #tmpSumWinloss
			(
				CustId
				,Wagers
				,Stake
				,ValidStake
				,MemberIncome
				,Agent
				,AgentIncome
				,AgentResult
				,AgentStock
				,MasterIncome
				,MasterResult
			)
			SELECT
				b.recommend			AS CustId
				,SUM(Wagers)			AS Wagers
				,SUM(Stake)				AS Stake
				,SUM(ValidStake)		AS ValidStake
				,SUM(MemberIncome)		AS MemberIncome
				,SUM(Agent)				AS Agent
				,SUM(AgentIncome)		AS AgentIncome
				,SUM(AgentResult)		AS AgentResult
				,SUM(AgentStock)		AS AgentStock
				,SUM(MasterIncome)		AS MasterIncome
				,SUM(MasterResult)		AS MasterResult
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
				b.recommend
			OPTION (HASH GROUP)
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
					,AgentIncome
					,AgentResult
					,AgentStock
					,MasterIncome
					,MasterResult
				)
				SELECT
					s.CustId
					,SUM(Wagers)			AS Wagers
					,SUM(Stake)				AS Stake
					,SUM(ValidStake)		AS ValidStake
					,SUM(MemberWinloss + MemberComm)		AS MemberIncome
					,SUM(Agent)				AS Agent
					,SUM(AgentWinloss + AgentComm)			AS AgentIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm)			AS AgentResult
					,SUM(AgentStock)		AS AgentStock
					,SUM(MasterWinloss + MasterComm)		AS MasterIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm
						+ MasterWinloss + MasterComm)		AS MasterResult
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
					,AgentIncome
					,AgentResult
					,AgentStock
					,MasterIncome
					,MasterResult
				)
				SELECT
					s.CustId
					,SUM(Wagers)			AS Wagers
					,SUM(Stake)				AS Stake
					,SUM(ValidStake)		AS ValidStake
					,SUM(MemberWinloss + MemberComm)		AS MemberIncome
					,SUM(Agent)				AS Agent
					,SUM(AgentWinloss + AgentComm)			AS AgentIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm)			AS AgentResult
					,SUM(AgentStock)		AS AgentStock
					,SUM(MasterWinloss + MasterComm)		AS MasterIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm
						+ MasterWinloss + MasterComm)		AS MasterResult
				FROM bodb_Summary.dbo.CS_SumWinloss s WITH (NOLOCK)
				WHERE s.WinlostDate BETWEEN @FDate AND @TDate
					AND EXISTS (SELECT 1 FROM @Downlines c WHERE s.CustID = c.DownlineId)
					AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
					AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
					AND (@IsLive = 2 OR IsLive = @IsLive)
				GROUP BY
					s.CustId
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
					,AgentIncome
					,AgentResult
					,AgentStock
					,MasterIncome
					,MasterResult
				)
				SELECT
					s.CustId
					,SUM(Wagers)			AS Wagers
					,SUM(Stake)				AS Stake
					,SUM(ValidStake)		AS ValidStake
					,SUM(MemberWinloss + MemberComm)		AS MemberIncome
					,SUM(Agent)				AS Agent
					,SUM(AgentWinloss + AgentComm)			AS AgentIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm)			AS AgentResult
					,SUM(AgentStock)		AS AgentStock
					,SUM(MasterWinloss + MasterComm)		AS MasterIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm
						+ MasterWinloss + MasterComm)		AS MasterResult
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
					,AgentIncome
					,AgentResult
					,AgentStock
					,MasterIncome
					,MasterResult
				)
				SELECT
					s.CustId
					,SUM(Wagers)			AS Wagers
					,SUM(Stake)				AS Stake
					,SUM(ValidStake)		AS ValidStake
					,SUM(MemberWinloss + MemberComm)		AS MemberIncome
					,SUM(Agent)				AS Agent
					,SUM(AgentWinloss + AgentComm)			AS AgentIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm)			AS AgentResult
					,SUM(AgentStock)		AS AgentStock
					,SUM(MasterWinloss + MasterComm)		AS MasterIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm
						+ MasterWinloss + MasterComm)		AS MasterResult
				FROM bodb_Summary.dbo.CS_SumWinloss_Old s WITH (NOLOCK)
				WHERE s.WinlostDate BETWEEN @FDate AND @TDate
					AND EXISTS (SELECT 1 FROM @Downlines c WHERE s.CustID = c.DownlineId)
					AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
					AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
					AND (@IsLive = 2 OR IsLive = @IsLive)
				GROUP BY
					s.CustId
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
			,SUM(AgentIncome)		AS AgentIncome
			,SUM(AgentResult)		AS AgentResult
			,SUM(AgentStock)		AS AgentStock
			,SUM(MasterIncome)		AS MasterIncome
			,SUM(MasterResult)		AS MasterResult
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
