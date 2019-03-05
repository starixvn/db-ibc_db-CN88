/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Rpt_Cancelled_Member]
	@CustId				INT = 0,	 
	@IsOwner			BIT = 1,
	@FromDate			SMALLDATETIME,
	@ToDate				SMALLDATETIME,	
	@ArchiveDate		SMALLDATETIME,
	@MoveBetsDay		SMALLDATETIME, 
	@SporttypeGroup		SMALLINT = 0, -- all
	@BettypeGroup		SMALLINT = 0, -- all
	@IsLive				TINYINT = 2, -- all
	@ReportType 		TINYINT = 1	

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
	Sample:

  EXEC [CS_Rpt_Cancelled_Member]
	@CustId				= 13884934,	
	@IsOwner			= 0,
	@FromDate			= '2019-01-01',
	@ToDate				= '2019-03-01',	
	@ArchiveDate		= '2019-02-03',
	@MoveBetsDay		= '2019-02-10',
	@ProductId			= 1,
	@SporttypeGroup		= 0, -- all
	@BettypeGroup			= 0, -- all
	@IsLive				= 2 
	   

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
		AgentResultA		MONEY		 
	) 
 	
	
	--- 1. Get AgentList
	
	CREATE TABLE #MemberList (CustId INT PRIMARY KEY)	
	
	---- Upline view Member
	BEGIN 
		INSERT INTO #MemberList (CustId)
		SELECT  CustID
		FROM	dbo.CustInfo WITH (NOLOCK) 
		WHERE	recommend = @CustID
				AND RoleID = 1
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
	------5.1. bettrans range
	DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME;

	SELECT  @FDate = @FromDate, @TDate = @ToDate;

	IF @ToDate >= @ArchiveDate 
	BEGIN
		IF @ToDate > @MoveBetsDay
		BEGIN
			IF @FromDate <= @MoveBetsDay
			BEGIN
				SET @FDate = DATEADD(DD, 1, @MoveBetsDay);
			END
		 	
			IF @ReportType = 1  --- Cencelled Bets
			BEGIN 			
				INSERT INTO	#MemberCancelled (
											CustId,
											Username,
											Name,
											Wagers,
											Stake 
											) 
											
				SELECT
									CustId,
									'' AS Username,
									'' AS Name,
									COUNT(TransID) AS Wagers,
									SUM(Actual_stake) AS Stake
				FROM	dbo.bettrans b WITH (NOLOCK)							
				WHERE	b.winlostdate BETWEEN @FDate AND @TDate
					AND b.StatusID IN (101,102,103)
					AND CASE WHEN b.ExtraInfo LIKE '%p1%' THEN
										ISNULL(CAST(('<xml>' + b.ExtraInfo + '</xml>') AS XML).value('data(/xml/p1/@ab)[1]','TINYINT'), 0)
									ELSE 0
								END <> 1
					AND EXISTS (SELECT 1 FROM #MemberList sl WHERE sl.CustID = b.CustID)	
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
				GROUP BY CustId
			END
			ELSE
			BEGIN 
				INSERT INTO	#MemberCancelled (
											CustId,
											Username,
											Name,
											Wagers,
											Stake
											) 
											
				SELECT
									CustId,
									'' AS Username,
									'' AS Name,
									COUNT(TransID) AS Wagers,
									SUM(Actual_stake) AS Stake

				FROM	dbo.bettrans b WITH (NOLOCK)							
				WHERE	b.winlostdate BETWEEN @FDate AND @TDate
					AND b.StatusID = 102
					AND CASE WHEN b.ExtraInfo LIKE '%p1%' THEN
										ISNULL(CAST(('<xml>' + b.ExtraInfo + '</xml>') AS XML).value('data(/xml/p1/@ab)[1]','TINYINT'), 0)
									ELSE 0
								END = 1
					AND EXISTS (SELECT 1 FROM #MemberList sl WHERE sl.CustID = b.CustID)	
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
				GROUP BY CustId
			END
		END 
		
		-- 5.2: sum table range
		SET @FDate = @FromDate;
		
		IF @FromDate <= @MoveBetsDay
		BEGIN
		
			IF @ArchiveDate < @FromDate
			BEGIN
				SET @FDate = @FromDate;
			END
			ELSE
			BEGIN
				SET @FDate = @ArchiveDate;
			END		
		
			IF @ToDate > @MoveBetsDay
			BEGIN
				SET @TDate = @MoveBetsDay;
			END		 
			
			INSERT INTO	#MemberCancelled (
									CustId,
									Username,
									Name,
									Wagers,
									Stake 
									) 		
			SELECT
								CustID,
								'' AS Username,
								'' AS Name,
								SUM(Wagers) AS Wagers,
								SUM(Stake) AS Stake															
										
			FROM	bodb_Summary.dbo.CS_SumCancelled b WITH (NOLOCK)						
			WHERE	b.winlostdate BETWEEN @FDate AND @TDate		
				AND b.CancelType = @ReportType			
				AND EXISTS (SELECT 1 FROM #MemberList sl WHERE sl.CustID = b.CustID)						
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
				
				INSERT INTO	#MemberCancelled (
									CustId,
									Username,
									Name,
									Wagers,
									Stake 
									) 		
				SELECT
									CustID,
									'' AS Username,
									'' AS Name,
									SUM(Wagers) AS Wagers,
									SUM(Stake) AS Stake														
											
				FROM	bodb_Summary.dbo.CS_SumCancelled_Old b WITH (NOLOCK)						
				WHERE	b.winlostdate BETWEEN @FDate AND @TDate	
					AND b.CancelType = @ReportType
					AND EXISTS (SELECT 1 FROM #MemberList sl WHERE sl.CustID = b.CustID)						
					AND EXISTS (SELECT 1 FROM @BettypeList bt WHERE bt.bettype = b.bettype)
					AND EXISTS (SELECT 1 FROM @SporttypeList st WHERE st.Sporttype = b.Sporttype)
				GROUP BY CustID
			
			END

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
			SUM (AgentResultA) AS AgentResultA
	FROM #MemberCancelled m
		INNER JOIN CustInfo c WITH (NOLOCK) 
			ON c.CustID = m.CustID
	WHERE C.RoleID = 1
	GROUP BY c.CustId,
			c.Username

	SET NOCOUNT OFF
END
GO
 