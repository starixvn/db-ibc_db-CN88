/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0"></info>*/	
USE bodb02
GO 

ALTER PROCEDURE [dbo].[CS_TotalBets_League_Sel]
	@SporttypeGroup INT = 0, 
	@Type TINYINT = 1
AS
 
/*
Created: 20190307@Sophia
Task : CN88 - Total Bet - get list of League
DB: DB042.bodb02
Original:

Revisions:
    - 20190307@Sophia: initial SP [Redmine: #109693]
	- 20190418@Sophia: SB only [Redmine: #109521]
 
	
Param's Explanation:
	@Type = 0:  All, 
		  = 1: In-play, 
		  = 2: Today, 
		  = 3: Early,
		  = 4: Outright
		  = 5: Started

*/
BEGIN
	SET NOCOUNT ON

	------ Check SP Version
	DECLARE @isTest BIT = 0
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	--- Get Sporttype
	DECLARE @SporttypeList VARCHAR(MAX)	
	SELECT @SporttypeList = COALESCE (@SporttypeList + ',', '') + CONVERT(VARCHAR(5),Sporttype) FROM bodb02.dbo.CS_f_SporttypeMatrix_Sel (1, @SporttypeGroup, 0, @isTest)	
		
	SELECT DISTINCT LeagueID from dbo.CS_f_TotalBets_Event_Sel (@Type, @isTest, 0, @SporttypeList) 
	 
	
END
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_League_Sel] TO [bodbDownlineNet]
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_League_Sel] TO [bodbDownlineNetView]
GO 