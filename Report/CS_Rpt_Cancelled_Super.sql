/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Rpt_Cancelled_Super]
	@CustId				INT = 0,
	@IsOwner			BIT = 1, 
	@FromDate			SMALLDATETIME,
	@ToDate				SMALLDATETIME,	
	@ArchiveDate		SMALLDATETIME,
	@MoveBetsDay		SMALLDATETIME,
	@SporttypeGroup		SMALLINT = 0, -- all
	@BettypeGroup		SMALLINT = 0, -- all
	@IsLive				TINYINT = 2 , -- all
	@ReportType 		TINYINT = 1
AS

/*
	Created: 20190214@Sophia
	Task: CN88 - Supers report by ID 
	DB: DBAGE.bodb02	
	Revisions:
		- 20190214@Sophia: Create new [RedmineID: #105660] 
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
						
						
		EXEC [CS_Rpt_Cancelled_Super] 
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

	CREATE TABLE #SuperCancelled
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

		
	----5. Get Tier 0 Poss
	IF @IsOwner = 0
	BEGIN 
		DECLARE @ExtraPT AS TABLE (SuperID INT, ExtraPT DECIMAL(9,8), FromDate DATETIME, ToDate DATETIME, ProductID TINYINT)----, Sporttype SMALLINT, SubProduct VARCHAR (50) )

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

	SELECT  @FDate = @FromDate, @TDate = @ToDate;

		IF @ToDate > @MoveBetsDay
		BEGIN
			IF @FromDate <= @MoveBetsDay
			BEGIN
				SET @FDate = DATEADD(DD, 1, @MoveBetsDay);
			END
			
			IF @ReportType = 1  --- Cencelled Bets
			BEGIN 
				INSERT INTO	#SuperCancelled (
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
									SUM(Actual_stake) AS Stake										
				FROM	dbo.bettrans b WITH (NOLOCK)		
					INNER JOIN @BettypeList bt
						ON	bt.Bettype = b.bettype
					LEFT JOIN @ExtraPT e 
						ON	b.Srecommend = e.SuperID 
							AND b.winlostdate BETWEEN e.FromDate AND E.ToDate
							AND bt.ProductID = e.ProductID
				WHERE	b.winlostdate BETWEEN @FDate AND @TDate
					AND b.StatusID IN (101,102,103)
					AND CASE WHEN b.ExtraInfo LIKE '%p1%' THEN
								ISNULL(CAST(('<xml>' + b.ExtraInfo + '</xml>') AS XML).value('data(/xml/p1/@ab)[1]','TINYINT'), 0)
							ELSE 0
						END <> 1
					AND EXISTS (SELECT 1 FROM #SuperList sl WHERE sl.SuperID = b.srecommend)		
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
				GROUP BY srecommend
			END 
			ELSE --- Abnormal Bet
			BEGIN 
				INSERT INTO	#SuperCancelled (
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
									SUM(Actual_stake) AS Stake											
				FROM	dbo.bettrans b WITH (NOLOCK)		
					INNER JOIN @BettypeList bt
						ON	bt.Bettype = b.bettype
					LEFT JOIN @ExtraPT e 
						ON	b.Srecommend = e.SuperID 
							AND b.winlostdate BETWEEN e.FromDate AND E.ToDate
							AND bt.ProductID = e.ProductID
				WHERE	b.winlostdate BETWEEN @FDate AND @TDate
					AND b.StatusID = 102
					AND CASE WHEN b.ExtraInfo LIKE '%p1%' THEN
								ISNULL(CAST(('<xml>' + b.ExtraInfo + '</xml>') AS XML).value('data(/xml/p1/@ab)[1]','TINYINT'), 0)
							ELSE 0
						END = 1
					AND EXISTS (SELECT 1 FROM #SuperList sl WHERE sl.SuperID = b.srecommend)		
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

			INSERT INTO	#SuperCancelled (
								CustId,
								Username,
								Name,
								Wagers,
								Stake)		
			SELECT
			  					CustId,
								'' AS Username,
								'' AS Name,
								SUM(Wagers) AS Wagers,
								SUM(Stake) AS Stake										
			FROM	bodb_Summary.dbo.CS_SumCancelled b WITH (NOLOCK)						
			WHERE	b.winlostdate BETWEEN @FDate AND @TDate	
				AND b.CancelType = @ReportType			
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
			
				INSERT INTO	#SuperCancelled (
									CustId,
									Username,
									Name,
									Wagers,
									Stake )		
				SELECT
									CustId,
									'' AS Username,
									'' AS Name,
									SUM(Wagers) AS Wagers,
									SUM(Stake) AS Stake
									
				FROM	bodb_Summary.dbo.CS_SumCancelled_Old b WITH (NOLOCK)						
				WHERE	b.winlostdate BETWEEN @FDate AND @TDate		
					AND b.CancelType = @ReportType
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
	FROM #SuperCancelled s
	INNER JOIN Customer c WITH (NOLOCK) 
		ON c.CustID = s.CustID
	WHERE C.RoleID = 4
	GROUP BY c.CustId, c.Username, c.FirstName
	
	SET NOCOUNT OFF

END
GO
 