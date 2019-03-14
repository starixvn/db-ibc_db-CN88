/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0"></info>*/	
USE bodb02
GO 

ALTER PROCEDURE [dbo].[CS_TotalBets_Bettype_Agent]
	@CustID INT ,
	@Type TINYINT = 1, 
	@SporttypeGroup INT = 0,	
	@MatchId INT = 0,
	@StakeCondition TINYINT = 1,
	@Stake MONEY = 0,
	@PossType TINYINT = 0,
	@IsLive TINYINT = 2
AS
 
/*
Created: 20190307@Sophia
Task : CN88 - Total Bet drilldown bettype: Super view downline
DB: DB042.bodb02
Original:

Revisions:
    - 20190307@Sophia: initial SP [Redmine: #109693] 
	
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
*/
BEGIN
	SET NOCOUNT ON

 	
	SELECT 	Bettype,
			Betteam,
			Liveindicator,
			CASE @PossType WHEN 0 THEN Stake0	
						   WHEN 1 THEN Stake1
						   WHEN 2 THEN Stake2
						   WHEN 3 THEN Stake3
						   WHEN 4 THEN Stake4
						   WHEN 5 THEN Stake5
						   WHEN 6 THEN Stake6
						   WHEN 7 THEN Stake7
			END	AS Stake										
	FROM  (
			SELECT
				Bettype,
				Betteam,
				Liveindicator,
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
			WHERE  	
				b.recommend = @CustId 
				AND b.statusID IN (0,1) 			
				AND (
						(@StakeCondition = 0 AND b.Stake = @Stake) 
						OR (@StakeCondition = 1 AND b.Stake > @Stake)
						OR (@StakeCondition = 2 AND b.Stake < @Stake)
					)
				AND b.MatchID = @MatchID
			GROUP BY
				b.Bettype,
				b.Betteam,
				b.Liveindicator
			) A
	
	
	 
END
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_Bettype_Agent] TO [bodbDownlineNet]
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_Bettype_Agent] TO [bodbDownlineNetView]
GO 
