/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO
 

ALTER PROCEDURE [dbo].[CS_Rpt_Outstanding_Master]
	@CustId				INT = 0,	 
	@IsOwner			BIT = 1,
	@FromDate			SMALLDATETIME,
	@ToDate				SMALLDATETIME,	
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
	@CustId				= 34109296,	-- master view master
	@IsOwner			= 1,
	@FromDate			= '2019-01-01',
	@ToDate				= '2019-03-01',	 
	@ProductId			= 1,
	@SporttypeGroup		= 0, -- all
	@BettypeGroup			= 0, -- all
	@IsLive				= 2

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
		WHERE (l.Sporttype IN (SELECT Sporttype FROM @SporttypeList) OR @BettypeGroup = 0 )
			AND m.eventdate BETWEEN @FromDate AND @ToDate			
	END 		 

		 
		
	--- 5. Get report
	DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME;

	SELECT  @FDate = @FromDate, @TDate = @ToDate;

			INSERT INTO	#MasterOutstanding (
										CustId,
										Username,
										Name,
										Wagers,
										Stake )		
			SELECT
			  					mrecommend,
								'' AS Username,
								'' AS Name,
								COUNT(TransID) AS Wagers,
								SUM(Actual_stake) AS Stake
			FROM	dbo.bettrans b WITH (NOLOCK)							
			WHERE	b.winlostdate BETWEEN @FDate AND @TDate
				AND b.StatusID IN (0,1)
				AND EXISTS (SELECT 1 FROM #MasterList sl WHERE sl.MasterID = b.mrecommend)	
				AND EXISTS (SELECT 1 FROM @BettypeList bt WHERE bt.Bettype = b.Bettype)	
				AND (
					EXISTS (SELECT 1 FROM dbo.Match m WITH (NOLOCK) WHERE m.MatchID = b.MatchID AND m.sporttype IN (Select Sporttype FROM @SporttypeList))
					OR
					(EXISTS (SELECT 1 FROM @OutrightList r WHERE r.MatchID = b.MatchID) AND (@BettypeGroup IN (10,0))) --- Outright (bettype)
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
			GROUP BY mrecommend



	SELECT	c.CustId,
			c.Username, 
			c.FirstName AS Name,
			SUM (Wagers) AS Wagers,
			SUM (Stake) AS Stake,
			0 AS ValidStake,
			0 AS MemberIncome,
										
			0 AS Agent,
			0 AS AgentResult,	
			0 AS MasterIncome,
			0 AS MasterResult,
			0 AS MasterStock,
										
			0 AS Super,
			0 AS SuperIncome,
			0 AS SuperResult,
			0 AS SuperStock 
	FROM #MasterOutstanding m
		INNER JOIN Customer c WITH (NOLOCK) 
			ON c.CustID = m.CustID
	WHERE C.RoleID = 3
	GROUP BY c.CustId,
			c.Username,
			c.FirstName

	SET NOCOUNT OFF;
END
GO