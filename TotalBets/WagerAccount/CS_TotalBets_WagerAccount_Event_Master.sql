/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0"></info>*/	
USE bodb02
GO 

ALTER PROCEDURE [dbo].[CS_TotalBets_WagerAccount_Event_Master]
	@CustID INT ,
	@MatchId INT = 0,
	@Bettype SMALLINT = 0,
	@Betteam NVARCHAR(10) = '',
	@LiveIndicator BIT = 0,
	@StakeCondition TINYINT = 1,
	@Stake MONEY = 0 
AS
 
/*
Created: 20190307@Sophia
Task : CN88 Agent Wager Account of Total Bet - by event
DB: DB042.bodb02
Original:

Revisions:
    - 20190307@Sophia: initial SP [Redmine: #109693] 
	
Param's Explanation:
	- @StakeCondition 	= 0 :  =
						= 1 :  >  (default)
						= 2 :  < 
	- @CustID : SuperID
*/
BEGIN
	SET NOCOUNT ON
	
	SELECT  C.Username, C.Firstname, A.Wager, A.Stake										
	FROM  (
			SELECT 
				b.mrecommend,
				COUNT(b.TransId) AS Wager,  
				SUM (b.Stake) AS Stake 				
			FROM bettrans b WITH (NOLOCK)
			WHERE  	
				b.srecommend = @CustId 
				AND b.statusID IN (0,1) 
				AND b.bettype = @bettype 
				AND (b.betteam = @betteam OR @betteam = '')
				AND b.MatchID = @MatchID
				AND b.LiveIndicator = @LiveIndicator
				AND (
						(@StakeCondition = 0 AND b.Stake = @Stake) 
						OR (@StakeCondition = 1 AND b.Stake > @Stake)
						OR (@StakeCondition = 2 AND b.Stake < @Stake)
					)				
			GROUP BY b.mrecommend
			) A
		INNER JOIN bodb02.dbo.Customer c WITH (NOLOCK) 
				ON c.CustId = A.mrecommend
		WHERE c.RoleID = 3
	
	
	 
END
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_WagerAccount_Event_Master] TO [bodbDownlineNet]
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_WagerAccount_Event_Master] TO [bodbDownlineNetView]
GO 