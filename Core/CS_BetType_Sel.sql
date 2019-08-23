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
		- 20190821@Percy: Remove SportTypeGroup = 0, Return ProductID = 1 for Sportsbook [RedmineID: #118833]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @isTest BIT
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	SELECT DISTINCT CASE WHEN sbm.ProductID = 1 THEN sbm.ProductID END AS ProductID, sbm.SportTypeGroup, sbm.BettypeGroup, b.typenamee AS TypeName
	FROM dbo.BetType b WITH (NOLOCK)
		INNER JOIN dbo.CS_SportBettypeMatrix sbm WITH (NOLOCK) ON b.TypeId = sbm.BettypeGroup
	WHERE sbm.IsTest <= @isTest
	ORDER BY sbm.BettypeGroup
END
GO