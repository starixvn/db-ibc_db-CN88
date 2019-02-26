/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO
ALTER PROCEDURE [dbo].[CS_Rpt_Cancelled_Super]
	@CustId				INT = 0,
	@IsOwner			BIT = 1, 
	@FromDate			SMALLDATETIME,
	@ToDate				SMALLDATETIME,	
	@BalanceUpDay		SMALLDATETIME,
	@MoveBetsDay		SMALLDATETIME,
	@ProductId			SMALLINT = 1,
	@SporttypeGroup		SMALLINT = 0, -- all
	@Bettype			SMALLINT = 0, -- all
	@IsLive				TINYINT = 2, -- all
	@ReportType			TINYINT = 1 
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
		- @IsLive: default = 2: All
						= 1: Live
						= 0: Dead
		- @ReportType : type of report 						
						= 1: Cancelled Report
						= 2: Abnormal Bets
						
						
		EXEC [CS_Rpt_Cancelled_Super] 
			@CustId				= 2,
			@IsOwner			= 1, 
			@FromDate			= '2019-01-01',
			@ToDate				= '2019-03-01',	
			@BalanceUpDay		= '2019-02-03',
			@MoveBetsDay		= '2019-02-08',
			@ProductId			= 1,
			@SporttypeGroup		= 0, -- all
			@Bettype			= 29, -- all
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
	
	CREATE TABLE #SuperList (SuperID INT)
	
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
	
	
	--- 2. Get MatchID by Sports

	DECLARE @SporttypeList AS TABLE (Sporttype SMALLINT PRIMARY KEY)
	DECLARE @OutrightList AS TABLE (MatchID INT)
	
	INSERT INTO @SporttypeList (Sporttype)   --- List Sporttype by @SporttypeGroup 
	SELECT	DISTINCT Sporttype 
	FROM	dbo.CS_SportbettypeMatrix WITH (NOLOCK)
	WHERE	SporttypeGroup = @SporttypeGroup OR @SporttypeGroup = 0 	
	
	
	IF @Bettype IN (10, 0) --- bettype is Outright or ALL
	BEGIN 
		INSERT INTO @OutrightList (MatchID) 
		SELECT m.orid			
		FROM dbo.Outright m WITH (NOLOCK)
		INNER JOIN dbo.League l WITH (NOLOCK) ON m.LeagueId = l.LeagueId
		WHERE l.Sporttype IN (SELECT Sporttype FROM @SporttypeList)
			AND m.eventdate BETWEEN @FromDate AND @ToDate			
	END 	
 	 

	--- 3. Get Bettype 	
	DECLARE @BettypeList AS TABLE (Bettype SMALLINT) 
	
	IF @Bettype = 0  --- All bettype 
	BEGIN 
		INSERT INTO @BettypeList(Bettype)
		SELECT	DISTINCT Bettype 
		FROM	dbo.CS_SportbettypeMatrix WITH (NOLOCK)
		WHERE	(SporttypeGroup = @SporttypeGroup OR @SporttypeGroup = 0)
	END 
	ELSE 
	BEGIN 
		INSERT INTO @BettypeList(Bettype)
		VALUES (@Bettype)
	END
	
	------Get Sport Bettype Matrix------
	-- Check SP Version
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)
	
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,SubProduct VARCHAR(500))
	INSERT INTO @SportBettype
	SELECT ProductID, Bettype, SubProduct FROM bodb02.dbo.f_SportBettypeMatrix_Sel (0, 0, 0, 2, '', '', @isTest)
	
	--- End get sport bettype 	

		
	----4. Get Tier 0 Poss
	IF @IsOwner = 0
	BEGIN 
		DECLARE @ExtraPT AS TABLE (SuperID INT, ExtraPT INT, FromDate SMALLDATETIME, ToDate SMALLDATETIME)

		INSERT INTO @ExtraPT (SuperID, ExtraPT, FromDate, ToDate )
		SELECT SuperID, ExtraPT, FromDate, ToDate 
		FROM  dbo.Acc_GroupExtraPTSetting WITH (NOLOCK) 
		WHERE SuperID IN (SELECT SuperID FROM #SuperList)
			  AND ProductID = @ProductID
			  AND Sporttype = 0		--- General Sporttype of SB 
			  AND SubProduct = '' 	--- General SubProduct of SB 	 
			  AND (@FromDate BETWEEN FromDate AND ToDate
					OR @ToDate BETWEEN FromDate AND ToDate )

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
			INSERT INTO	#SuperCancelled (
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
								
								HeadlinePoss,
								HeadlineIncome,
								HeadlineResult,
								HeadlineStock )		
			SELECT
			  					srecommend,
								'' AS Username,
								'' AS Name,
								COUNT(TransID) AS Wagers,
								SUM(Actual_stake) AS Stake,
								SUM(CASE WHEN StatusId IN (112, 113) THEN ABS(winlost - actual_stake) ELSE 0 END) ValidStake,
								SUM(Winlost - actual_stake + Playercomm) AS MemberIncome,
										
								SUM(Winlost - actual_stake + Playercomm) AS Agent,
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm)) AS AgentResult,  --- Member Income + Agent Income
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm)) AS Master,
									 
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm) + (MWinlost + AComm - Comm)) AS Super,		  ---	Master Income + Agent Result 
								
								SUM(SWinlost + SComm - Acomm) AS SuperIncome,
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm) + (MWinlost + AComm - Comm) + (SWinlost + SComm - Acomm)) AS SuperResult,
								SUM(CASE WHEN StatusId IN (112, 113) THEN ABS(winlost - actual_stake) ELSE 0 END * (1 - tpositiontaking)) AS SuperStock,		
								
								MAX(e.ExtraPT) AS HeadlinePoss,
								SUM (-1 * (CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.winlost - b.actual_stake + b.scomm / (1 - b.tpositiontaking) END) * e.ExtraPT) AS HeadlineIncome,  --- MSH Win Loss + MSH Sharing Comm 
								SUM ( 								
										((CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.winlost - b.actual_stake + b.scomm / (1 - b.tpositiontaking) END) * e.ExtraPT)
										+ ((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm) + (MWinlost + AComm - Comm) + (SWinlost + SComm - Acomm)) 
									) AS HeadlineResult,
								SUM (CASE WHEN StatusId IN (112, 113) THEN ABS(winlost - actual_stake) ELSE 0 END * (1 - tpositiontaking - e.ExtraPT)) AS HeadlineStock		
										
			FROM	dbo.bettrans b WITH(NOLOCK)		
				LEFT JOIN @ExtraPT e ON b.Srecommend = e.SuperID AND b.winlostdate BETWEEN e.FromDate AND E.ToDate
			WHERE	b.winlostdate BETWEEN @FDate AND @TDate
				AND b.StatusID IN (0,1)
				AND EXISTS (SELECT 1 FROM #SuperList sl WHERE sl.SuperID = b.srecommend)									
				AND EXISTS (SELECT 1 FROM @BettypeList bt WHERE bt.Bettype = b.Bettype)
				AND (
					EXISTS (SELECT 1 FROM dbo.Match m WITH (NOLOCK) WHERE m.MatchID = b.MatchID AND m.sporttype IN (Select Sporttype FROM @SporttypeList))
					OR
					(EXISTS (SELECT 1 FROM @OutrightList r WHERE r.MatchID = b.MatchID) AND (@Bettype IN (10,0)))
					OR @Bettype = 29
					)
				AND (   @IsLive = 2   --- all
						OR
						(@Bettype <> 29 AND b.Liveindicator = @IsLive)
						OR 
						(@Bettype = 29 AND b.livehomescore IN ( SELECT 0 AS IsLive WHERE @IsLive = 0
																UNION 
																SELECT 2 AS IsLive WHERE @IsLive = 0
																UNION 
																SELECT 1 AS IsLive WHERE @IsLive = 1																		
																)
						)
					)
			GROUP BY srecommend



		--SET @FDate = @FromDate;
		
		--IF @FromDate <= @MoveBetsDay
		--BEGIN
		--	IF @ToDate > @MoveBetsDay
		--	BEGIN
		--		SET @TDate = @MoveBetsDay;
		--	END

	--		INSERT INTO #SAgCancelled(ProductID, bettype, SportType, liveindicator, GrossComm, Turnover, MAgTotal, SAgCancelled, SAgComm, NumberOfTickets)
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
	--				SUM(swinlost) AS SAgCancelled,
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
			SUM (Master) AS Master,
													
			SUM (Super) AS Super,
			SUM (SuperIncome) AS SuperIncome,
			SUM (SuperResult) AS SuperResult,
			SUM (SuperStock) AS SuperStock, 
								
			MAX (HeadlinePoss) AS HeadlinePoss,
			SUM (HeadlineIncome) AS HeadlineIncome,
			SUM (HeadlineResult) AS HeadlineResult,
			SUM (HeadlineStock) AS HeadlineStock
	FROM #SuperCancelled s
	INNER JOIN CustInfo c WITH (NOLOCK) 
		ON c.CustID = s.CustID
	WHERE C.RoleID = 4
	GROUP BY c.CustId, c.Username
	
	SET NOCOUNT OFF

END
GO

GRANT EXECUTE ON [CS_Rpt_Cancelled_Super] TO bodbDownlineNet 
GO