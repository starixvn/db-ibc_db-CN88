/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0"></info>*/	
USE bodb02
GO 

ALTER PROCEDURE [dbo].[CS_TotalBets_OutrightLeague_Sel]
	@SporttypeGroup INT = 0  
AS
 
/*
Created: 20190307@Sophia
Task : CN88 Retrieve Total Bet for outright - get list of League
DB: DB042.bodb02
Original:

Revisions:
    - 20190307@Sophia: initial SP [Redmine: #109693]
 
	
Param's Explanation:
• @custid: Super Agent ID
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
	

	SELECT l.leagueid		
	FROM dbo.League l WITH (NOLOCK)  
	WHERE EXISTS (  SELECT 1 
					FROM  dbo.outright o WITH (NOLOCK) 
					WHERE o.oddsstatus IN ('Running','closed','suspend', 'closePrice') AND l.leagueid = o.leagueid)
		AND l.sporttype IN (SELECT sporttype FROM @SporttypeList) 
		AND l.sporttype NOT IN (151,152,153) --- racing
		AND l.isTest <= @isTest
	
	
END
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_OutrightLeague_Sel] TO [bodbDownlineNet]
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_OutrightLeague_Sel] TO [bodbDownlineNetView]
GO 