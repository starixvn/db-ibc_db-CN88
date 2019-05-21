/*<info serverAlias="DBAGE-bodb02,DBEXT-bodb02,DBACC-bodb02,DBTXN-bodb02,DB042-bodb02" selecters="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="1" isNested="0"></info>*/
USE [bodb02]
GO

ALTER FUNCTION [dbo].[CS_f_BettypeMatrix_Sel]
(
	@ProductID			SMALLINT = 0
	,@SportTypeGroup	SMALLINT = 0
	,@BettypeGroup		SMALLINT = 0
	,@IsTest			BIT		 = 0
) 
/*
	Creator: Sophia
	Date: 20190225
	Task: Get Bettype Matrix for CN88 
	DB: DBAGE.bodb02, DBEXT.bodb02, DBACC.bodb02, DBPRO.bodb02,  DBTXN.bodb02, DB042.bodb02
		
	Revisions: 
		- 20190225@Sophia: Create new [RedmineID: #105660]
		- 20190520@Percy: Return BetTypeGroup [RedmineID: #113849]

	Paramters Explanation:
 		@ProductID, @SportType, @BetType, @SportTypeGroup
			0	: get all
			<>0 : check condition
		@IsLive : check paramer
			0	: None-live
			1	: Live
			2	: None-live & Live
		@ProductPrefix:
			''  : get all
			<>'': Check ProductPrefix column on dbo.Product table
		@IsTest:
			1: Get all products and bettypes
			0: Get only products and bettypes which are not being tested
*/

RETURNS TABLE
RETURN
SELECT DISTINCT
	 ma.ProductID
	,ma.BetTypeGroup
	,ma.BetType
	,ma.EventType
	,ma.SubProduct
	,ma.RefTable
	,p.CasinoType
	,p.ProductPrefix
FROM
	dbo.CS_SportBettypeMatrix ma WITH(NOLOCK)
	INNER JOIN dbo.Products p WITH(NOLOCK) ON p.ProductID = ma.ProductID
WHERE   (@ProductID		= 0  OR  ma.ProductID	= @ProductID)
	AND (@SportTypeGroup= 0  OR  ma.SportTypeGroup = @SportTypeGroup)
	AND (@BettypeGroup	= 0  OR  ma.BettypeGroup = @BettypeGroup)
	AND (ma.IsTest <= @IsTest)
	AND (ma.Enabled = 1)
GO