/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" isFunction="0"></info>*/	
USE bodb02
GO 

ALTER PROCEDURE [dbo].[CS_TotalBets_Outright_Master]
	@CustID			INT,
	@SubAccId		INT = 0,
	@IsAllDownline	BIT = 1,
	@SporttypeGroup INT = 0,
	@LeagueId		INT = 0,
	@StakeCondition TINYINT = 1,
	@Stake			MONEY = 0,
	@PossType		TINYINT = 0
AS

/*
	Created: 20190307@Sophia
	Task: CN88 Retrieve Total Bet for outright: Super view downline
	DB: DB042.bodb02

	Revisions:
		- 20190307@Sophia: initial SP [Redmine: #109693]
		- 20190713@Percy: Add sub account - permission on downlines [RedmineID: #116825]
	
	Param's Explanation:
		- @SubAccId: sub account
		- @IsAllDownline: is view all downlines
		- @StakeCondition 	= 0 :  =
							= 1 :  >  (default)
							= 2 :  < 
		- @PossType : 
					= 0:	Full Percentage
					= 1:	Company %: Shown on SMA
					= 2:	SMA %: Shown on SMA
					= 3:	MA%: Shown on SMA, MA
					= 4:	Agent%: Shown on SMA, MA, Agent
					= 5:	SMA + MA + Agent%: Shown on SMA
					= 6:	SMA + MA %: Shown on SMA
					= 7:	MA + Agent %: Shown on SMA, MA
		- @CustID : MasterId
*/
BEGIN
	SET NOCOUNT ON

	------ Check SP Version
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	/* ===== Get downline list by Sub Account ==== */
	DECLARE @Downlines TABLE (DownlineId INT)

	IF ISNULL(@SubAccId, 0) <> 0 AND ISNULL(@IsAllDownline, 0) = 0
	BEGIN
		INSERT INTO @Downlines (DownlineId)
		SELECT DownlineId FROM dbo.CS_f_GetDownlineBySubAcc(@SubAccId)
	END
	/* ===== End Get downline list by Sub Account ==== */

	DECLARE @SporttypeList VARCHAR(MAX)	
	SELECT @SporttypeList = COALESCE (@SporttypeList + ',', '') + CONVERT(VARCHAR(5),Sporttype) FROM bodb02.dbo.CS_f_SporttypeMatrix_Sel (1, @SporttypeGroup, 0, @isTest)	
	
	---Get event
	CREATE TABLE #EventInfo (MatchID INT, LeagueId INT, Sporttype INT, IsNeutral BIT, ShowtimeDT SMALLDATETIME, HomeId INT, AwayId INT,
						LiveHomeScore INT, LiveAwayScore INT, HTHomeScore INT, HTAwayScore INT, OfferLive BIT, LiveType TINYINT, DateType TINYINT)
	
	INSERT INTO #EventInfo (MatchID, LeagueId, Sporttype, IsNeutral, ShowtimeDT, HomeId, AwayId,
						  LiveHomeScore, LiveAwayScore, HTHomeScore, HTAwayScore, OfferLive, LiveType, DateType )
	SELECT 	MatchID, LeagueId, Sporttype, IsNeutral, ShowtimeDT, HomeId, AwayId,
			LiveHomeScore, LiveAwayScore, HTHomeScore, HTAwayScore, OfferLive, LiveType, DateType
	FROM 	dbo.CS_f_TotalBets_Event_Sel (4, @isTest, @LeagueId, @SporttypeList)
	
	
	SELECT  leagueid, MatchID, HomeId AS TeamId, 
			Wager, 
			CASE @PossType WHEN 0 THEN Stake0							  
						   WHEN 3 THEN Stake3						  
						   WHEN 4 THEN Stake4
						   WHEN 7 THEN Stake7
			END	AS Stake										
	FROM  (
			SELECT 
				m.leagueid, 
				m.MatchId,
				m.HomeId,		
				COUNT(b.TransId) AS Wager,  
				SUM (b.Stake) AS Stake0,
				SUM (b.Stake * (mpositiontaking)) AS Stake3,
				SUM (b.Stake * (apositiontaking)) AS Stake4,
				SUM (b.Stake * (mpositiontaking + apositiontaking)) AS Stake7
			FROM bettrans b WITH (NOLOCK)
				INNER JOIN #EventInfo AS m ON m.matchid = b.matchid 	
			WHERE  	
				b.mrecommend = @CustId
				AND (@IsAllDownline = 1 OR EXISTS (SELECT 1 FROM @Downlines d WHERE b.recommend = d.DownlineId))
				AND b.statusID IN (0,1) 
				AND b.bettype = 10  
				AND (
						(@StakeCondition = 0 AND b.Stake = @Stake) 
						OR (@StakeCondition = 1 AND b.Stake > @Stake)
						OR (@StakeCondition = 2 AND b.Stake < @Stake)
					)								
			GROUP BY m.leagueid, 
				m.MatchId,
				m.HomeId
			) A
END
GO