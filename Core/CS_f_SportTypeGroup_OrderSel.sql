/*<info serverAlias="DBAGE-bodb02,DB042-bodb02" selecters="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="1" isNested="1"></info>*/
USE [bodb02]
GO

ALTER FUNCTION [dbo].[CS_f_SportTypeGroup_OrderSel]
(
	@TypeId TINYINT
)
RETURNS TABLE
AS

/*
	Created: 20190307@Percy
	DB: DBAGE.bodb02, DB042.bodb02
	Task: Core function - Order SportTypeGroup on Report & Total Bets

	Revisions:
		- 20190307@Percy: Initialize function [RedmineID: #105660]

	Param's Explanation:
		@Type: 1 for Report, 2 for Total Bets
*/

RETURN
	SELECT SportTypeGroup, OrderId
	FROM
	(
		VALUES
			(1, 10) -- Soccer
			,(2, 20) -- Basketball/Football
			,(3, 30) -- Tennis
			,(4, 40) -- Volleyball
			,(5, 50) -- Baseball
			,(6, 60) -- Badminton
			,(7, 70) -- Table Tennis
			,(8, 80) -- Snooker
			,(9, 90) -- Parlay
			,(10, 100) -- E-Sports
			,(99, 990) -- Other Sports
	) AS A (SportTypeGroup, OrderId)
	WHERE @TypeId = 1 -- Report

	UNION ALL
	SELECT SportTypeGroup, OrderId
	FROM
	(
		VALUES
			(1, 10) -- Soccer
			,(2, 20) -- Basketball/Football
			,(3, 30) -- Tennis
			,(4, 40) -- Volleyball
			,(7, 50) -- Table Tennis
			,(6, 60) -- Badminton
			,(5, 70) -- Baseball
			,(8, 80) -- Snooker
			,(9, 90) -- Parlay
			,(10, 100) -- E-Sports
			,(99, 990) -- Other Sports
	) AS B (SportTypeGroup, OrderId)
	WHERE @TypeId = 2 -- Total Bets
GO