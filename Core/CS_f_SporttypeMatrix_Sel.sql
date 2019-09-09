/*<info serverAlias="DBAGE-bodb02,DBEXT-bodb02,DBACC-bodb02,DBTXN-bodb02,DB042-bodb02" selecters="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="1" isNested="1"></info>*/
ALTER FUNCTION [dbo].[CS_f_SporttypeMatrix_Sel]
(
	@ProductID			SMALLINT		= 0
	,@SportTypeGroups	VARCHAR(MAX)	= '0'
	,@BettypeGroup		SMALLINT		= 0
	,@IsTest			BIT				= 0
) 
/*
	Creator: Sophia
	Date: 20190225
	Task: Get SportType Matrix for CN88 
	DB: DBAGE.bodb02, DBEXT.bodb02, DBACC.bodb02, DBPRO.bodb02, DBTXN.bodb02, DB042.bodb02
		
	Revisions: 
		- 20190225@Sophia: Create new [RedmineID: #105660]
		- 20190520@Percy: Return SportTypeGroup [RedmineID: #113849]
		- 20190821@Percy: Change single SportTypeGroup to multiple [RedmineID: #118833]

	Paramters Explanation:
 		@ProductID, @BetTypeGroup, @SportTypeGroup
			0	: get all
			<>0 : check condition		
		@IsTest:
			1: Get all products and bettypes
			0: Get only products and bettypes which are not being tested
*/

RETURNS TABLE
RETURN
SELECT DISTINCT
	ma.SportTypeGroup
	,CASE WHEN ma.Bettype = 29 THEN 0 ELSE ma.SportType END AS SportType
	,ma.ProductID
	,p.CasinoType
	,p.ProductPrefix
FROM
	dbo.CS_SportBettypeMatrix ma WITH(NOLOCK)
	INNER JOIN dbo.Products p WITH(NOLOCK) ON p.ProductID = ma.ProductID
WHERE   (@ProductID = 0			OR ma.ProductID	= @ProductID)
	AND (@SportTypeGroups = '0' OR ',' + @SportTypeGroups + ',' LIKE '%,' + CONVERT(VARCHAR(10), ma.SportTypeGroup) + ',%')
	AND (@BettypeGroup	= 0		OR ma.BettypeGroup = @BettypeGroup)
	AND (ma.IsTest <= @IsTest)
GO