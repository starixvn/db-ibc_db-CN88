/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Rpt_Winloss_Master]
	@CustId				INT = 0,	 
	@IsOwner			BIT = 1,
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
	Task: CN88 - Master report (super view master)
	DB: DBAGE.bodb02	
	Revisions:
		- 20190214@Sophia: Create new [RedmineID: #105660] 
		- 20190329@Sophia: Implement Non Sports [Redmine: #109521]
		
	Param's Explanation:
		- @CustId: SuperID or MasterID
		- @IsOwner: Is Master view Master or not (if @CustId = MasterID then @IsOwner = 1, if @CustId = SuperID then @IsOwner = 0)
		- @ProductId: default = 1: Sportsbook
		- @BettypeGroup: default = 0: all
		- @SporttypeGroup: default = 0: All
		- @IsLive: default = 2: All
						= 1: Live
						= 0: Dead 
	Sample:

EXEC [CS_Rpt_Winloss_Master]
	@CustId				= 2,	
	@IsOwner			= 0,
	@FromDate			= '2019-01-01',
	@ToDate				= '2019-03-01',	
	@ArchiveDate		= '2019-02-03',
	@MoveBetsDay		= '2019-02-10',
	@ProductId			= 1,
	@SporttypeGroup		= 0, -- all
	@Bettype			= 0, -- all
	@IsLive				= 2  
	

*/

BEGIN
	SET NOCOUNT ON;

	
	CREATE TABLE #MasterWinLoss
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
					
		MasterIncome	MONEY,
		MasterResult	MONEY,				
		MasterStock		MONEY,

		Super			MONEY,		
		SuperPoss		MONEY,
		SuperIncome		MONEY,
		SuperResult		MONEY,
		SuperStock		MONEY		
	) 
	
	
	--- 1. Get MasterList
	
	CREATE TABLE #MasterList (MasterId INT PRIMARY KEY)
	
	IF @IsOwner = 1  --- Master view Master
	BEGIN 
		INSERT INTO #MasterList (MasterId)
		VALUES (@CustID)
	END
	ELSE ---- Upline view Master
	BEGIN 
		INSERT INTO #MasterList (MasterId)
		SELECT  CustID
		FROM	dbo.CustInfo WITH (NOLOCK) 
		WHERE	srecommend = @CustID
				AND RoleID = 3
	END
	
	
	--- 2. Get Bettype
	------ Check SP Version
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	------ Get Bettype Matrix------	
	DECLARE @BettypeList TABLE (ProductID INT, Bettype SMALLINT)
	INSERT INTO @BettypeList
	SELECT ProductID, Bettype FROM bodb02.dbo.CS_f_BettypeMatrix_Sel (0, @SporttypeGroup, @BettypeGroup, @isTest)	
	--- End get Bettype 


	--- 3. Get Sporttype

	DECLARE @SporttypeList AS TABLE (Sporttype SMALLINT PRIMARY KEY, ProductID INT)	
		 
	INSERT INTO @SporttypeList
	SELECT DISTINCT Sporttype, ProductID FROM bodb02.dbo.CS_f_SporttypeMatrix_Sel (0, @SporttypeGroup, @BettypeGroup, @isTest)	
	
	--- 4. get Outright by sports	
	DECLARE @OutrightList AS TABLE (MatchID INT)

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
	DECLARE @VSOutrightList AS TABLE (MatchID INT)
	
	IF @SporttypeGroup IN (13, 0) 
	BEGIN 
		INSERT INTO @VSOutrightList (MatchID) 
		SELECT o.EventID 		
		FROM dbo.VSOutright o WITH (NOLOCK)
		INNER JOIN dbo.VSRaceInfo r WITH(NOLOCK) ON o.EventID = r.EventID		
		WHERE r.Sporttype IN (SELECT Sporttype FROM @SporttypeList)
			AND o.eventdate BETWEEN @FromDate AND @ToDate		
					
	END 	 
		
	--- 5. Get report
	---5.1 bettrans range
	DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME;

	SELECT  @FDate = @FromDate, @TDate = @ToDate;
	
	IF @ToDate > @MoveBetsDay
		BEGIN
			IF @FromDate <= @MoveBetsDay
			BEGIN
				SET @FDate = DATEADD(DD, 1, @MoveBetsDay);
			END
		
		 
			INSERT INTO	#MasterWinLoss (
										CustId,
										Username,
										Name,
										Wagers,
										Stake,
										ValidStake,
										MemberIncome,
				
										Agent,
										AgentResult,
			
										MasterIncome,
										MasterResult,
										MasterStock,

										Super,	 
										SuperIncome,
										SuperResult	,
										SuperStock)		
			SELECT
			  					mrecommend,
								'' AS Username,
								'' AS Name,
								COUNT(TransID) AS Wagers,
								SUM(Stake) AS Stake,
								SUM(ABS(winlost - actual_stake)) ValidStake,
								SUM(Winlost - actual_stake + Playercomm) AS MemberIncome,
										
								SUM((Winlost - actual_stake)  + (ABS(winlost - actual_stake) * discount) ) AS Agent,
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm)) AS AgentResult,  --- Member Income + Agent Income
								
								SUM(MWinlost + AComm - Comm) AS MasterIncome,								
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm) + (MWinlost + AComm - Comm)) AS MasterResult, ---	Master Income + Agent Result 		 
								SUM(ABS(winlost - actual_stake) * (1 - apositiontaking - mpositiontaking)) AS MasterStock,	

								SUM( (Winlost - actual_stake)* (1 - apositiontaking - mpositiontaking) 
									 +  ABS(winlost - actual_stake) * (1 - apositiontaking - mpositiontaking) * sdiscount
									 ) AS Super,		 
								 
								SUM(SWinlost + SComm - Acomm) AS SuperIncome,
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm) + (MWinlost + AComm - Comm) + (SWinlost + SComm - Acomm)) AS SuperResult,
								SUM(ABS(winlost - actual_stake) * (1 - tpositiontaking)) AS SuperStock	
			
			FROM	dbo.bettrans b WITH (NOLOCK)							
			WHERE	b.winlostdate BETWEEN @FDate AND @TDate
				AND b.StatusID IN (111,112,113)
				AND EXISTS (SELECT 1 FROM #MasterList sl WHERE sl.MasterID = b.mrecommend)	
				AND EXISTS (SELECT 1 FROM @BettypeList bt WHERE bt.Bettype = b.Bettype)	
				AND (
					EXISTS (SELECT 1 FROM dbo.Match m WITH (NOLOCK) WHERE m.MatchID = b.MatchID AND m.sporttype IN (Select Sporttype FROM @SporttypeList))
					OR
					(EXISTS (SELECT 1 FROM @OutrightList r WHERE r.MatchID = b.MatchID) AND (@BettypeGroup IN (10,0))) --- Outright (bettype)
					OR
					(EXISTS (SELECT 1 FROM @VSOutrightList r WHERE r.MatchID = b.MatchID) AND (@SporttypeGroup IN (13, 0)) ) --- VS
					OR @SporttypeGroup IN(0,9)  --- Parlay (sport)
					)
				AND (   @IsLive = 2   --- all
						OR
						(b.bettype <> 29 AND b.Liveindicator = @IsLive)
						OR 
						(b.bettype = 29 AND b.livehomescore IN ( SELECT 0 AS IsLive WHERE @IsLive = 0
																UNION 
																SELECT 2 AS IsLive WHERE @IsLive = 0
																UNION 
																SELECT 1 AS IsLive WHERE @IsLive = 1																		
																)
						)
					)
			AND b.Bettype <> 2799 -- exclude VS mix Parlay					
			GROUP BY mrecommend		
			
		-- Mix parlay of BRVS
		IF (@BettypeGroup IN (2799,0) OR @SporttypeGroup IN(13,0) AND @IsLive IN (0,2))
		BEGIN 
			INSERT INTO	#MasterWinLoss (
										CustId,
										Username,
										Name,
										Wagers,
										Stake,
										ValidStake,
										MemberIncome,
				
										Agent,
										AgentResult,
			
										MasterIncome,
										MasterResult,
										MasterStock,

										Super,	 
										SuperIncome,
										SuperResult	,
										SuperStock)		
			SELECT
			  					mrecommend,
								'' AS Username,
								'' AS Name,
								COUNT(TransID) AS Wagers,
								SUM(Stake) AS Stake,
								SUM(ABS(winlost - actual_stake)) ValidStake,
								SUM(Winlost - actual_stake + Playercomm) AS MemberIncome,
										
								SUM((Winlost - actual_stake)  + (ABS(winlost - actual_stake) * discount) ) AS Agent,
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm)) AS AgentResult,  --- Member Income + Agent Income
								
								SUM(MWinlost + AComm - Comm) AS MasterIncome,								
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm) + (MWinlost + AComm - Comm)) AS MasterResult, ---	Master Income + Agent Result 		 
								SUM(ABS(winlost - actual_stake) * (1 - apositiontaking - mpositiontaking)) AS MasterStock,	

								SUM( (Winlost - actual_stake)* (1 - apositiontaking - mpositiontaking) 
									 +  ABS(winlost - actual_stake) * (1 - apositiontaking - mpositiontaking) * sdiscount
									 ) AS Super,		 
								 
								SUM(SWinlost + SComm - Acomm) AS SuperIncome,
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm) + (MWinlost + AComm - Comm) + (SWinlost + SComm - Acomm)) AS SuperResult,
								SUM(ABS(winlost - actual_stake) * (1 - tpositiontaking)) AS SuperStock	
			FROM dbo.bettrans b WITH (NOLOCK)		
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
				AND EXISTS (SELECT 1 FROM #MasterList sl WHERE sl.MasterID = b.mrecommend)
			GROUP BY mrecommend
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

			INSERT INTO	#MasterWinLoss (
										CustId,
										Username,
										Name,
										Wagers,
										Stake,
										ValidStake,
										MemberIncome,
				
										Agent,
										AgentResult,
			
										MasterIncome,
										MasterResult,
										MasterStock,

										Super,	 
										SuperIncome,
										SuperResult	,
										SuperStock)	
			SELECT
								CustID,
								'' AS Username,
								'' AS Name,
								SUM(Wagers) AS Wagers,
								SUM(Stake) AS Stake,
								SUM(ValidStake) ValidStake,
								SUM(MemberWinloss + MemberComm) AS MemberIncome,
										
								SUM(Agent) AS Agent,
								SUM((MemberWinloss +MemberComm) + (AgentWinloss + AgentComm)) AS AgentResult,  --- Member Income + Agent Income
							
								SUM(MasterWinloss + MasterComm) AS MasterIncome,
								SUM((MemberWinloss +MemberComm) + (AgentWinloss + AgentComm) + (MasterWinloss + MasterComm)) AS MasterResult, 									 
								SUM(MasterStock) AS MasterStock,		 
								
								SUM(Super) AS Super,								
								SUM(SuperWinloss + SuperComm) AS SuperIncome,
								SUM((MemberWinloss +MemberComm) + (AgentWinloss + AgentComm) + (MasterWinloss + MasterComm) + (SuperWinloss + SuperComm)) AS SuperResult,
								SUM(SuperStock) AS SuperStock									
										
			FROM	bodb_Summary.dbo.CS_SumWinloss b WITH (NOLOCK)						
			WHERE	b.winlostdate BETWEEN @FDate AND @TDate	
				AND (@isLive = 2 OR isLive = @isLive)	
				AND EXISTS (SELECT 1 FROM #MasterList sl WHERE sl.MasterID = b.CustID)						
				AND EXISTS (SELECT 1 FROM @BettypeList bt WHERE bt.bettype = b.bettype)
				AND EXISTS (SELECT 1 FROM @SporttypeList st WHERE st.Sporttype = b.Sporttype)
			GROUP BY CustID
				
			---5.3: range archive table 
			SELECT	@FDate = @FromDate,
					@TDate = @ToDate;

			IF @FromDate < @ArchiveDate 
			BEGIN
				IF @ToDate >= DATEADD(dd, -1, @ArchiveDate)
				BEGIN
					SELECT @TDate = DATEADD(dd, -1, @ArchiveDate);
				END
			
				INSERT INTO	#MasterWinLoss (
											CustId,
											Username,
											Name,
											Wagers,
											Stake,
											ValidStake,
											MemberIncome,
					
											Agent,
											AgentResult,
				
											MasterIncome,
											MasterResult,
											MasterStock,

											Super,	 
											SuperIncome,
											SuperResult	,
											SuperStock)	
				SELECT
									CustID,
									'' AS Username,
									'' AS Name,
									SUM(Wagers) AS Wagers,
									SUM(Stake) AS Stake,
									SUM(ValidStake) ValidStake,
									SUM(MemberWinloss + MemberComm) AS MemberIncome,
											
									SUM(Agent) AS Agent,
									SUM((MemberWinloss +MemberComm) + (AgentWinloss + AgentComm)) AS AgentResult,  --- Member Income + Agent Income
								
									SUM(MasterWinloss + MasterComm) AS MasterIncome,
									SUM((MemberWinloss +MemberComm) + (AgentWinloss + AgentComm) + (MasterWinloss + MasterComm)) AS MasterResult, 									 
									SUM(MasterStock) AS MasterStock,		 
									
									SUM(Super) AS Super,								
									SUM(SuperWinloss + SuperComm) AS SuperIncome,
									SUM((MemberWinloss +MemberComm) + (AgentWinloss + AgentComm) + (MasterWinloss + MasterComm) + (SuperWinloss + SuperComm)) AS SuperResult,
									SUM(SuperStock) AS SuperStock									
											
				FROM	bodb_Summary.dbo.CS_SumWinloss_Old b WITH (NOLOCK)						
				WHERE	b.winlostdate BETWEEN @FDate AND @TDate		
					AND (@isLive = 2 OR isLive = @isLive)					
					AND EXISTS (SELECT 1 FROM #MasterList sl WHERE sl.MasterID = b.CustID)						
					AND EXISTS (SELECT 1 FROM @BettypeList bt WHERE bt.bettype = b.bettype)
					AND EXISTS (SELECT 1 FROM @SporttypeList st WHERE st.Sporttype = b.Sporttype)
				GROUP BY CustID
			
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
			SUM (MasterIncome) AS MasterIncome,
			SUM (MasterResult) AS MasterResult,
			SUM (MasterStock) AS MasterStock,
										
			SUM (Super) AS Super, 
			SUM (SuperIncome) AS SuperIncome,
			SUM (SuperResult) AS SuperResult,
			SUM (SuperStock) AS SuperStock 
	FROM #MasterWinLoss m
		INNER JOIN Customer c WITH (NOLOCK) 
			ON c.CustID = m.CustID
	WHERE C.RoleID = 3
	GROUP BY c.CustId,
			c.Username,
			c.FirstName

	SET NOCOUNT OFF;
END
GO