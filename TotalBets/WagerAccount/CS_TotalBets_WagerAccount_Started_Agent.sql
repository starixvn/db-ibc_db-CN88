/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" isFunction="0"></info>*/	
ALTER PROCEDURE [dbo].[CS_TotalBets_WagerAccount_Started_Agent]
	@CustID			INT,
	@SubAccId		INT = 0,
	@IsAllDownline	BIT = 1,
	@MatchId		INT = 0,
	@BettypeGroup	SMALLINT = 0,
	@Betteam		NVARCHAR(10) = '',
	@LiveIndicator	BIT = 0,
	@StakeCondition TINYINT = 1,
	@Stake			MONEY = 0
AS

/*
	Created: 20190419@Sophia 
	Task: CN88 Agent Wager Account of Total Bet - by Started
	DB: DBAGE.bodb02

	Revisions:
		- 20190419@Sophia: initial SP [Redmine: #112032]
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
	------ Check SP Version
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	/* ===== Get downline list by Sub Account ==== */
	DECLARE @Downlines TABLE (DownlineId INT)

	IF ISNULL(@SubAccId, 0) <> 0 AND ISNULL(@IsAllDownline, 0) = 0
	BEGIN
		INSERT INTO @Downlines (DownlineId)
		SELECT DownlineId FROM dbo.CS_f_GetDownlineBySubAcc(@SubAccId)
	END
	/* ===== End Get downline list by Sub Account ==== */

	--- Get Bettype
	DECLARE @BettypeList AS TABLE (bettype SMALLINT )
	INSERT INTO @BettypeList (bettype)	
	SELECT Bettype FROM bodb02.dbo.CS_f_BettypeMatrix_Sel (1, 0, @BettypeGroup, @isTest)	
	
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
				AND b.statusID IN (0,1,111,112,113) 
				AND b.bettype IN (Select Bettype FROM @BettypeList)
				AND (b.betteam = @betteam OR @betteam = '')
				AND b.MatchID = @MatchID
				AND b.LiveIndicator = @LiveIndicator
				AND (
						(@StakeCondition = 0 AND b.Stake = @Stake) 
						OR (@StakeCondition = 1 AND b.Stake > @Stake)
						OR (@StakeCondition = 2 AND b.Stake < @Stake)
					)			
			GROUP BY b.recommend
			) A
		INNER JOIN bodb02.dbo.Customer c WITH (NOLOCK) 
				ON c.CustId = A.recommend
		WHERE c.RoleID = 2
END
GO 