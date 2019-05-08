/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Rpt_Winloss_Super]
	@CustId				INT = 0,
	@IsOwner			BIT = 1, 
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
	Task: CN88 - Supers report by ID 
	DB: DBAGE.bodb02	
	Revisions:
		- 20190214@Sophia: Create new [RedmineID: #105660] 
		- 20190329@Sophia: Implement Non Sports [Redmine: #109521]
		
	Param's Explanation:
		- @CustId: SuperID or HeadlineID
		- @IsOwner: Is Super view super or not (if @CustId = SuperID then @IsOwner = 1, if @CustId = HeadlineID then @IsOwner = 0)
		- @ProductId: default = 1: Sportsbook
		- @Bettype: default = 0: all
		- @SporttypeGroup: default = 0: All
		- @BettypeGroup: default = 0: All
		- @IsLive: default = 2: All
						= 1: Live
						= 0: Dead
						
						
		EXEC [CS_Rpt_Winloss_Super] 
			@CustId				= 2,
			@IsOwner			= 1, 
			@FromDate			= '2019-01-01',
			@ToDate				= '2019-03-01',	
			@ArchiveDate		= '2019-02-03',
			@MoveBetsDay		= '2019-02-08',
			@ProductId			= 1,
			@SporttypeGroup		= 0, -- all
			@BettypeGroup		= 10, -- all
			@IsLive				= 0 -- all
			

*/

BEGIN
	SET NOCOUNT ON;

	CREATE TABLE #SuperWinLoss
	(
		CustId			INT,
		Username		VARCHAR(50),
		Name			VARCHAR(50),
		Wagers			INT,
		Stake			MONEY, 
		ValidStake		MONEY, 
		MemberIncome	MONEY, 
				
		Agent			MONEY, 
		AgentResult		MONEY,		
		Master			MONEY,
				
		Super			MONEY,
		SuperIncome		MONEY,
		SuperResult		MONEY,
		SuperStock		MONEY,
		
		HeadlinePoss		MONEY,
		HeadlineIncome		MONEY,
		HeadlineResult		MONEY,
		HeadlineStock		MONEY
		
	) 
	
	
	--- 1. Get Superlist
	
	CREATE TABLE #SuperList (SuperID INT PRIMARY KEY)
	
	IF @IsOwner = 1  --- Super view super
	BEGIN 
		INSERT INTO #SuperList (SuperID)
		VALUES (@CustID)
	END
	ELSE ---- Headline view Supers 
	BEGIN 
		INSERT INTO #SuperList (SuperID)
		SELECT  CustID
		FROM	dbo.CustSuper WITH (NOLOCK) 
		WHERE	UplineID = @CustID
	END

	--- 2. Get Bettype
	------ Check SP Version
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	------ Get Bettype Matrix------	
	DECLARE @BettypeList TABLE (ProductID INT, Bettype SMALLINT, EventType TINYINT)
	INSERT INTO @BettypeList
	SELECT DISTINCT ProductID, Bettype, EventType FROM dbo.CS_f_BettypeMatrix_Sel (0, @SporttypeGroup, @BettypeGroup, @isTest)	

	--- 3. Get Sporttype
	DECLARE @SporttypeList TABLE (Sporttype SMALLINT PRIMARY KEY, ProductID INT)	
	INSERT INTO @SporttypeList
	SELECT DISTINCT Sporttype, ProductID FROM dbo.CS_f_SporttypeMatrix_Sel (0, @SporttypeGroup, @BettypeGroup, @isTest)	
	
	--- 4. get Outright by sports	
	DECLARE @OutrightList TABLE (MatchID INT)

	IF @BettypeGroup IN (10, 0) --- bettype is Outright or ALL
	BEGIN 
		INSERT INTO @OutrightList (MatchID) 
		SELECT m.orid			
		FROM dbo.Outright m WITH (NOLOCK)
		INNER JOIN dbo.League l WITH (NOLOCK) ON m.LeagueId = l.LeagueId
		WHERE l.Sporttype IN (SELECT Sporttype FROM @SporttypeList) 
			AND m.eventdate BETWEEN @FromDate AND @ToDate			
	END 		 

	--- 5. get VSOutright by sports	
	DECLARE @VSOutrightList TABLE (MatchID INT)
	
	IF @SporttypeGroup IN (13, 0)
	BEGIN 
		INSERT INTO @VSOutrightList (MatchID) 
		SELECT r.EventID
		FROM dbo.VSRaceInfo r WITH (NOLOCK)
		WHERE r.Sporttype IN (SELECT Sporttype FROM @SporttypeList)
			AND EXISTS (
				SELECT 1 FROM dbo.VSOutright o WITH (NOLOCK)
				WHERE o.EventID = r.EventID
					AND o.eventdate BETWEEN @FromDate AND @ToDate	
			)
	END
	
		
	----5. Get Tier 0 Poss
	IF @IsOwner = 0
	BEGIN 
		DECLARE @ExtraPT TABLE (SuperID INT, ExtraPT DECIMAL(9,8), FromDate DATETIME, ToDate DATETIME, ProductID TINYINT)----, Sporttype SMALLINT, SubProduct VARCHAR (50) )

		INSERT INTO @ExtraPT (SuperID, ExtraPT, FromDate, ToDate, ProductID)---, Sporttype, SubProduct)
		SELECT DISTINCT e.SuperID, e.ExtraPT, e.FromDate, e.ToDate, e.ProductId----, Sporttype, SubProduct 
		FROM  dbo.Acc_GroupExtraPTSetting e WITH (NOLOCK) 
			INNER JOIN @BettypeList b 
				ON b.ProductID = e.ProductId 		
		WHERE e.SuperID IN (SELECT SuperID FROM #SuperList)
			  AND e.Sporttype = 0		--- General Sporttype of SB & other products
			  AND e.SubProduct = '' 	--- General SubProduct of SB & other products 
			  AND (@FromDate BETWEEN e.FromDate AND e.ToDate
					OR @ToDate BETWEEN e.FromDate AND e.ToDate )

	END
	
	
	--- 5. Get report
	------5.1. bettrans range
	DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME;

	SELECT  @FDate = @FromDate, @TDate = @ToDate

	IF @ToDate > @MoveBetsDay
	BEGIN
		IF @FromDate <= @MoveBetsDay
		BEGIN
			SET @FDate = DATEADD(DD, 1, @MoveBetsDay);
		END
		 
		INSERT INTO	#SuperWinLoss (
							CustId,
							Username,
							Name,
							Wagers,
							Stake,
							ValidStake,
							MemberIncome,
										
							Agent,
							AgentResult,	
							Master,
										
							Super,
							SuperIncome,
							SuperResult,
							SuperStock, 
								
							HeadlineIncome,
							HeadlineResult,
							HeadlineStock )		
		SELECT
			  				srecommend,
							'' AS Username,
							'' AS Name,
							COUNT(TransID) AS Wagers,
							SUM(Stake) AS Stake,
							SUM(ABS(winlost - actual_stake)) ValidStake,
							SUM(Winlost - actual_stake + Playercomm) AS MemberIncome,
										
							SUM((Winlost - actual_stake)  + (ABS(winlost - actual_stake) * discount) ) AS Agent,
							SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm)) AS AgentResult,  --- Member Income + Agent Income
							SUM(((Winlost - actual_stake) * (1-apositiontaking)) + ABS(winlost - actual_stake) * (1 - apositiontaking) * adiscount) AS Master,
									 
							SUM( (Winlost - actual_stake)* (1 - apositiontaking - mpositiontaking) 
									+  ABS(winlost - actual_stake) * (1 - apositiontaking - mpositiontaking) * sdiscount
									) AS Super,
								
							SUM(SWinlost + SComm - Acomm) AS SuperIncome,
							SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm) + (MWinlost + AComm - Comm) + (SWinlost + SComm - Acomm)) AS SuperResult,
							SUM(ABS(winlost - actual_stake) * (1 - tpositiontaking)) AS SuperStock,		
								
							SUM (-1 *(CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.winlost - b.actual_stake + b.scomm / (1 - b.tpositiontaking) END) * e.ExtraPT) AS HeadlineIncome,  --- MSH Win Loss + MSH Sharing Comm 
							SUM ( 								
									( -1 * (CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.winlost - b.actual_stake + b.scomm / (1 - b.tpositiontaking) END) * e.ExtraPT)
									+ ((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm) + (MWinlost + AComm - Comm) + (SWinlost + SComm - Acomm)) 
								) AS HeadlineResult,
							SUM (ABS(winlost - actual_stake) * (1 - tpositiontaking - e.ExtraPT)) AS HeadlineStock		
										
		FROM	dbo.bettrans b WITH (NOLOCK)		
			INNER JOIN @BettypeList bt
				ON	bt.Bettype = b.bettype
			LEFT JOIN @ExtraPT e 
				ON	b.Srecommend = e.SuperID 
					AND b.winlostdate BETWEEN e.FromDate AND E.ToDate
					AND bt.ProductID = e.ProductID
		WHERE	b.winlostdate BETWEEN @FDate AND @TDate
			AND b.StatusID IN (111,112,113)
			AND EXISTS (SELECT 1 FROM #SuperList sl WHERE sl.SuperID = b.srecommend)		
			AND (
					bt.EventType = 0  --- bettrans only
					OR EXISTS (SELECT 1 FROM dbo.Match m WITH (NOLOCK) WHERE m.MatchID = b.MatchID AND bt.EventType = 1)
					OR EXISTS (SELECT 1 FROM @OutrightList r WHERE r.MatchID = b.MatchID AND bt.EventType = 2)
					OR EXISTS (SELECT 1 FROM @VSOutrightList r WHERE r.MatchID = b.MatchID AND bt.EventType = 3)
				)
			AND (   @IsLive = 2   --- all
					OR
					(b.bettype <> 29 AND b.Liveindicator = @IsLive)
					OR 
					(b.bettype = 29  AND b.livehomescore IN ( SELECT 0 AS IsLive WHERE @IsLive = 0
															UNION 
															SELECT 2 AS IsLive WHERE @IsLive = 0
															UNION 
															SELECT 1 AS IsLive WHERE @IsLive = 1																		
															)
					)
				)
			AND b.Bettype <> 2799 -- exclude VS mix Parlay
		GROUP BY srecommend
		
		
		
		-- Mix parlay of BRVS
		IF (@BettypeGroup IN (2799,0) OR @SporttypeGroup IN(13,0) AND @IsLive IN (0,2))
		BEGIN 
			INSERT INTO	#SuperWinLoss (
								CustId,
								Username,
								Name,
								Wagers,
								Stake,
								ValidStake,
								MemberIncome,
											
								Agent,
								AgentResult,	
								Master,
											
								Super,
								SuperIncome,
								SuperResult,
								SuperStock, 
									
								HeadlineIncome,
								HeadlineResult,
								HeadlineStock )		
			SELECT
								srecommend,
								'' AS Username,
								'' AS Name,
								COUNT(TransID) AS Wagers,
								SUM(Stake) AS Stake,
								SUM(ABS(winlost - actual_stake)) ValidStake,
								SUM(Winlost - actual_stake + Playercomm) AS MemberIncome,
											
								SUM((Winlost - actual_stake)  + (ABS(winlost - actual_stake) * discount) ) AS Agent,
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm)) AS AgentResult,  --- Member Income + Agent Income
								SUM(((Winlost - actual_stake) * (1-apositiontaking)) + ABS(winlost - actual_stake) * (1 - apositiontaking) * adiscount) AS Master,
										 
								SUM( (Winlost - actual_stake)* (1 - apositiontaking - mpositiontaking) 
										+  ABS(winlost - actual_stake) * (1 - apositiontaking - mpositiontaking) * sdiscount
										) AS Super,
									
								SUM(SWinlost + SComm - Acomm) AS SuperIncome,
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm) + (MWinlost + AComm - Comm) + (SWinlost + SComm - Acomm)) AS SuperResult,
								SUM(ABS(winlost - actual_stake) * (1 - tpositiontaking)) AS SuperStock,		
									
								SUM (-1 *(CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.winlost - b.actual_stake + b.scomm / (1 - b.tpositiontaking) END) * e.ExtraPT) AS HeadlineIncome,  --- MSH Win Loss + MSH Sharing Comm 
								SUM ( 								
										( -1 * (CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.winlost - b.actual_stake + b.scomm / (1 - b.tpositiontaking) END) * e.ExtraPT)
										+ ((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm) + (MWinlost + AComm - Comm) + (SWinlost + SComm - Acomm)) 
									) AS HeadlineResult,
								SUM (ABS(winlost - actual_stake) * (1 - tpositiontaking - e.ExtraPT)) AS HeadlineStock	
											
			FROM dbo.bettrans b WITH (NOLOCK)
			INNER JOIN @BettypeList bt
					ON	bt.Bettype = b.bettype
			LEFT JOIN @ExtraPT e 
				ON	b.Srecommend = e.SuperID 
					AND b.winlostdate BETWEEN e.FromDate AND E.ToDate
					AND bt.ProductID = e.ProductID					
			CROSS APPLY (
				SELECT TOP 1 m.sporttype
				FROM dbo.bettransm bm WITH (NOLOCK)
					INNER JOIN dbo.match m WITH (NOLOCK) ON bm.matchid = m.matchid				
				WHERE bm.refno = b.refno
					  AND m.sporttype IN (Select Sporttype FROM @SporttypeList)
				) AS s
			WHERE b.matchid = 2799 AND b.bettype = 2799
				AND b.winlostdate BETWEEN @FDate AND @TDate
				AND b.StatusID IN (111,112,113)
				AND EXISTS (SELECT 1 FROM #SuperList sl WHERE sl.SuperID = b.srecommend)
			GROUP BY srecommend
		END	
	END
 

		-- 5.2: sum table range
		SELECT @FDate = @FromDate,
			   @TDate = @ToDate
		
		IF @FromDate <= @MoveBetsDay
		BEGIN
		
			IF @FromDate < @ArchiveDate 
			BEGIN
				SET @FDate = @ArchiveDate;
			END			 
		
			IF @ToDate > @MoveBetsDay
			BEGIN
				SET @TDate = @MoveBetsDay;
			END

			INSERT INTO	#SuperWinLoss (
								CustId,
								Username,
								Name,
								Wagers,
								Stake,
								ValidStake,
								MemberIncome,
										
								Agent,
								AgentResult,	
								Master,
										
								Super,
								SuperIncome,
								SuperResult,
								SuperStock, 
								
								HeadlineIncome,
								HeadlineResult,
								HeadlineStock )		
			SELECT
			  					CustId,
								'' AS Username,
								'' AS Name,
								SUM(Wagers) AS Wagers,
								SUM(Stake) AS Stake,
								SUM(ValidStake) ValidStake,
								SUM(MemberWinloss + MemberComm) AS MemberIncome,
										
								SUM(Agent) AS Agent,
								SUM((MemberWinloss + MemberComm) + (AgentWinloss + AgentComm)) AS AgentResult,  --- Member Income + Agent Income
								SUM(Master) AS Master,
									 
								SUM(Super) AS Super,		 
								
								SUM(SuperWinloss + SuperComm) AS SuperIncome,
								SUM((MemberWinloss +MemberComm) + (AgentWinloss + AgentComm) + (MasterWinloss + MasterComm) + (SuperWinloss + SuperComm)) AS SuperResult,
								SUM(SuperStock) AS SuperStock,		
								
								SUM (HeadlineWinloss + HeadlineComm) AS HeadlineIncome,  --- MSH Win Loss + MSH Sharing Comm 
								SUM (	(HeadlineWinloss + HeadlineComm)
										+(MemberWinloss +MemberComm) 
										+ (AgentWinloss + AgentComm) 
										+ (MasterWinloss + MasterComm) 
										+ (SuperWinloss + SuperComm)
									) AS HeadlineResult,
								SUM (HeadlineStock) AS HeadlineStock	
										
			FROM	bodb_Summary.dbo.CS_SumWinloss b WITH (NOLOCK)						
			WHERE	b.winlostdate BETWEEN @FDate AND @TDate		
				AND (@isLive = 2 OR isLive = @isLive)	
				AND EXISTS (SELECT 1 FROM #SuperList sl WHERE sl.SuperID = b.CustID)					 
				AND EXISTS (SELECT 1 FROM @BettypeList bt WHERE bt.bettype = b.bettype)
				AND EXISTS (SELECT 1 FROM @SporttypeList st WHERE st.Sporttype = b.Sporttype)
			GROUP BY CustId
		 	
			
			---5.3: range archive table 
			SELECT	@FDate = @FromDate,
					@TDate = @ToDate;

			IF @FromDate < @ArchiveDate 
			BEGIN
				IF @ToDate >= DATEADD(dd, -1, @ArchiveDate)
				BEGIN
					SELECT @TDate = DATEADD(dd, -1, @ArchiveDate);
				END
			
				INSERT INTO	#SuperWinLoss (
									CustId,
									Username,
									Name,
									Wagers,
									Stake,
									ValidStake,
									MemberIncome,
											
									Agent,
									AgentResult,	
									Master,
											
									Super,
									SuperIncome,
									SuperResult,
									SuperStock, 
									
									HeadlineIncome,
									HeadlineResult,
									HeadlineStock )		
				SELECT
									CustId,
									'' AS Username,
									'' AS Name,
									SUM(Wagers) AS Wagers,
									SUM(Stake) AS Stake,
									SUM(ValidStake) ValidStake,
									SUM(MemberWinloss + MemberComm) AS MemberIncome,
											
									SUM(Agent) AS Agent,
									SUM((MemberWinloss + MemberComm) + (AgentWinloss + AgentComm)) AS AgentResult,  --- Member Income + Agent Income
									SUM(Master) AS Master,
										 
									SUM(Super) AS Super,		 
									
									SUM(SuperWinloss + SuperComm) AS SuperIncome,
									SUM((MemberWinloss +MemberComm) + (AgentWinloss + AgentComm) + (MasterWinloss + MasterComm) + (SuperWinloss + SuperComm)) AS SuperResult,
									SUM(SuperStock) AS SuperStock,		
									
									SUM (HeadlineWinloss + HeadlineComm) AS HeadlineIncome,  --- MSH Win Loss + MSH Sharing Comm 
									SUM (	(HeadlineWinloss + HeadlineComm)
											+(MemberWinloss +MemberComm) 
											+ (AgentWinloss + AgentComm) 
											+ (MasterWinloss + MasterComm) 
											+ (SuperWinloss + SuperComm)
										) AS HeadlineResult,
									SUM (HeadlineStock) AS HeadlineStock	
											
				FROM	bodb_Summary.dbo.CS_SumWinloss_Old b WITH (NOLOCK)						
				WHERE	b.winlostdate BETWEEN @FDate AND @TDate		
					AND (@isLive = 2 OR isLive = @isLive)	
					AND EXISTS (SELECT 1 FROM #SuperList sl WHERE sl.SuperID = b.CustID)					 
					AND EXISTS (SELECT 1 FROM @BettypeList bt WHERE bt.bettype = b.bettype)
					AND EXISTS (SELECT 1 FROM @SporttypeList st WHERE st.Sporttype = b.Sporttype)
				GROUP BY CustId
			
			END		
	 
		END		
		 
	

	SELECT	c.CustId,
			c.Username, 
			c.FirstName AS Name,
			SUM (Wagers) AS Wagers,
			SUM (Stake) AS Stake,
			SUM (ValidStake) AS ValidStake,
			SUM (MemberIncome) AS MemberIncome,
										
			SUM (Agent) AS Agent,
			SUM (AgentResult) AS AgentResult,	
			SUM (Master) AS Master,
													
			SUM (Super) AS Super,
			SUM (SuperIncome) AS SuperIncome,
			SUM (SuperResult) AS SuperResult,
			SUM (SuperStock) AS SuperStock, 
								
			SUM (HeadlineIncome) AS HeadlineIncome,
			SUM (HeadlineResult) AS HeadlineResult,
			SUM (HeadlineStock) AS HeadlineStock
	FROM #SuperWinLoss s
	INNER JOIN Customer c WITH (NOLOCK) 
		ON c.CustID = s.CustID
	WHERE C.RoleID = 4
	GROUP BY c.CustId, c.Username, c.FirstName
	
	SET NOCOUNT OFF

END
GO
 