/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0"></info>*/	
USE bodb02
GO 

ALTER PROCEDURE [dbo].[CS_TotalBets_Outright_Super]
	@CustID INT ,
	@SporttypeGroup INT = 0,
	@LeagueId INT = 0,
	@StakeCondition TINYINT = 1,
	@Stake MONEY = 0,
	@PossType TINYINT = 0 
AS
 
/*
Created: 20190307@Sophia
Task : CN88 Retrieve Total Bet for outright: Super view downline
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
	-@CustID : SuperId
*/
BEGIN
	SET NOCOUNT ON

	------ Check SP Version
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	DECLARE @SporttypeList VARCHAR(MAX)	
	SELECT @SporttypeList = COALESCE (@SporttypeList + ',', '') + CONVERT(VARCHAR(5),Sporttype) FROM bodb02.dbo.CS_f_SporttypeMatrix_Sel (0, @SporttypeGroup, 0, @isTest)	
		
	SELECT  leagueid, MatchID, HomeId AS TeamId, 
			Wager, 
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
				m.leagueid, 
				m.MatchId,
				m.HomeId,	
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
				INNER JOIN dbo.CS_f_TotalBets_Event_Sel (4, @isTest, @LeagueId, @SporttypeList) AS m ON m.matchid = b.matchid 		 
			WHERE  	
				b.srecommend = @CustId 
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
GRANT EXECUTE ON [dbo].[CS_TotalBets_Outright_Super] TO [bodbDownlineNet]
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_Outright_Super] TO [bodbDownlineNetView]
GO 