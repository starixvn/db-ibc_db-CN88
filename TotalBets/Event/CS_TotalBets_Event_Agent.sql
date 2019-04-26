/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0"></info>*/	
USE bodb02
GO 

ALTER PROCEDURE [dbo].[CS_TotalBets_Event_Agent]
	@CustID INT ,
	@Type TINYINT = 1, 
	@SporttypeGroup INT = 0,
	@LeagueId INT = 0,
	@StakeCondition TINYINT = 1,
	@Stake MONEY = 0,
	@PossType TINYINT = 0,
	@IsLive TINYINT = 2
AS
 
/*
Created: 20190307@Sophia
Task : CN88 Retrieve Total Bet for Event: Agent view downline
DB: DB042.bodb02
Original:

Revisions:
    - 20190307@Sophia: initial SP [Redmine: #109693] 
	- 20190426@Sophia: SB only + Revise Sp  [Redmine: #112570]
	
Param's Explanation:
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

	 - @Type = 0:  All, 
		  = 1: In-play, 
		  = 2: Today, 
		  = 3: Early,
		  = 4: Outright

	- @IsLive: default = 2: All
					= 1: Live
					= 0: Dead
	- @CustID = AgentID
*/
BEGIN
	SET NOCOUNT ON

	------ Check SP Version
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	--- Get Sporttype
	
	DECLARE @SporttypeList VARCHAR(MAX)	
	SELECT @SporttypeList = COALESCE (@SporttypeList + ',', '') + CONVERT(VARCHAR(5),Sporttype) FROM bodb02.dbo.CS_f_SporttypeMatrix_Sel (1, @SporttypeGroup, 0, @isTest)	
	
	---Get #MatchID
	CREATE TABLE #EventInfo (MatchID INT, LeagueId INT, Sporttype INT, IsNeutral BIT, ShowtimeDT SMALLDATETIME, HomeId INT, AwayId INT,
						LiveHomeScore INT, LiveAwayScore INT, HTHomeScore INT, HTAwayScore INT, OfferLive BIT, LiveType TINYINT, DateType TINYINT)
	
	INSERT INTO #EventInfo (MatchID, LeagueId, Sporttype, IsNeutral, ShowtimeDT, HomeId, AwayId,
						  LiveHomeScore, LiveAwayScore, HTHomeScore, HTAwayScore, OfferLive, LiveType, DateType )
	SELECT 	MatchID, LeagueId, Sporttype, IsNeutral, ShowtimeDT, HomeId, AwayId,
			LiveHomeScore, LiveAwayScore, HTHomeScore, HTAwayScore, OfferLive, LiveType, DateType
	FROM 	dbo.CS_f_TotalBets_Event_Sel (@Type, @isTest, @LeagueId, @SporttypeList)
	
 	
	SELECT  LeagueId, 	
			MatchID,
			HomeId,	
			AwayId,
			LiveHomeScore,
			LiveAwayScore,
			ShowtimeDT,
			OfferLive,
			IsNeutral,
			Wager, 
			BettypeCount,
			CASE @PossType WHEN 0 THEN Stake0	
						   WHEN 4 THEN Stake4
			END	AS Stake										
	FROM  (
			SELECT 
				m.leagueid, 
				m.MatchID,				
				m.HomeId,	
				m.AwayId,
				m.LiveHomeScore,
				m.LiveAwayScore,
				m.ShowtimeDT,
				m.OfferLive,
				m.IsNeutral,
				COUNT(b.TransId) AS Wager,  
				COUNT(DISTINCT bg.bettypeGroup) AS BettypeCount,
				SUM (b.Stake) AS Stake0,
				SUM (b.Stake * (apositiontaking)) AS Stake4
			FROM bettrans b WITH (NOLOCK)
				INNER JOIN #EventInfo AS m ON m.matchid = b.matchid 	
				CROSS APPLY dbo.CS_f_BettypeGroupMatrix_Sel (1,0,b.Bettype,@IsTest) AS bg 				
			WHERE  	
				b.recommend = @CustId 
				AND b.statusID IN (0,1) 
				AND (
						(@StakeCondition = 0 AND b.Stake = @Stake) 
						OR (@StakeCondition = 1 AND b.Stake > @Stake)
						OR (@StakeCondition = 2 AND b.Stake < @Stake)
					)			
				AND (	@IsLive = 2   --- all
						OR b.Liveindicator = @IsLive
					)
			GROUP BY 
				m.leagueid,
				m.MatchID,
				m.HomeId,	
				m.AwayId,
				m.LiveHomeScore,
				m.LiveAwayScore,
				m.ShowtimeDT,
				m.OfferLive,
				m.IsNeutral
			) A
	
	
	 
END
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_Event_Agent] TO [bodbDownlineNet]
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_Event_Agent] TO [bodbDownlineNetView]
GO 
 