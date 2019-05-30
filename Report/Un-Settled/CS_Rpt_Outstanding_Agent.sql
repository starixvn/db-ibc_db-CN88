/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Rpt_Outstanding_Agent]
	@CustId				INT = 0,	 
	@IsOwner			BIT = 1,
	@FromDate			SMALLDATETIME,
	@ToDate				SMALLDATETIME,	 
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
		- 20190329@Sophia: Implement Non Sports [Redmine: #109521]
		- 20190528@Sophia: Fix bug VS [Redmine: #113482]
		
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
	
	CREATE TABLE #AgentList (AgentId INT  PRIMARY KEY)
	
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
	DECLARE @BettypeList TABLE (ProductID INT, Bettype SMALLINT, EventType TINYINT, RefTable TINYINT)
	INSERT INTO @BettypeList
	SELECT DISTINCT ProductID, Bettype, EventType, RefTable FROM dbo.CS_f_BettypeMatrix_Sel (0, @SporttypeGroup, @BettypeGroup, @isTest)	

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
  		
	--- 5. Get report
	DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME;

	SELECT  @FDate = @FromDate, @TDate = @ToDate;
 
		INSERT INTO	#AgentOutstanding (
									CustId,
									Username,
									Name,
									Wagers,
									Stake 
									)		
		SELECT
							recommend,
							'' AS Username,
							'' AS Name,
							COUNT(TransID) AS Wagers,
							SUM(Stake) AS Stake 

		FROM	dbo.bettrans b WITH (NOLOCK)
				INNER JOIN @BettypeList bt ON bt.Bettype = b.Bettype AND bt.RefTable = 0
		WHERE	b.winlostdate BETWEEN @FDate AND @TDate
			AND b.StatusID IN (0,1)
			AND EXISTS (SELECT 1 FROM #AgentList sl WHERE sl.AgentID = b.recommend)	
			AND (
					bt.EventType = 0  --- bettrans only
					OR EXISTS (SELECT 1 FROM dbo.Match m WITH (NOLOCK) INNER JOIN @SporttypeList s ON m.sporttype = s.Sporttype WHERE m.MatchID = b.MatchID AND bt.EventType = 1)
					OR EXISTS (SELECT 1 FROM @OutrightList r WHERE r.MatchID = b.MatchID AND bt.EventType = 2)
					OR EXISTS (SELECT 1 FROM @VSOutrightList r WHERE r.MatchID = b.MatchID AND bt.EventType = 3)
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
		GROUP BY recommend
			
		-- Mix parlay of BRVS
		IF (@BettypeGroup IN (2799,0) AND @SporttypeGroup IN(13,0) AND @IsLive IN (0,2))
		BEGIN 
			INSERT INTO	#AgentOutstanding (
									CustId,
									Username,
									Name,
									Wagers,
									Stake 
									)		
			SELECT
							recommend,
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
				AND EXISTS (SELECT 1 FROM #AgentList sl WHERE sl.AgentID = b.recommend)	
			GROUP BY recommend
		END		
			
		------Translog table 
		INSERT INTO	#AgentOutstanding (
									CustId,
									Username,
									Name,
									Wagers,
									Stake 
									)		
		SELECT
							recommend,
							'' AS Username,
							'' AS Name,
							COUNT(translogid) AS Wagers,
							SUM(Stake) AS Stake 

		FROM	dbo.Translog b WITH (NOLOCK)
				INNER JOIN @BettypeList bt ON bt.Bettype = b.gameID AND bt.RefTable = 3
		WHERE	b.winlostdate BETWEEN @FDate AND @TDate
			AND b.StatusID IN (0,1)
			AND EXISTS (SELECT 1 FROM #AgentList sl WHERE sl.AgentID = b.recommend)	
			AND (
					bt.EventType = 0  --- translog only
					OR EXISTS (SELECT 1 FROM dbo.Match m WITH (NOLOCK) INNER JOIN @SporttypeList s ON m.sporttype = s.Sporttype WHERE m.MatchID = b.eventID AND bt.EventType = 1)
					OR EXISTS (SELECT 1 FROM @OutrightList r WHERE r.MatchID = b.eventID AND bt.EventType = 2)
					OR EXISTS (SELECT 1 FROM @VSOutrightList r WHERE r.MatchID = b.eventID AND bt.EventType = 3)
				)
			AND (   @IsLive = 2   --- all
					OR b.Liveindicator = @IsLive 
				)								
		GROUP BY recommend
		
	
	SELECT	c.CustId,
			c.Username, 
			c.FirstName AS Name,
			SUM (Wagers) AS Wagers,
			SUM (Stake) AS Stake,
			0 AS ValidStake,
			0 AS MemberIncome,

			0 AS AgentCurrency,										
			0 AS Agent,
			0 AS AgentIncome,
			0 AS AgentResult,
			0 AS MasterStock,
				
			0 AS MasterIncome,
			0 AS MasterResult
	FROM #AgentOutstanding m
		INNER JOIN Customer c WITH (NOLOCK) 
			ON c.CustID = m.CustID
	WHERE C.RoleID = 2
	GROUP BY c.CustId,
			c.Username, 
			c.FirstName

	SET NOCOUNT OFF
END
GO
