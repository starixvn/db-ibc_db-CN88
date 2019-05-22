/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Rpt_Outstanding_Headline]	
	@FromDate			SMALLDATETIME,
	@ToDate				SMALLDATETIME,		
	@SporttypeGroup		SMALLINT = 0, -- all
	@BettypeGroup		SMALLINT = 0, -- all
	@IsLive				TINYINT = 2,  -- all 
	@IsExcludedTest		BIT = 1

AS

/*
	Created: 20190521@Sophia
	Task: CN88 - Headline report 
	DB: DBAGE.bodb02	
	Revisions:
		- 20190521@Sophia: initial [Redmine: #113828]
	 
		
	Param's Explanation:
		- @SporttypeGroup: default = 0: All
		- @BettypeGroup: default = 0: All
		- @IsLive: (market)
					default = 2: All
						= 1: Live
						= 0: Dead			
	[CS_Rpt_Outstanding_Headline] '2019-04-28', '2019-05-05',0,0,2 
 
*/

BEGIN
	SET NOCOUNT ON;

	CREATE TABLE #SuperOutstanding
	(
		CustId			INT,
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
	
	CREATE TABLE #SuperList (SuperID INT PRIMARY KEY, UplineID INT)
	
	---- Company view all headline  
	BEGIN 
		INSERT INTO #SuperList (SuperID, UplineID)
		SELECT  CustID, UplineID
		FROM	dbo.CustSuper WITH (NOLOCK) 
		WHERE	UplineID IS NOT NULL
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

			INSERT INTO	#SuperOutstanding (
								CustId,
								Wagers,
								Stake)		
			SELECT
			  					srecommend,
								COUNT(TransID) AS Wagers,
								SUM(Stake) AS Stake
			FROM	dbo.bettrans b WITH (NOLOCK)
					INNER JOIN @BettypeList bt ON bt.Bettype = b.Bettype AND bt.RefTable = 0
			WHERE	b.winlostdate BETWEEN @FDate AND @TDate
				AND b.StatusID IN (0,1)
				AND EXISTS (SELECT 1 FROM #SuperList sl WHERE sl.SuperID = b.srecommend)
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
				AND (b.currency <> 20 OR @IsExcludedTest = 0)
			GROUP BY srecommend

			-- Mix parlay of BRVS
			IF (@BettypeGroup IN (2799,0) OR @SporttypeGroup IN(13,0) AND @IsLive IN (0,2))
			BEGIN 
				INSERT INTO	#SuperOutstanding (
								CustId,
								Wagers,
								Stake)		
				SELECT
			  					srecommend,
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
					AND (b.currency <> 20 OR @IsExcludedTest = 0)
				GROUP BY srecommend
			END		

			
			------Translog table 
			INSERT INTO	#SuperOutstanding (
								CustId,
								Wagers,
								Stake)		
			SELECT
			  					srecommend,
								COUNT(translogid) AS Wagers,
								SUM(Stake) AS Stake
			FROM	dbo.Translog b WITH (NOLOCK)
					INNER JOIN @BettypeList bt ON bt.Bettype = b.gameID AND bt.RefTable = 3
			WHERE	b.winlostdate BETWEEN @FDate AND @TDate
				AND b.StatusID IN (0,1)
				AND EXISTS (SELECT 1 FROM #SuperList sl WHERE sl.SuperID = b.srecommend)
				AND (
					bt.EventType = 0  --- translog only
					OR EXISTS (SELECT 1 FROM dbo.Match m WITH (NOLOCK) WHERE m.MatchID = b.eventID AND bt.EventType = 1)
					OR EXISTS (SELECT 1 FROM @OutrightList r WHERE r.MatchID = b.eventID AND bt.EventType = 2)
					OR EXISTS (SELECT 1 FROM @VSOutrightList r WHERE r.MatchID = b.eventID AND bt.EventType = 3)
				)
				AND (   @IsLive = 2   --- all
						OR  b.Liveindicator = @IsLive
						 
					)	
				AND (b.currency <> 20 OR @IsExcludedTest = 0)					
			GROUP BY srecommend
			
			
	SELECT	c.CustId,
			c.Username,  
			SUM (Wagers) AS Wagers,
			SUM (Stake) AS Stake,
			0 AS ValidStake,
			0 AS MemberIncome,			
			
			0 AS SuperComm, 
			0 AS HouseWinloss,
			0 AS HouseComm,
			0 AS HouseIncome,			
			0 AS HeadlineStock
	FROM #SuperOutstanding s
	INNER JOIN #SuperList sl ON sl.SuperID = s.CustID
	INNER JOIN Customer c WITH (NOLOCK) 
			ON c.CustID = sl.UplineID
	WHERE C.RoleID = 0
	GROUP BY c.CustId, c.Username 
	
	SET NOCOUNT OFF

END
GO
