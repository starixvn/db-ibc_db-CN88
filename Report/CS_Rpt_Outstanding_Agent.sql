/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Rpt_Outstanding_Agent]
	@CustId				INT = 0,	 
	@IsOwner			BIT = 1,
	@FromDate			SMALLDATETIME,
	@ToDate				SMALLDATETIME,	
	@ProductId			SMALLINT = 1,
	@SporttypeGroup		SMALLINT = 0, -- all
	@BettypeGroup		SMALLINT = 0, -- all
	@IsLive				TINYINT = 2 
AS
/*
	Created: 20190214@Sophia
	Task: CN88 - Agent report (Master view Agent)
	DB: DBAGE.bodb02	
	Revisions:
		- 20190214@Sophia: Create new [RedmineID: #105660] 
	Param's Explanation:
		- @CustId: MasterID or AgentID  
		- @IsOwner: Upline view Agent or not (if @CustId = AgentId then @IsOwner = 1, if @CustId = MasterId then @IsOwner = 0)
		- @ProductId: default = 1: Sportsbook
		- @BettypeGroup: default = 0: all
		- @SporttypeGroup: default = 0: All
		- @IsLive: default = 2: All
						= 1: Live
						= 0: Dead
		
	Sample:


	EXEC [CS_Rpt_Outstanding_Agent]
	@CustId				= 34109296,	--- master view agent 
	@IsOwner			= 0,
	@FromDate			= '2019-01-01',
	@ToDate				= '2019-03-01',	 
	@ProductId			= 1,
	@SporttypeGroup		= 0, -- all
	@BettypeGroup			= 0, -- all
	@IsLive				= 2  	 

*/

BEGIN
	SET NOCOUNT ON;

	CREATE TABLE #AgentOutstanding
	(
		CustId			INT,
		Username		VARCHAR(50),
		Name			VARCHAR(50),
		Wagers			INT,
		Stake			MONEY, 
		ValidStake		MONEY, 
		MemberIncome	MONEY,
		 
		AgentCurrency	MONEY,					
		Agent			MONEY, 
		AgentIncome		MONEY,
		AgentResult		MONEY,	
		AgentStock		MONEY,
					
		MasterIncome	MONEY,
		MasterResult	MONEY				
		 
	)  	
	
	--- 1. Get AgentList
	
	CREATE TABLE #AgentList (AgentId INT)
	
	IF @IsOwner = 1  --- Agent view Agent
	BEGIN 
		INSERT INTO #AgentList (AgentId)
		VALUES (@CustID)
	END
	ELSE ---- Upline view Agent
	BEGIN 
		INSERT INTO #AgentList (AgentId)
		SELECT  CustID
		FROM	dbo.CustInfo WITH (NOLOCK) 
		WHERE	mrecommend = @CustID
				AND RoleID = 2
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
 
			INSERT INTO	#AgentOutstanding (
										CustId,
										Username,
										Name,
										Wagers,
										Stake,
										ValidStake,
										MemberIncome,

										AgentCurrency,					
										Agent, 
										AgentIncome,
										AgentResult,	
										AgentStock,
					
										MasterIncome,
										MasterResult		
										)		
			SELECT
			  					recommend,
								'' AS Username,
								'' AS Name,
								COUNT(TransID) AS Wagers,
								SUM(Actual_stake) AS Stake,
								0 AS ValidStake,
								SUM(Winlost - actual_stake + Playercomm) AS MemberIncome,

								SUM(Winlost - actual_stake + Playercomm) AS AgentCurrency,										
								SUM(Winlost - actual_stake + Playercomm) AS Agent,
								SUM(AWinlost + Comm - Playercomm) AS AgentIncome,	
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm)) AS AgentResult,  --- Member Income + Agent Income
								SUM(CASE WHEN StatusId IN (112, 113) THEN ABS(winlost - actual_stake) ELSE 0 END * (1 - apositiontaking)) AS AgentStock,
								
								SUM(MWinlost + AComm - Comm) AS MasterIncome,								
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm) + (MWinlost + AComm - Comm)) AS MasterResult

			FROM	dbo.bettrans b WITH (NOLOCK)							
			WHERE	b.winlostdate BETWEEN @FDate AND @TDate
				AND b.StatusID IN (0,1)
				AND EXISTS (SELECT 1 FROM #AgentList sl WHERE sl.AgentID = b.recommend)	
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
			GROUP BY recommend

	
	SELECT	c.CustId,
			c.Username,
			c.Username AS Name,
			SUM (Wagers) AS Wagers,
			SUM (Stake) AS Stake,
			SUM (ValidStake) AS ValidStake,
			SUM (MemberIncome) AS MemberIncome,

			SUM (AgentCurrency) AS AgentCurrency,										
			SUM (Agent) AS Agent,
			SUM (AgentIncome) AS AgentIncome,
			SUM (AgentResult) AS AgentResult,
			SUM (AgentStock) AS MasterStock,
				
			SUM (MasterIncome) AS MasterIncome,
			SUM (MasterResult) AS MasterResult
	FROM #AgentOutstanding m
		INNER JOIN CustInfo c WITH (NOLOCK) 
			ON c.CustID = m.CustID
	WHERE C.RoleID = 2
	GROUP BY c.CustId,
			c.Username

	SET NOCOUNT OFF
END
GO
