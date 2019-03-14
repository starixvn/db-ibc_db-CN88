/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0"></info>*/	
USE bodb02
GO 

ALTER PROCEDURE [dbo].[CS_TotalBets_WagerAccount_Outright_Master]
	@CustID INT ,
	@MatchID INT,  
	@StakeCondition TINYINT = 1,
	@Stake MONEY = 0 
AS
 
/*
Created: 20190307@Sophia
Task : CN88 Agent Wager Account of Total Bet Outright 
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
	 
	
	SELECT  C.CustID, C.Username, C.Firstname, A.Wager, A.Stake										
	FROM  (
			SELECT 
				b.mrecommend,
				COUNT(b.TransId) AS Wager,  
				SUM (b.Stake) AS Stake 				
			FROM bettrans b WITH (NOLOCK)				
			WHERE  	
				b.srecommend = @CustId 
				AND b.statusID IN (0,1) 				 
				AND (
						(@StakeCondition = 0 AND b.Stake = @Stake) 
						OR (@StakeCondition = 1 AND b.Stake > @Stake)
						OR (@StakeCondition = 2 AND b.Stake < @Stake)
					)				
				AND b.MatchID = @MatchID
			GROUP BY b.mrecommend
			) A
		INNER JOIN bodb02.dbo.Customer c WITH (NOLOCK) 
				ON c.CustId = A.mrecommend
		WHERE c.RoleID = 3
	
	
	 
END
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_WagerAccount_Outright_Master] TO [bodbDownlineNet]
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_WagerAccount_Outright_Master] TO [bodbDownlineNetView]
GO 