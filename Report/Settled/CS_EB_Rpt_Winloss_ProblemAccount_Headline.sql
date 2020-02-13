/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_EB_Rpt_Winloss_ProblemAccount_Headline]
	@ReportMode			TINYINT = 1
	,@FromDate			SMALLDATETIME
	,@ToDate			SMALLDATETIME
	,@MoveBetsDay		SMALLDATETIME
	,@SporttypeGroups	VARCHAR(MAX) = '0' -- all
	,@BettypeGroup		SMALLINT = 0 -- all
	,@IsLive			TINYINT = 2  -- all
	,@IsExcludedTest	BIT = 1
	,@IsHeadLineGroup   SMALLINT = 0 -- all
AS

/*
	Created: 20191021@Percy
	Task: CN88 - EB - Problem Account Settled Report - View Headlines
	DB: DBAGE.bodb02
	
	Revisions:
		- 20191021@Percy: Initialize SP [Redmine: #122191]
		- 20200210@Malcolm : New group of Headline XPG - Changes on EB [RedmineID : #127209]
		- 20200212@Percy: Missing HouseTurnover on CS_SumCancelled [RedmineID: #128441]
		
	Param's Explanation:
		- @ReportMode: 1: current, 2: history
		- @SporttypeGroup: default = 0: All
		- @BettypeGroup: default = 0: All
		- @IsLive: (market) default = 2: All
									= 1: Live
									= 0: Dead
		- @IsHeadLineGroup: default = 0: all headlines
		                            = 1: XPG headlines
									= 2: Other headlines
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

	/* ===== Get Cust Super ===== */
	BEGIN
	     CREATE TABLE #CS_CustSuper(CustID INT NOT NULL PRIMARY KEY)

		 INSERT INTO #CS_CustSuper(CustID)
		 SELECT c.CustId
	     FROM dbo.CS_CustSuper c 
		      LEFT JOIN dbo.f_GetHeadlineNoPT() f ON c.CustId = f.SuperId
		 WHERE @IsHeadLineGroup = 0 OR (@IsHeadLineGroup = 1 AND f.SuperId IS NOT NULL) OR (@IsHeadLineGroup = 2 AND f.SuperId IS NULL)
	END 
	/* ===== Get End Cust Super ===== */

	/* ===== Get Data ===== */
	BEGIN
		CREATE TABLE #HeadlineWinLoss
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

			IF OBJECT_ID('tempdb..#__refno') IS NOT NULL
				DROP TABLE #__refno

			CREATE TABLE #tmpBettrans
			(
				UplineId		INT
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

			-- For VS Parlay (bettype = 2799)
			SELECT b.refno, b.matchid
			INTO #__refno
			FROM #CS_CustSuper c WITH (NOLOCK)
				CROSS APPLY (
					SELECT b.refno, bm.matchid
					FROM dbo.bettrans b WITH (NOLOCK)
						CROSS APPLY (SELECT TOP 1 bm.matchid FROM dbo.bettransm bm WITH (NOLOCK) WHERE b.refno = bm.refno) AS bm
					WHERE c.custid = b.srecommend AND b.matchid = 2799 AND b.winlostdate BETWEEN @FDate AND @TDate
						AND b.statusID NOT IN (0, 1)
			) AS b

			INSERT INTO #tmpBettrans
			(
				UplineId
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
				e.UplineId
				,b.matchid
				,b.eventtype
				,COUNT(1) AS Wagers
				,SUM(b.stake) AS Stake
				,SUM(ABS(b.winlost - b.actual_stake)) AS ValidStake
				,SUM(b.winlost - b.actual_stake) AS MemberWinloss
				,SUM(b.playercomm) AS MemberComm
				,SUM(b.scomm - b.acomm) AS SuperComm
				,-SUM(b.winlost - b.actual_stake + b.swinlost + b.mwinlost + b.awinlost - ((b.winlost - b.actual_stake) * ISNULL(CONVERT(DECIMAL(9,8), b.epositiontaking), 0))) AS HouseWinloss
				,-SUM(b.scomm - CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.scomm / (1 - b.tpositiontaking) * ISNULL(CONVERT(DECIMAL(9,8), b.epositiontaking), 0) END) AS HouseComm
				,SUM(b.stake * (1 - b.tpositiontaking - ISNULL(CONVERT(DECIMAL(9,8), b.epositiontaking), 0))) AS HouseTurnover
				,SUM(ABS(b.winlost - b.actual_stake) * (1 - b.tpositiontaking - ISNULL(CONVERT(DECIMAL(9,8), b.epositiontaking), 0))) AS HeadlineStock
			FROM #CS_CustSuper cs WITH (NOLOCK)
				CROSS APPLY (
					SELECT
						CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END AS matchid
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
						,b.epositiontaking
						,b.winlostdate
					FROM dbo.bettrans b WITH (NOLOCK)
						INNER JOIN #tblBetType bt ON b.bettype = bt.bettype
						OUTER APPLY (
							SELECT r.matchid FROM #__refno r WHERE b.refno = r.refno AND b.bettype = 2799
						) AS s
					WHERE cs.CustId = b.srecommend AND b.winlostdate BETWEEN @FDate AND @TDate
						AND b.statusID NOT IN (0, 1)
						AND (
								@IsLive = 2
								OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
								OR (b.bettype = 2799 AND @IsLive = 0)
								OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
							)
						AND (@IsExcludedTest = 0 OR b.currency <> 20)
						AND EXISTS (SELECT 1 FROM dbo.CS_ProblemAccount pa WITH (NOLOCK) WHERE b.custid = pa.custid)
				) AS b
				OUTER APPLY (
					SELECT ag.UplineId
					FROM dbo.Acc_GroupExtraPTSetting ag WITH (NOLOCK)
					WHERE cs.CustId = ag.SuperId
						AND b.winlostdate BETWEEN ag.FromDate AND ag.ToDate
						AND b.ProductID = ag.ProductId
						AND ag.Sporttype = 0
						AND ag.SubProduct = ''
				) AS e
			GROUP BY
				e.UplineId
				,b.matchid
				,b.eventtype

			DROP TABLE #__refno
	
			INSERT INTO #HeadlineWinLoss
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
				b.UplineId			AS CustId
				,SUM(Wagers)		AS Wagers
				,SUM(Stake)			AS Stake
				,SUM(ValidStake)	AS ValidStake
				,SUM(MemberWinloss)	AS MemberWinloss
				,SUM(MemberComm)	AS MemberComm
				,SUM(SuperComm)		AS SuperComm
				,SUM(HouseWinloss)	AS HouseWinloss
				,SUM(HouseComm)		AS HouseComm
				,SUM(HouseTurnover)	AS HouseTurnover
				,SUM(HeadlineStock)	AS HeadlineStock
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
				b.UplineId
			OPTION (HASH GROUP)

			DROP TABLE #tmpBettrans
		END
		-- End bettrans

		-- CS_SumWinloss
		IF (@ReportMode = 1 AND @FromDate <= @MoveBetsDay) OR @ReportMode = 2
		BEGIN
			SELECT	@FDate = @FromDate
					,@TDate = CASE WHEN @ReportMode = 1 AND @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

			IF @FDate <= @TDate
			BEGIN
				INSERT INTO #HeadlineWinLoss
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
					s.UplineId
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
				FROM dbo.Customer c WITH (NOLOCK)
					INNER JOIN dbo.CS_ProblemAccount pa WITH (NOLOCK) ON c.custid = pa.custid AND c.roleid = 1
					CROSS APPLY (
						SELECT
							s.HeadlineId AS UplineId
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
							,HouseTurnover
							,HeadlineStock
						FROM bodb_Summary.dbo.CS_SumWinloss s WITH (NOLOCK)
						WHERE s.custid = c.custid
							AND s.WinlostDate BETWEEN @FDate AND @TDate
							AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
							AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
							AND (@IsLive = 2 OR IsLive = @IsLive)
					) AS s
				WHERE (c.currency <> 20 OR @IsExcludedTest = 0) 
				      AND EXISTS(SELECT 1 FROM #CS_CustSuper cs_ WHERE cs_.CustID = c.srecommend)
				GROUP BY
					s.UplineId

				INSERT INTO #HeadlineWinLoss
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
					s.UplineId
					,SUM(Wagers)		AS Wagers
					,SUM(Stake)			AS Stake
					,0 AS ValidStake
					,0 AS MemberWinloss
					,0 AS MemberComm
					,0 AS SuperComm
					,0 AS HouseWinloss
					,0 AS HouseComm
					,SUM(HouseTurnover) AS HouseTurnover
					,0 AS HeadlineStock
				FROM dbo.Customer c WITH (NOLOCK)
					INNER JOIN dbo.CS_ProblemAccount pa WITH (NOLOCK) ON c.custid = pa.custid AND c.roleid = 1
					CROSS APPLY (
						SELECT
							s.HeadlineId AS UplineId
							,Wagers
							,Stake
							,HouseTurnover
						FROM bodb_Summary.dbo.CS_SumCancelled s WITH (NOLOCK)
						WHERE s.custid = c.custid
							AND s.WinlostDate BETWEEN @FDate AND @TDate
							AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
							AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
							AND (@IsLive = 2 OR IsLive = @IsLive)
					) AS s
				WHERE (c.currency <> 20 OR @IsExcludedTest = 0)
				       AND EXISTS(SELECT 1 FROM #CS_CustSuper cs_ WHERE cs_.CustID = c.srecommend)
				GROUP BY
					s.UplineId
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
			,SUM(s.Wagers)			AS Wagers
			,SUM(s.Stake)			AS Stake
			,SUM(s.ValidStake)		AS ValidStake
			,SUM(s.MemberWinloss)	AS MemberWinloss
			,SUM(s.MemberComm)		AS MemberComm
			,SUM(s.MemberWinloss + s.MemberComm)	AS MemberIncome
			,SUM(s.SuperComm)		AS SuperComm
			,SUM(s.HouseWinloss)	AS HouseWinloss
			,SUM(s.HouseComm)		AS HouseComm
			,SUM(s.HouseTurnover)	AS HouseTurnover
			,SUM(s.HouseWinloss + s.HouseComm)		AS HouseIncome
			,-SUM(s.HouseWinloss + s.HouseComm)		AS HeadlineResult
			,SUM(s.HeadlineStock)	AS HeadlineStock
		FROM #HeadlineWinLoss s
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON s.CustId = c.custid
		GROUP BY
			c.CustId
			,c.Username
	END
	/* ===== End Return Data ===== */

	DROP TABLE #HeadlineWinLoss
	DROP TABLE #tblBetType
	DROP TABLE #tblSportType
END
GO