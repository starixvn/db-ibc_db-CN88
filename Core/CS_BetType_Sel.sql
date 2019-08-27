/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_BetType_Sel]
AS

/*
	Created: 20190214@Percy
	DB: DBAGE.bodb02
	Task: Get Bet Type List

	Revisions:
		- 20190214@Percy: Initialize SP [RedmineID: #105338]
		- 20190515@Sophia: Add SportTypeGroup = 0 [RedmineID: #109521]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @isTest BIT
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	---- SportTypeGroup = 0 will get all BettypeGroup 
	SELECT DISTINCT 0 AS SportTypeGroup, sbm.BettypeGroup, b.typenamee AS TypeName
	FROM dbo.BetType b WITH (NOLOCK)
		INNER JOIN dbo.CS_SportBettypeMatrix sbm WITH (NOLOCK) ON b.TypeId = sbm.BettypeGroup
	WHERE sbm.Enabled = 1 AND sbm.IsTest <= @isTest

	UNION ALL 
	
	SELECT DISTINCT sbm.SportTypeGroup, sbm.BettypeGroup, b.typenamee AS TypeName
	FROM dbo.BetType b WITH (NOLOCK)
		INNER JOIN dbo.CS_SportBettypeMatrix sbm WITH (NOLOCK) ON b.TypeId = sbm.BettypeGroup
	WHERE sbm.Enabled = 1 AND sbm.IsTest <= @isTest
	
	
END
GO