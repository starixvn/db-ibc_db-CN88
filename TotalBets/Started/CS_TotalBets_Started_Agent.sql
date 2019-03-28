/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0"></info>*/	
USE bodb02
GO 

ALTER PROCEDURE [dbo].[CS_TotalBets_Started_Agent]
	@CustID INT ,	
	@DateType TINYINT = 0,
	@SporttypeGroup INT = 0,
	@LeagueId INT = 0,
	@StakeCondition TINYINT = 1,
	@Stake MONEY = 0,
	@PossType TINYINT = 0,
	@IsLive TINYINT = 2
AS
 
/*
Created: 20190325@Sophia
Task : CN88 - Total Bet for Started: Agent view downline
DB: DB042.bodb02
Original:

Revisions:
    - 20190325@Sophia: initial SP [Redmine: #109693] 
	
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

	- @Type = 5: Started
	- @DateType = 0: all
				= 1: Today
				= 2: Yesterday 
	- @IsLive: mean Market on UI 
			default = 2: All
					= 1: Live
					= 0: Dead
	- @CustID = MasterId
*/
BEGIN
	SET NOCOUNT ON

	------ Check SP Version
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	--- Get Sporttype
	
	DECLARE @SporttypeList VARCHAR(MAX)	
	SELECT @SporttypeList = COALESCE (@SporttypeList + ',', '') + CONVERT(VARCHAR(5),Sporttype) 
	FROM bodb02.dbo.CS_f_SporttypeMatrix_Sel (0, @SporttypeGroup, 0, @isTest)	
	 	
	CREATE TABLE #StartedData (
				leagueid INT, 	
				MatchID INT,
				HomeId INT,	
				AwayId INT,
				LiveHomeScore INT,
				LiveAwayScore INT,
				HTHomeScore INT,
				HTAwayScore INT,
				ShowtimeDT SMALLDATETIME,
				OfferLive BIT,
				IsNeutral BIT,
				LiveType BIT,  
				liveindicator BIT,
				bettypeGroup SMALLINT,
				Wager INT,  				
				Stake0 MONEY,
				Stake1 MONEY,
				Stake2 MONEY,
				Stake3 MONEY,
				Stake4 MONEY,
				Stake5 MONEY,
				Stake6 MONEY,
				Stake7 MONEY
				)
 
		INSERT INTO #StartedData 
		SELECT 
				m.leagueid, 	
				m.MatchID,
				m.HomeId,	
				m.AwayId,
				m.LiveHomeScore,
				m.LiveAwayScore,
				m.HTHomeScore,
				m.HTAwayScore,
				m.ShowtimeDT,
				m.OfferLive,
				m.IsNeutral,
				m.LiveType,  --- show text Live on the UI 
				b.liveindicator,
				bg.bettypeGroup,
				COUNT(b.TransId) AS Wager,  				
				SUM (b.Stake) AS Stake0,
				SUM (b.Stake * ( 1 - tpositiontaking)) AS Stake1,
				SUM (b.Stake * (spositiontaking)) AS Stake2,
				SUM (b.Stake * (mpositiontaking)) AS Stake3,
				SUM (b.Stake * (apositiontaking)) AS Stake4,
				SUM (b.Stake * (spositiontaking + mpositiontaking + apositiontaking)) AS Stake5,
				SUM (b.Stake * (spositiontaking + mpositiontaking)) AS Stake6,
				SUM (b.Stake * (mpositiontaking + apositiontaking)) AS Stake7	
			FROM bettrans b WITH (NOLOCK)
				INNER JOIN dbo.CS_f_TotalBets_Event_Sel (5, @isTest, @LeagueId, @SporttypeList) AS m ON m.matchid = b.matchid 	
				CROSS APPLY dbo.CS_f_BettypeGroupMatrix_Sel (0,0,b.Bettype,@IsTest) AS bg
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
				AND (m.DateType = @DateType OR @DateType = 0)
			GROUP BY 
				m.leagueid, 	
				m.MatchID,
				m.HomeId,	
				m.AwayId,
				m.LiveHomeScore,
				m.LiveAwayScore,
				m.HTHomeScore,
				m.HTAwayScore,
				m.ShowtimeDT,
				m.OfferLive,
				m.IsNeutral,
				m.LiveType,
				b.liveindicator,
				bg.bettypeGroup


---- get MatchInfo 

	SELECT  LeagueId, 
			MatchID,
			HomeId,	
			AwayId,
			LiveHomeScore,
			LiveAwayScore,
			HTHomeScore,
			HTAwayScore,
			ShowtimeDT,
			OfferLive,
			IsNeutral,
			LiveType,	--- show text Live on the UI 		
			COUNT (DISTINCT bettypeGroup) BettypeCount								
	FROM   #StartedData A
	GROUP BY  
			LeagueId, 
			MatchID,
			HomeId,	
			AwayId,
			LiveHomeScore,
			LiveAwayScore,
			HTHomeScore,
			HTAwayScore,
			ShowtimeDT,
			OfferLive,
			IsNeutral,
			LiveType
	
	 
	 ----- SumInfo 
	SELECT  MatchID,			
			LiveIndicator,
			SUM(Wager) AS Wager, 
			SUM(CASE @PossType WHEN 0 THEN Stake0	
						   WHEN 1 THEN Stake1
						   WHEN 2 THEN Stake2
						   WHEN 3 THEN Stake3
						   WHEN 4 THEN Stake4
						   WHEN 5 THEN Stake5
						   WHEN 6 THEN Stake6
						   WHEN 7 THEN Stake7
				 END)	AS Stake										
	FROM   #StartedData A
	GROUP BY MatchID, LiveIndicator
	
	DROP TABLE #StartedData
	
	 
END
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_Started_Agent] TO [bodbDownlineNet]
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_Started_Agent] TO [bodbDownlineNetView]
GO 
