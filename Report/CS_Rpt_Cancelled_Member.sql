/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Rpt_Cancelled_Member]
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
	Task: CN88 - Agent report (Master view Agent)
	DB: DBAGE.bodb02	
	Revisions:
		- 20190214@Sophia: Create new [RedmineID: #105660] 
	Param's Explanation:
		- @CustId: AgentID
		- @IsOwner: Upline view Member , @IsOwner = 0
		- @ProductId: default = 1: Sportsbook
		- @Bettype: default = 0: all
		- @SporttypeGroup: default = 0: All
		- @IsLive: default = 2: All
						= 1: Live
						= 0: Dead
		- @ReportType : type of report 
						= 1: Cancelled Report
						= 2: Abnormal Bets
	Sample:

  EXEC [CS_Rpt_Cancelled_Member]
	@CustId				= 13884934,	
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

	CREATE TABLE #MemberCancelled
	(
		CustId			INT,
		Username		VARCHAR(50),
		Name			VARCHAR(50),
		Wagers			INT,
		Stake			MONEY, 
		ValidStake		MONEY, 
		MemberIncome	MONEY,
		 				
		AgentIncome		MONEY,
		AgentResult		MONEY		 
	) 
 	
	
	--- 1. Get AgentList
	
	CREATE TABLE #MemberList (CustId INT)	
	
	---- Upline view Member
	BEGIN 
		INSERT INTO #MemberList (CustId)
		SELECT  CustID
		FROM	dbo.CustInfo WITH (NOLOCK) 
		WHERE	recommend = @CustID
				AND RoleID = 1
	END
	
	
	--- 2. Get MatchID by Sports

	DECLARE @SporttypeList AS TABLE (Sporttype SMALLINT PRIMARY KEY)
	DECLARE @OutrightList AS TABLE (MatchID INT)
	
	INSERT INTO @SporttypeList (Sporttype)   --- List Sporrtype by @SporttypeGroup 
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
			INSERT INTO	#MemberCancelled (
										CustId,
										Username,
										Name,
										Wagers,
										Stake, 
										ValidStake, 
										MemberIncome,		 				
										AgentIncome,
										AgentResult	 
										) 
									 	
			SELECT
			  					CustId,
								'' AS Username,
								'' AS Name,
								COUNT(TransID) AS Wagers,
								SUM(Actual_stake) AS Stake,
								SUM(ABS(winlost - actual_stake)) ValidStake,
								SUM(Winlost - actual_stake + Playercomm) AS MemberIncome,

								SUM(AWinlost + Comm - Playercomm) AS AgentIncome,	
								SUM((Winlost - actual_stake + Playercomm) + (Awinlost + Comm - PlayerComm)) AS AgentResult

			FROM	dbo.bettrans b WITH(NOLOCK)		
				INNER JOIN dbo.Match m WITH (NOLOCK) ON m.MatchID = b.matchID					
			WHERE	b.winlostdate BETWEEN @FDate AND @TDate
				AND b.StatusID IN (0,1)
				AND EXISTS (SELECT 1 FROM #MemberList sl WHERE sl.CustId = b.CustID)					
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
			GROUP BY CustId


			 

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
			SUM (AgentIncome) AS AgentIncome,
			SUM (AgentResult) AS AgentResultA
	FROM #MemberCancelled m
		INNER JOIN CustInfo c WITH (NOLOCK) 
			ON c.CustID = m.CustID
	WHERE C.RoleID = 1
	GROUP BY c.CustId,
			c.Username

	SET NOCOUNT OFF
END
GO

GRANT EXECUTE ON [CS_Rpt_Cancelled_Member] TO bodbDownlineNet 
GO
