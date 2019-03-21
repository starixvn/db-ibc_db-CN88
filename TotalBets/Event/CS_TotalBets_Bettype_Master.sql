/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0"></info>*/	
USE bodb02
GO 

ALTER PROCEDURE [dbo].[CS_TotalBets_Bettype_Master]
	@CustID INT ,	
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
	- @CustID = MasterID
*/
BEGIN
	SET NOCOUNT ON

 	------ Check SP Version
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)
	
	SELECT 	MatchID,
			B.BettypeGroup As BettypeGroup,
			CASE WHEN B.BettypeGroup IN (1,2,3,5,7,8,12,15,17,18,20,21,428,430) THEN Betteam ELSE '' END AS Betteam,
			CASE WHEN B.BettypeGroup IN (1,2,3,5,7,8,12,15,17,18,20,21,428,430) THEN Liveindicator ELSE 0 END AS Liveindicator,
			SUM (Wager) AS Wager,
			CASE @PossType WHEN 0 THEN SUM (Stake0) 
						   WHEN 3 THEN SUM (Stake3)
						   WHEN 4 THEN SUM (Stake4)
						   WHEN 7 THEN SUM (Stake7)
			END	AS Stake										
	FROM  (
			SELECT
				MatchID,
				Bettype,
				Betteam,
				Liveindicator,
				COUNT(b.TransId) AS Wager,  				
				SUM (b.Stake) AS Stake0,
				SUM (b.Stake * (mpositiontaking)) AS Stake3,
				SUM (b.Stake * (apositiontaking)) AS Stake4,
				SUM (b.Stake * (mpositiontaking + apositiontaking)) AS Stake7
			FROM bettrans b WITH (NOLOCK)				
			WHERE  	
				b.mrecommend = @CustId 
				AND b.statusID IN (0,1) 
				AND b.bettype <> 10				
				AND (
						(@StakeCondition = 0 AND b.Stake = @Stake) 
						OR (@StakeCondition = 1 AND b.Stake > @Stake)
						OR (@StakeCondition = 2 AND b.Stake < @Stake)
					)
				AND b.MatchID = @MatchID
				AND (   @IsLive = 2   --- all
					OR
					(b.bettype <> 29 AND b.Liveindicator = @IsLive)
					OR 
					(b.bettype = 29  AND b.livehomescore IN ( SELECT 0 AS IsLive WHERE @IsLive = 0
															UNION 
															SELECT 2 AS IsLive WHERE @IsLive = 0
															UNION 
															SELECT 1 AS IsLive WHERE @IsLive = 1																		
															)
					)
				)
			GROUP BY
				b.MatchID,
				b.Bettype,
				b.Betteam,
				b.Liveindicator
			) A
			CROSS APPLY (SELECT Bettype, BettypeGroup FROM dbo.CS_f_BettypeGroupMatrix_Sel (0,0,A.Bettype,@Istest) WHERE BettypeGroup <> 10 ) B
	GROUP BY 
			MatchID,
			B.BettypeGroup,
			CASE WHEN B.BettypeGroup IN (1,2,3,5,7,8,12,15,17,18,20,21,428,430) THEN Betteam ELSE '' END,
			CASE WHEN B.BettypeGroup IN (1,2,3,5,7,8,12,15,17,18,20,21,428,430) THEN Liveindicator ELSE 0 END
	
	 
END
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_Bettype_Master] TO [bodbDownlineNet]
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_Bettype_Master] TO [bodbDownlineNetView]
GO 
