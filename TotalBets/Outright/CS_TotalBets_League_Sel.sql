/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0"></info>*/	
USE bodb02
GO 

ALTER PROCEDURE [dbo].[CS_TotalBets_League_Sel]
	@SporttypeGroup INT = 0, 
	@Type TINYINT = 0 
AS
 
/*
Created: 20190307@Sophia
Task : CN88 - Total Bet - get list of League
DB: DB042.bodb02
Original:

Revisions:
    - 20190307@Sophia: initial SP [Redmine: #109693]
 
	
Param's Explanation:
	@Type: = 0: Match
		   = 1: Outright 

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
	
	IF @Type = 1
	BEGIN 
		SELECT l.leagueid		
		FROM dbo.League l WITH (NOLOCK)  
		WHERE EXISTS (  SELECT 1 
						FROM  dbo.outright o WITH (NOLOCK) 
						WHERE o.oddsstatus IN ('Running','closed','suspend', 'closePrice') AND l.leagueid = o.leagueid)
			AND l.sporttype IN (SELECT sporttype FROM @SporttypeList) 
			AND l.sporttype NOT IN (151,152,153) --- racing
			AND l.isTest <= @isTest
	END 
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
GRANT EXECUTE ON [dbo].[CS_TotalBets_League_Sel] TO [bodbDownlineNet]
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_League_Sel] TO [bodbDownlineNetView]
GO 