/*<info serverAlias="DBAGE-bodb02,DB042-bodb02" selecters="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="1" isNested="1"></info>*/
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
		- 20190328@Percy: Add Number Game/Happy 5, Keno/Lottery, Virtual Sports/Virtual Sports 2 [RedmineID: #109521]

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
			,(11, 1010) -- Number Game/Happy 5
			,(12, 1020) -- Keno/Lottery
			,(13, 1030) -- Virtual Sports (include Virtual Sports 2)
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
			,(11, 1010) -- Number Game/Happy 5
			,(12, 1020) -- Keno/Lottery
			,(13, 1030) -- Virtual Sports (include Virtual Sports 2)
	) AS B (SportTypeGroup, OrderId)
	WHERE @TypeId = 2 -- Total Bets
GO