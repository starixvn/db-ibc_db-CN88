/*
	Created: 20190220@Percy
	DB: DBPRO.bodb02
	Task: Initilize data of CS_SportBettypeMatrix

		SportTypeGroup			- SportType
		1: Soccer				- 1
		2: Basketball/Football	- 2,3
		3: Tennis				- 5
		4: Volleyball			- 6
		5: Baseball				- 8
		6: Other Sports			- others, exclude 99 (dummy sport for setting)
		7: Badminton			- 9
		8: Table Tennis			- 18
		9: Snooker/Pool			- 7
		10: Parlay				- all sports have bettype in (9,29)
*/
-- DBPRO
USE [bodb02]
GO

/*
DELETE FROM dbo.CS_SportBettypeMatrix
GO
*/

INSERT INTO dbo.CS_SportBettypeMatrix (SportType, Bettype, IsLive, ProductID, Enabled, IsTest, EventType, SubProduct, RefTable, SportTypeGroup)
SELECT DISTINCT SportType, CASE WHEN Bettype = 9 THEN 29 ELSE BetType END, IsLive, ProductID, Enabled, IsTest, EventType, SubProduct, RefTable
		,CASE	WHEN BetType IN (9, 29) THEN 9
				WHEN SportType = 1 THEN 1
				WHEN SportType IN (2,3) THEN 2
				WHEN SportType = 9 THEN 6
				WHEN SportType = 5 THEN 3
				WHEN SportType = 6 THEN 4
				WHEN SportType = 7 THEN 8
				WHEN SportType = 8 THEN 5
				WHEN SportType = 18 THEN 7
				ELSE 10 END AS SportTypeGroup
FROM dbo.SportBettypeMatrix WITH (NOLOCK)
WHERE ProductId = 1
	AND (SubProduct = '' OR SubProduct IN ('Bet Builder','Betradar','SS'))
	AND SportType <> 99
GO

UPDATE sbm WITH (ROWLOCK, UPDLOCK)
SET sbm.BetTypeGroup = ISNULL(f.GroupTypeId, sbm.BetType)
FROM dbo.CS_SportBettypeMatrix sbm
	LEFT JOIN dbo.f_GroupBettype() f ON sbm.BetType = f.Bettype
GO