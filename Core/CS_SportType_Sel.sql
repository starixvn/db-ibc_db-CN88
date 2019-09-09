/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_SportType_Sel]
AS

/*
	Created: 20190214@Percy
	DB: DBAGE.bodb02
	Task: Get Sports List

	Revisions:
		- 20190214@Percy: Initialize SP [RedmineID: #105660]
		- 20190328@Percy: Display Virtual Sports Group [RedmineID: #109521]
		- 20190510@Percy: Return ProductID (1 for SB, NULL for others) [RedmineID: #113849]
		- 20190719@Percy: Remove ProductID (support all Products) [RedmineID: #117101]
		- 20190821@Percy: Return ProductID (1 for SB, NULL for others) [RedmineID: #118833]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @isTest BIT
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	;WITH CTE_Sports AS (
		SELECT DISTINCT CASE WHEN sbm.ProductID = 1 THEN sbm.ProductID END AS ProductID, sbm.SportTypeGroup, sbm.SportType, s.SportName
		FROM dbo.CS_SportBettypeMatrix sbm WITH (NOLOCK)
			INNER JOIN dbo.Sports s WITH (NOLOCK) ON sbm.SportType = s.SportType
		WHERE IsTest <= @isTest
	)
	SELECT
		ProductID			= s.ProductID
		,SportTypeGroup		= s.SportTypeGroup
		,DisplaySport		= CASE
								WHEN s.SportTypeGroup = 99 THEN '99' -- Other Sports
								WHEN s.SportTypeGroup IN (9, 13) THEN '' -- Parlay + Virtual Sports
								ELSE STUFF((SELECT N',' + CONVERT(VARCHAR(5), SportType)
											FROM CTE_Sports
											WHERE SportTypeGroup = s.SportTypeGroup
											ORDER BY SportType
											FOR XML PATH('')), 1, 1, '') END
		,DisplaySportName	= CASE
								WHEN s.SportTypeGroup = 99 THEN 'Other Sports'
								WHEN s.SportTypeGroup = 9 THEN 'Parlay'
								WHEN s.SportTypeGroup = 13 THEN 'Virtual Sports'
								ELSE STUFF((SELECT N'/' + SportName
											FROM CTE_Sports
											WHERE SportTypeGroup = s.SportTypeGroup
											ORDER BY SportType
											FOR XML PATH('')), 1, 1, '') END
	FROM CTE_Sports AS s
		INNER JOIN dbo.CS_f_SportTypeGroup_OrderSel(1) f ON s.SportTypeGroup = f.SportTypeGroup
	GROUP BY s.ProductID, s.SportTypeGroup, f.OrderId
	ORDER BY f.OrderId
END
GO