/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0"></info>*/	
USE bodb02
GO 

ALTER PROCEDURE [dbo].[CS_TotalBets_WagerAccount_Outright_Member]
	@CustID INT ,
	@MatchID 	INT, 
	@StakeCondition TINYINT = 1,
	@Stake MONEY = 0
AS
 
/*
Created: 20190307@Sophia
Task : CN88 - Wager Account of Total Bet Outright: Member
DB: DB042.bodb02
Original:

Revisions:
    - 20190307@Sophia: initial SP [Redmine: #109693] 
	
Param's Explanation:
	- @StakeCondition 	= 0 :  =
						= 1 :  >  (default)
						= 2 :  < 
	 
	- @CustID : AgentId
*/
BEGIN
	SET NOCOUNT ON
	
	SELECT  C.CustID,C.Username, C.Firstname, A.Wager, A.Stake										
	FROM  (
			SELECT 
				b.CustId,
				COUNT(b.TransId) AS Wager,  
				SUM (b.Stake) AS Stake 				
			FROM bettrans b WITH (NOLOCK)
				INNER JOIN outright o WITH (NOLOCK) ON o.orid = b.matchid 	 
			WHERE  	
				b.recommend = @CustId 
				AND b.statusID IN (0,1) 
				AND b.bettype = 10  
				AND (
						(@StakeCondition = 0 AND b.Stake = @Stake) 
						OR (@StakeCondition = 1 AND b.Stake > @Stake)
						OR (@StakeCondition = 2 AND b.Stake < @Stake)
					)				
				AND b.MatchID = @MatchID
			GROUP BY b.CustId
			) A
		INNER JOIN bodb02.dbo.Customer c WITH (NOLOCK) 
				ON c.CustId = A.CustID
		WHERE c.RoleID = 1
	
	
	 
END
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_WagerAccount_Outright_Member] TO [bodbDownlineNet]
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_WagerAccount_Outright_Member] TO [bodbDownlineNetView]
GO 