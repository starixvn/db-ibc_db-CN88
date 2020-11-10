/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_HL_Rpt_Winloss_Super]
	@HeadlineId			INT
	,@CustId			INT
	,@FromDate			SMALLDATETIME
	,@ToDate			SMALLDATETIME
	,@MoveBetsDay		SMALLDATETIME
	,@SporttypeGroups	VARCHAR(MAX) = '0' -- all
	,@BettypeGroup		SMALLINT = 0 -- all
	,@IsLive			TINYINT = 2  -- all
AS

/*
	Created: 20190926@Percy
	Task: CN88 - HL - Settled Report - View Supers
	DB: DBAGE.bodb02
	
	Revisions:
		- 20190926@Percy: Initialize SP [Redmine: #118962]
		- 20201110@Malcolm: Get extraPT from the epositiontaking column of bettrans [RedmineID: #145074]
		
	Param's Explanation:
		- @HeadlineId: HeadlineId
		- @CustId: HeadlineId
		- @SporttypeGroups: list of SporttypeGroup
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
		SELECT DISTINCT SportType FROM dbo.CS_f_SporttypeMatrix_Sel (0, @SporttypeGroups, @BetTypeGroup, @IsTest)

		CREATE TABLE #tblBetType (ProductID INT, BetType INT, EventType TINYINT)
		INSERT INTO #tblBetType (ProductID, BetType, EventType)
		SELECT DISTINCT ProductID, BetType, EventType FROM dbo.CS_f_BettypeMatrix_Sel (0, @SporttypeGroups, @BetTypeGroup, @IsTest)
	END
	/* ===== End Get Sport/Bettype ===== */

	/* ===== Get Super Info ===== */
	BEGIN
		CREATE TABLE #tmpSuper (srecommend INT, FromDate SMALLDATETIME, ToDate SMALLDATETIME)
		INSERT INTO #tmpSuper (srecommend, FromDate, ToDate)
		SELECT SuperId, CASE WHEN FromDate < @FromDate THEN @FromDate ELSE FromDate END, CASE WHEN ToDate > @ToDate THEN @ToDate ELSE ToDate END
		FROM dbo.Acc_GroupExtraPTSetting WITH (NOLOCK)
		WHERE UplineId = @HeadlineId
			AND ProductId = 1
			AND Sporttype = 0
			AND SubProduct = ''
			AND @FromDate <= ToDate AND @ToDate >= FromDate
	END
	/* ===== End Get Super Info ===== */

	/* ===== Get Data ===== */
	BEGIN
		CREATE TABLE #SuperWinLoss
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

		DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME

		-- bettrans
		IF @ToDate > @MoveBetsDay
		BEGIN
			SELECT	@FDate = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
					,@TDate = @ToDate
		
			IF OBJECT_ID('tempdb..#tmpBettrans') IS NOT NULL
				DROP TABLE #tmpBettrans

			IF OBJECT_ID('tempdb..#__refno') IS NOT NULL
				DROP TABLE #__refno

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

			-- For VS Parlay (bettype = 2799)
			SELECT b.refno, b.matchid
			INTO #__refno
			FROM #tmpSuper ts
				CROSS APPLY (
					SELECT b.refno, bm.matchid
					FROM dbo.bettrans b WITH (NOLOCK)
						CROSS APPLY (SELECT TOP 1 bm.matchid FROM dbo.bettransm bm WITH (NOLOCK) WHERE b.refno = bm.refno) AS bm
					WHERE ts.srecommend = b.srecommend AND b.matchid = 2799 AND b.winlostdate BETWEEN ts.FromDate AND ts.ToDate
						AND b.winlostdate BETWEEN @FDate AND @TDate
						AND b.statusID NOT IN (0, 1)
			) AS b

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
				,b.eventtype
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
				,SUM( -- HeadlineIncome = HeadlineWinloss + HeadlineComm
					- (b.winlost - b.actual_stake) * ISNULL(CONVERT(DECIMAL(9,8), b.epositiontaking), 0) -- HeadlineWinloss
					- CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm / (1 - b.tpositiontaking) * ISNULL(CONVERT(DECIMAL(9,8), b.epositiontaking), 0) END -- HeadlineComm
					) AS HeadlineIncome
				,SUM( -- HeadlineResult = -HouseIncome = -(HouseWinloss + HouseComm)
					b.winlost - b.actual_stake + b.swinlost + b.mwinlost + b.awinlost - ((b.winlost - b.actual_stake) * ISNULL(CONVERT(DECIMAL(9,8), b.epositiontaking), 0)) -- HouseWinloss
					+ b.scomm - CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm / (1 - b.tpositiontaking) * ISNULL(CONVERT(DECIMAL(9,8), b.epositiontaking), 0) END -- HouseComm
					) AS HeadlineResult 
				,SUM(ABS(b.winlost - b.actual_stake) * (1 - b.tpositiontaking - ISNULL(CONVERT(DECIMAL(9,8), b.epositiontaking), 0))) AS HeadlineStock
			FROM #tmpSuper ts
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
						,b.awinlost
						,b.mwinlost
						,b.swinlost
						,b.playercomm
						,b.comm
						,b.acomm
						,b.scomm
						,b.discount
						,b.adiscount
						,b.sdiscount
						,b.apositiontaking
						,b.mpositiontaking
						,b.tpositiontaking
						,b.epositiontaking
						,b.winlostdate
					FROM dbo.bettrans b WITH (NOLOCK)
						INNER JOIN #tblBetType bt ON b.bettype = bt.bettype
						OUTER APPLY (
							SELECT r.matchid FROM #__refno r WHERE b.refno = r.refno AND b.bettype = 2799
						) AS s
					WHERE ts.srecommend = b.srecommend AND b.winlostdate BETWEEN ts.FromDate AND ts.ToDate
						AND b.winlostdate BETWEEN @FDate AND @TDate
						AND b.statusID NOT IN (0, 1)
						AND (
								@IsLive = 2
								OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
								OR (b.bettype = 2799 AND @IsLive = 0)
								OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
							)
				) AS b
			GROUP BY
				b.srecommend
				,b.matchid
				,b.eventtype

			DROP TABLE #__refno

			INSERT INTO #SuperWinLoss
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
			OPTION (HASH GROUP)

			DROP TABLE #tmpBettrans
		END
		-- End bettrans

		-- CS_SumWinloss
		IF @FromDate <= @MoveBetsDay
		BEGIN
			SELECT	@FDate = @FromDate
					,@TDate = CASE WHEN @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

			IF @FDate <= @TDate
			BEGIN
				INSERT INTO #SuperWinLoss
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
					CustId
					,SUM(Wagers)		AS Wagers
					,SUM(Stake)			AS Stake
					,SUM(ValidStake)	AS ValidStake
					,SUM(MemberWinloss + MemberComm)		AS MemberIncome
					,SUM(Agent)			AS Agent
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm)			AS AgentResult
					,SUM(Master)		AS Master
					,SUM(Super)			AS Super
					,SUM(SuperWinloss + SuperComm)			AS SuperIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm
						+ MasterWinloss + MasterComm
						+ SuperWinloss + SuperComm)			AS SuperResult
					,SUM(SuperStock)	AS SuperStock
					,SUM(HeadlineWinloss + HeadlineComm)	AS HeadlineIncome
					,SUM(MemberWinloss + MemberComm
						+ AgentWinloss + AgentComm
						+ MasterWinloss + MasterComm
						+ SuperWinloss + SuperComm
						+ HeadlineWinloss + HeadlineComm)	AS HeadlineResult
					,SUM(HeadlineStock) AS HeadlineStock
				FROM #tmpSuper ts
					CROSS APPLY (
						SELECT
							CustId
							,Wagers
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
							,Agent
							,Master
							,Super
							,SuperStock
							,HeadlineStock
						FROM bodb_Summary.dbo.CS_SumWinloss s WITH (NOLOCK)
						WHERE s.custid = ts.srecommend
							AND s.WinlostDate BETWEEN @FDate AND @TDate
							AND s.WinlostDate BETWEEN ts.FromDate AND ts.ToDate
							AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
							AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
							AND (@IsLive = 2 OR IsLive = @IsLive)
					) AS s
				GROUP BY
					CustId

				INSERT INTO #SuperWinLoss
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
					CustId
					,SUM(Wagers)		AS Wagers
					,SUM(Stake)			AS Stake
					,0 AS ValidStake
					,0 AS MemberIncome
					,0 AS Agent
					,0 AS AgentResult
					,0 AS Master
					,0 AS Super
					,0 AS SuperIncome
					,0 AS SuperResult
					,0 AS SuperStock
					,0 AS HeadlineIncome
					,0 AS HeadlineResult
					,0 AS HeadlineStock
				FROM #tmpSuper ts
					CROSS APPLY (
						SELECT
							CustId
							,Wagers
							,Stake
						FROM bodb_Summary.dbo.CS_SumCancelled s WITH (NOLOCK)
						WHERE s.custid = ts.srecommend
							AND s.WinlostDate BETWEEN @FDate AND @TDate
							AND s.WinlostDate BETWEEN ts.FromDate AND ts.ToDate
							AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
							AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
							AND (@IsLive = 2 OR IsLive = @IsLive)
					) AS s
				GROUP BY
					CustId
			END
		END
		-- End CS_SumWinloss
	END
	/* ===== End Get Data ===== */

	/* ===== Return Data ===== */
	BEGIN
		SELECT
			c.CustId
			,c.Username
			,c.FirstName			AS Name
			,SUM(s.Wagers)			AS Wagers
			,SUM(s.Stake)			AS Stake
			,SUM(s.ValidStake)		AS ValidStake
			,SUM(s.MemberIncome)	AS MemberIncome
			,SUM(s.Agent)			AS Agent
			,SUM(s.AgentResult)		AS AgentResult
			,SUM(s.Master)			AS Master
			,SUM(s.Super)			AS Super
			,SUM(s.SuperIncome)		AS SuperIncome
			,SUM(s.SuperResult)		AS SuperResult
			,SUM(s.SuperStock)		AS SuperStock
			,SUM(s.HeadlineIncome)	AS HeadlineIncome
			,SUM(s.HeadlineResult)	AS HeadlineResult
			,SUM(s.HeadlineStock)	AS HeadlineStock
		FROM #SuperWinLoss s
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON s.custid = c.custid
		GROUP BY
			c.CustId
			,c.Username
			,c.FirstName
	END
	/* ===== End Return Data ===== */
	
	DROP TABLE #SuperWinLoss
	DROP TABLE #tblBetType
	DROP TABLE #tblSportType
	DROP TABLE #tmpSuper
END
GO