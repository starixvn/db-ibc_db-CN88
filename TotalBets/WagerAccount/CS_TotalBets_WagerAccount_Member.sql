/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0"></info>*/	
USE bodb02
GO 

CREATE PROCEDURE [dbo].[CS_TotalBets_WagerAccount_Member]
	@CustID INT ,
	@SporttypeGroup INT = 0,
	@LeagueId INT = 0,
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
	- @PossType : 
				= 0:	Full Percentage
				= 1:	Company %: Shown on SMA
				= 2:	SMA %: Shown on SMA
				= 3:	MA%: Shown on SMA, MA
				= 4:	Agent%: Shown on SMA, MA, Agent
				= 5:	SMA + MA + Agent%: Shown on SMA
				= 6:	SMA + MA %: Shown on SMA
				= 7:	MA + Agent %: Shown on SMA, MA
*/
BEGIN
	SET NOCOUNT ON

	------ Check SP Version
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	--- Get Sporttype
	
	DECLARE @SporttypeList AS TABLE (Sporttype SMALLINT PRIMARY KEY, ProductID INT)	
		 
	INSERT INTO @SporttypeList
	SELECT DISTINCT Sporttype, ProductID FROM bodb02.dbo.CS_f_SporttypeMatrix_Sel (0, @SporttypeGroup, 0, @isTest)	
	
	SELECT  C.Username, C.Firstname, A.Wager, A.Stake										
	FROM  (
			SELECT 
				b.CustId,
				COUNT(b.TransId) AS Wager,  
				SUM (b.Stake) AS Stake 				
			FROM bettrans b WITH (NOLOCK)
				INNER JOIN outright o WITH (NOLOCK) ON o.orid = b.matchid 	 
			WHERE  	
				b.CustId = @CustId 
				AND b.statusID IN (0,1) 
				AND b.bettype = 10  
				AND (
						(@StakeCondition = 0 AND b.Stake = @Stake) 
						OR (@StakeCondition = 1 AND b.Stake > @Stake)
						OR (@StakeCondition = 2 AND b.Stake < @Stake)
					)				
				AND (EXISTS (SELECT 1 
							FROM dbo.League l WITH (NOLOCK) 
							WHERE l.LeagueId = o.LeagueId 
								  AND l.sporttype IN (SELECT sporttype FROM @SporttypeList)  
								  AND l.isTest <= @isTest
								  AND (l.leagueid = @LeagueId OR @leagueid = 0) 
							)
					)
				AND (o.leagueid = @LeagueId OR @leagueid = 0) 
				AND o.oddsstatus IN ('Running','closed','suspend', 'closePrice')
				AND o.kickofftime > CURRENT_TIMESTAMP
			GROUP BY b.CustId
			) A
		INNER JOIN bodb02.dbo.Customer c WITH (NOLOCK) 
				ON c.CustId = A.CustID
		WHERE c.RoleID = 1
	
	
	 
END
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_WagerAccount_Member] TO [bodbDownlineNet]
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_WagerAccount_Member] TO [bodbDownlineNetView]
GO 