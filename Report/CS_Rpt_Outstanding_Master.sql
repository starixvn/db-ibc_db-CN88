/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO
 

ALTER PROCEDURE [dbo].[CS_Rpt_Outstanding_Master]
	@CustId				INT = 0,	 
	@IsOwner			BIT = 1,
	@FromDate			SMALLDATETIME,
	@ToDate				SMALLDATETIME,	
	@BalanceUpDay		SMALLDATETIME,
	@MoveBetsDay		SMALLDATETIME,
	@ProductId			SMALLINT = 1,
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

EXEC [CS_Rpt_Outstanding_Master]
	@CustId				= 2,	
	@IsOwner			= 0,
	@FromDate			= '2019-01-01',
	@ToDate				= '2019-03-01',	
	@BalanceUpDay		= '2019-02-03',
	@MoveBetsDay		= '2019-02-10',
	@ProductId			= 1,
	@SporttypeGroup		= 0, -- all
	@Bettype			= 0, -- all
	@IsLive				= 2, -- all
	@ReportType			= 1 
	

*/

BEGIN
	SET NOCOUNT ON;

	
	CREATE TABLE #MasterOutstanding
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
	
	CREATE TABLE #MasterList (MasterId INT)
	
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
	SELECT ProductID, Bettype FROM bodb02.dbo.f_CS_BettypeMatrix_Sel (0, @SporttypeGroup, @BettypeGroup, @isTest)	
	--- End get Bettype 


	--- 3. Get Sporttype

	DECLARE @SporttypeList AS TABLE (Sporttype SMALLINT PRIMARY KEY, ProductID INT)	
		 
	INSERT INTO @SporttypeList
	SELECT DISTINCT Sporttype, ProductID FROM bodb02.dbo.f_CS_SporttypeMatrix_Sel (0, @SporttypeGroup, @BettypeGroup, @isTest)	
	
	--- 4. get Outright by sports	
	DECLARE @OutrightList AS TABLE (MatchID INT)

	IF @BettypeGroup IN (10, 0) --- bettype is Outright or ALL
	BEGIN 
		INSERT INTO @OutrightList (MatchID) 
		SELECT m.orid			
		FROM dbo.Outright m WITH (NOLOCK)
		INNER JOIN dbo.League l WITH (NOLOCK) ON m.LeagueId = l.LeagueId
		WHERE (l.Sporttype IN (SELECT Sporttype FROM @SporttypeList) OR @BettypeGroup = 0 )
			AND m.eventdate BETWEEN @FromDate AND @ToDate			
	END 		 

		 
		
	--- 5. Get report
	DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME;

	SELECT  @FDate = @FromDate, @TDate = @ToDate;

	IF @ToDate >= @BalanceUpDay 
	BEGIN
		IF @ToDate > @MoveBetsDay
		BEGIN
			IF @FromDate <= @MoveBetsDay
			BEGIN
				SET @FDate = DATEADD(DD, 1, @MoveBetsDay);
			END
		
		---- all
			INSERT INTO	#MasterOutstanding (
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
										SuperPoss,
										SuperIncome,
										SuperResult	,
										SuperStock)		
			SELECT
			  					mrecommend,
								'' AS Username,
								'' AS Name,
								COUNT(TransID) AS Wagers,
								SUM(Actual_stake) AS Stake,
								SUM(ABS(winlost - actual_stake)) ValidStake,
								SUM(Winlost - actual_stake + Playercomm) AS MemberIncome,
										
								SUM(Winlost - actual_stake + Playercomm) AS Agent,
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm)) AS AgentResult,  --- Member Income + Agent Income
								
								SUM(MWinlost + AComm - Comm) AS MasterIncome,								
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm) + (MWinlost + AComm - Comm)) AS MasterResult, ---	Master Income + Agent Result 		 
								SUM(ABS(winlost - actual_stake) * (1 - apositiontaking - mpositiontaking)) AS MasterStock,	

								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm) + (MWinlost + AComm - Comm)) AS Super,		  ---	Master Income + Agent Result 
								0 AS SuperPoss,
								SUM(SWinlost + SComm - Acomm) AS SuperIncome,
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm) + (MWinlost + AComm - Comm) + (SWinlost + SComm - Acomm)) AS SuperResult,
								SUM(ABS(winlost - actual_stake) * (1 - tpositiontaking)) AS SuperStock	
			
			FROM	dbo.bettrans b WITH (NOLOCK)							
			WHERE	b.winlostdate BETWEEN @FDate AND @TDate
				AND b.StatusID IN (0,1)
				AND EXISTS (SELECT 1 FROM #MasterList sl WHERE sl.MasterID = b.recommend)	
				AND EXISTS (SELECT 1 FROM @BettypeList bt WHERE bt.Bettype = b.Bettype)	
				AND (
					EXISTS (SELECT 1 FROM dbo.Match m WITH (NOLOCK) WHERE m.MatchID = b.MatchID AND m.sporttype IN (Select Sporttype FROM @SporttypeList))
					OR
					(EXISTS (SELECT 1 FROM @OutrightList r WHERE r.MatchID = b.MatchID) AND (@BettypeGroup IN (10,0))) --- Outright (bettype)
					OR @SporttypeGroup = 10  --- Parlay (sport)
					)
				AND (   @IsLive = 2   --- all
						OR
						(@SporttypeGroup <> 10 AND b.Liveindicator = @IsLive)
						OR 
						(@SporttypeGroup = 10 AND b.livehomescore IN ( SELECT 0 AS IsLive WHERE @IsLive = 0
																UNION 
																SELECT 2 AS IsLive WHERE @IsLive = 0
																UNION 
																SELECT 1 AS IsLive WHERE @IsLive = 1																		
																)
						)
					)		
			GROUP BY mrecommend


			

		--SET @FDate = @FromDate;
		
		--IF @FromDate <= @MoveBetsDay
		--BEGIN
		--	IF @ToDate > @MoveBetsDay
		--	BEGIN
		--		SET @TDate = @MoveBetsDay;
		--	END

	--		INSERT INTO #SAgOutstanding(ProductID, bettype, SportType, liveindicator, GrossComm, Turnover, MAgTotal, SAgOutstanding, SAgComm, NumberOfTickets)
	--		SELECT  s.ProductID,
	--				s.GroupTypeId,
	--				CASE s.ProductID
	--					WHEN 5 THEN m.sporttype
	--					WHEN 22 THEN s.SportType
	--					WHEN 23 THEN s.SportType
	--				END AS SportType,
	--				CASE s.ProductID
	--					WHEN 3 THEN b.liveindicator
	--					ELSE 0
	--				END AS liveindicator,
	--				SUM(CASE
	--					WHEN b.bettype = 1000 THEN oddsspread
	--					WHEN b.bettype BETWEEN 1401 AND 1499 THEN scomm
	--					ELSE CASE WHEN tpositiontaking = 1 THEN 0 ELSE scomm / (1 - tpositiontaking) END END) AS GrossComm,
	--				SUM(CASE WHEN winlostdate >= @ABSDate THEN 
	--							CASE WHEN b.bettype IN (33, 43) AND b.liveawayscore = 0 THEN ABS(stake) / 2
	--								ELSE ABS(stake) END
	--						ELSE 
	--							CASE WHEN b.bettype IN (33, 43) AND b.liveawayscore = 0 THEN stake / 2
	--								ELSE stake END
	--					END) AS Turnover,
	--				SUM(mwinlost + awinlost + acomm + winlost - actual_stake) AS MAgTotal,
	--				SUM(swinlost) AS SAgOutstanding,
	--				ISNULL(SUM(scomm), 0) - ISNULL(SUM(acomm), 0) AS SAgComm,
	--				COUNT(transid) AS NumberOfTickets
	--		FROM dbo.bettrans14 b WITH(NOLOCK)
	--			INNER JOIN #SportBettype s ON (b.bettype = s.Bettype AND (ProductID <> 5 OR EventType <> 3))
	--			LEFT JOIN dbo.match14 m WITH(NOLOCK) ON b.matchid = m.matchid AND s.ProductID = 5
	--		WHERE winlostdate BETWEEN @FDate AND @TDate
	--			AND statusID NOT IN (0, 1, 101, 102, 103)	
	--			AND b.ruben = 1			
	--			AND b.srecommend = @CustID
	--		GROUP BY s.ProductID, s.GroupTypeId,
	--				CASE s.ProductID
	--					WHEN 5 THEN m.sporttype
	--					WHEN 22 THEN s.SportType
	--					WHEN 23 THEN s.SportType
	--				END,
	--				CASE s.ProductID
	--					WHEN 3 THEN b.liveindicator
	--					ELSE 0 END;

		END
	END

	SELECT	c.CustId,
			c.Username,
			c.Username AS Name,
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
			MAX (SuperPoss) AS SuperPoss,
			SUM (SuperIncome) AS SuperIncome,
			SUM (SuperResult) AS SuperResult,
			SUM (SuperStock) AS SuperStock 
	FROM #MasterOutstanding m
		INNER JOIN CustInfo c WITH (NOLOCK) 
			ON c.CustID = m.CustID
	WHERE C.RoleID = 3
	GROUP BY c.CustId,
			c.Username

	SET NOCOUNT OFF;
END
GO