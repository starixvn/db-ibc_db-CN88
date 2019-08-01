/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" isFunction="0"></info>*/	
USE bodb02
GO 

ALTER PROCEDURE [dbo].[CS_TotalBets_WagerAccount_Outright_Agent]
	@CustID			INT,
	@SubAccId		INT = 0,
	@IsAllDownline	BIT = 1,
	@MatchID		INT,
	@StakeCondition TINYINT = 1,
	@Stake			MONEY = 0 
AS

/*
	Created: 20190307@Sophia
	Task: CN88 Agent Wager Account of Total Bet Outright 
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
	
		- @CustID : MasterID
*/
BEGIN
	SET NOCOUNT ON

	/* ===== Get downline list by Sub Account ==== */
	DECLARE @Downlines TABLE (DownlineId INT)

	IF ISNULL(@SubAccId, 0) <> 0 AND ISNULL(@IsAllDownline, 0) = 0
	BEGIN
		INSERT INTO @Downlines (DownlineId)
		SELECT DownlineId FROM dbo.CS_f_GetDownlineBySubAcc(@SubAccId)
	END
	/* ===== End Get downline list by Sub Account ==== */
	
	SELECT  C.CustID, C.Username, C.Firstname, A.Wager, A.Stake										
	FROM  (
			SELECT 
				b.recommend,
				COUNT(b.TransId) AS Wager,  
				SUM (b.Stake) AS Stake 				
			FROM bettrans b WITH (NOLOCK)	 
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
				AND b.matchID = @MatchID 
			GROUP BY b.recommend
			) A
		INNER JOIN bodb02.dbo.Customer c WITH (NOLOCK) 
				ON c.CustId = A.recommend
		WHERE c.RoleID = 2
END
GO