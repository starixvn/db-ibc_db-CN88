/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_SportType_Sel]
AS

/*
	Created: 20190214@Percy
	DB: DBAGE.bodb02
	Task: Get Sports List

	Revisions:
		- 20190214@Percy: Initialize SP [RedmineID: #105338]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @isTest BIT
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	;WITH CTE_Sports AS (
		SELECT DISTINCT SportTypeGroup, SportType
		FROM dbo.CS_SportBettypeMatrix WITH (NOLOCK)
		WHERE IsTest <= @isTest
	)
	SELECT
		SportTypeGroup	= s.SportTypeGroup
		,DisplaySport	= CASE
							WHEN s.SportTypeGroup = 99 THEN '99' -- Other Sports
							WHEN s.SportTypeGroup = 9 THEN '' -- Parlay
							ELSE STUFF((SELECT N',' + CONVERT(VARCHAR(5), SportType) FROM CTE_Sports WHERE SportTypeGroup = s.SportTypeGroup FOR XML PATH('')), 1, 1, '') END
	FROM CTE_Sports AS s
	GROUP BY s.SportTypeGroup
END
GO