/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" isFunction="0"></info>*/	
USE bodb02
GO 

ALTER PROCEDURE [dbo].[CS_TotalBets_Bettype_Started_Agent]
	@CustID			INT,
	@SubAccId		INT = 0,
	@IsAllDownline	BIT = 1,
	@MatchId		INT = 0,
	@StakeCondition TINYINT = 1,
	@Stake			MONEY = 0,
	@PossType		TINYINT = 0,
	@IsLive			TINYINT = 2
AS

/*
	Created: 20190419@Sophia
	Task: CN88 - Total Bet drilldown bettype from Started: Super view downline
	DB: DBAGE.bodb02
	Original:

	Revisions:
		- 20190419@Sophia: initial SP [Redmine: #112032]
		- 20190713@Percy: Add sub account - permission on downlines [RedmineID: #116825]
	
	Param's Explanation:
		- @SubAccId: sub account
		- @IsAllDownline: is view all downlines
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
		- @CustID = AgentID
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
 	
	SELECT  MatchID,
			B.BettypeGroup As BettypeGroup,
			CASE WHEN B.BettypeGroup IN (1,2,3,5,7,8,12,15,17,18,20,21,177,184) THEN Betteam ELSE '' END AS Betteam,
			Liveindicator,
			SUM(Wager) AS Wager,
			CASE @PossType WHEN 0 THEN SUM(Stake0)
						   WHEN 4 THEN SUM(Stake4)
			END	AS Stake										
	FROM  (
			SELECT
				MatchID,
				Bettype,
				Betteam,
				Liveindicator,
				COUNT(b.TransId) AS Wager,  				
				SUM (b.Stake) AS Stake0,
				SUM (b.Stake * (apositiontaking)) AS Stake4
			FROM bettrans b WITH (NOLOCK)				
			WHERE  	
				b.recommend = @CustId
				AND (@IsAllDownline = 1 OR EXISTS (SELECT 1 FROM @Downlines d WHERE b.custid = d.DownlineId))
				AND b.statusID IN (0,1,111,112,113) 		
				AND b.bettype <> 10				
				AND (
						(@StakeCondition = 0 AND b.Stake = @Stake) 
						OR (@StakeCondition = 1 AND b.Stake > @Stake)
						OR (@StakeCondition = 2 AND b.Stake < @Stake)
					)
				AND b.MatchID = @MatchID
				AND (	@IsLive = 2   --- all
						OR b.Liveindicator = @IsLive
					)
			GROUP BY
				b.MatchID,
				b.Bettype,
				b.Betteam,
				b.Liveindicator
			) A
			CROSS APPLY (SELECT Bettype, BettypeGroup FROM dbo.CS_f_BettypeGroupMatrix_Sel (0,0,A.Bettype,@Istest) WHERE BettypeGroup <> 10) B
	GROUP BY MatchID,
			B.BettypeGroup,
			CASE WHEN B.BettypeGroup IN (1,2,3,5,7,8,12,15,17,18,20,21,177,184) THEN Betteam ELSE '' END,
			Liveindicator
END
GO