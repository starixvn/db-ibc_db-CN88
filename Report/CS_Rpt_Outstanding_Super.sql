/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Rpt_Outstanding_Super]
	@CustId				INT = 0,
	@IsOwner			BIT = 1, 
	@FromDate			SMALLDATETIME,
	@ToDate				SMALLDATETIME,		
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
						
	EXEC [CS_Rpt_Outstanding_Super]
	@CustId				= 34109295,	--super view super 
	@IsOwner			= 1,
	@FromDate			= '2019-01-01',
	@ToDate				= '2019-03-01',	 
	@SporttypeGroup		= 0, -- all
	@BettypeGroup			= 0, -- all
	@IsLive				= 2
			

*/

BEGIN
	SET NOCOUNT ON;

	CREATE TABLE #SuperOutstanding
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
	DECLARE @BettypeList TABLE (ProductID INT, Bettype SMALLINT, RefTable TINYINT)
	INSERT INTO @BettypeList
	SELECT ProductID, Bettype, RefTable FROM bodb02.dbo.CS_f_BettypeMatrix_Sel (0, @SporttypeGroup, @BettypeGroup, @isTest)	
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
	DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME;

	SELECT  @FDate = @FromDate, @TDate = @ToDate;

			INSERT INTO	#SuperOutstanding (
								CustId,
								Username,
								Name,
								Wagers,
								Stake)		
			SELECT
			  					srecommend,
								'' AS Username,
								'' AS Name,
								COUNT(TransID) AS Wagers,
								SUM(Stake) AS Stake
			FROM	dbo.bettrans b WITH (NOLOCK)								
			WHERE	b.winlostdate BETWEEN @FDate AND @TDate
				AND b.StatusID IN (0,1)
				AND EXISTS (SELECT 1 FROM #SuperList sl WHERE sl.SuperID = b.srecommend)
				AND EXISTS (SELECT 1 FROM @BettypeList bt WHERE bt.Bettype = b.Bettype AND RefTable = 0)					
				AND (
					EXISTS (SELECT 1 FROM dbo.Match m WITH (NOLOCK) WHERE m.MatchID = b.MatchID AND m.sporttype IN (Select Sporttype FROM @SporttypeList))
					OR
					(EXISTS (SELECT 1 FROM @OutrightList r WHERE r.MatchID = b.MatchID) AND (@BettypeGroup IN (10,0))) --- Outright (bettype)
					OR
					EXISTS (SELECT 1 FROM @VSOutrightList r WHERE r.MatchID = b.MatchID) AND (@SporttypeGroup IN (13, 0)) ) --- VS
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
			GROUP BY srecommend

			-- Mix parlay of BRVS
			IF (@BettypeGroup IN (2799,0) OR @SporttypeGroup(13,0) AND @IsLive IN (0,2))
			BEGIN 
				INSERT INTO	#SuperOutstanding (
								CustId,
								Username,
								Name,
								Wagers,
								Stake)		
				SELECT
			  					srecommend,
								'' AS Username,
								'' AS Name,
								COUNT(TransID) AS Wagers,
								SUM(Stake) AS Stake
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
					AND b.StatusID IN (0,1)
					AND EXISTS (SELECT 1 FROM #SuperList sl WHERE sl.SuperID = b.srecommend)
				GROUP BY srecommend
			END		

			
			------Translog table 
			INSERT INTO	#SuperOutstanding (
								CustId,
								Username,
								Name,
								Wagers,
								Stake)		
			SELECT
			  					srecommend,
								'' AS Username,
								'' AS Name,
								COUNT(TransID) AS Wagers,
								SUM(Stake) AS Stake
			FROM	dbo.Translog b WITH (NOLOCK)							
			WHERE	b.winlostdate BETWEEN @FDate AND @TDate
				AND b.StatusID IN (0,1)
				AND EXISTS (SELECT 1 FROM #SuperList sl WHERE sl.SuperID = b.srecommend)
				AND EXISTS (SELECT 1 FROM @BettypeList bt WHERE bt.Bettype = b.Bettype AND RefTable = 3)	
				AND (
					EXISTS (SELECT 1 FROM dbo.Match m WITH (NOLOCK) WHERE m.MatchID = b.MatchID AND m.sporttype IN (Select Sporttype FROM @SporttypeList))	
					OR @SporttypeGroup IN(0)  ---all
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
			0 AS Master,
													
			0 AS Super,
			0 AS SuperIncome,
			0 AS SuperResult,
			0 AS SuperStock, 
								 
			0 AS HeadlineIncome,
			0 AS HeadlineResult,
			0 AS HeadlineStock
	FROM #SuperOutstanding s
	INNER JOIN Customer c WITH (NOLOCK) 
		ON c.CustID = s.CustID
	WHERE C.RoleID = 4
	GROUP BY c.CustId, c.Username, c.FirstName
	
	SET NOCOUNT OFF

END
GO
