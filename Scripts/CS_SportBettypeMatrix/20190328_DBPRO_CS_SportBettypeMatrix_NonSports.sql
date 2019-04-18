USE [bodb02]
GO

/*
	Created: 20190328@Percy
	DB: DBPRO.bodb02
	Task: Add Non-Sports: Keno, Lottery, Number Game (include Happy 5), Virtual Sport, Virtual Sports 2
*/

INSERT INTO dbo.CS_SportBettypeMatrix (SportType,BetType,IsLive,ProductID,Enabled,IsTest,EventType,SubProduct,RefTable,SportTypeGroup,BetTypeGroup)
SELECT DISTINCT SportType,s.BetType,IsLive,ProductID,Enabled,1 AS IsTest,EventType,SubProduct,RefTable
	,SportTypeGroup = CASE
						WHEN ProductId = 3 THEN 11 -- Number Game / Happy 5
						WHEN ProductId IN (8, 28) THEN 12 -- Keno / Lottery
						WHEN ProductId IN (5, 27) THEN 13 -- Virtual Sports / Virtual Sports 2
						END
	,BetTypeGroup = ISNULL(f.GroupTypeId, s.BetType)
FROM dbo.SportBettypeMatrix s WITH (NOLOCK)
	LEFT JOIN dbo.f_GroupBettype() f ON s.BetType = f.Bettype
WHERE ProductId IN (3,8,5,27,28)