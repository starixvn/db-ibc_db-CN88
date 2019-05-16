USE [bodb02]
GO

/*
	Created: 20190328@Percy
	DB: DBPRO.bodb02
	Task:
		1. Add Non-Sports: Keno, Lottery, Number Game (include Happy 5), Virtual Sport, Virtual Sports 2
		2. Sportsbook: Add Bet Builder
*/

-- Non-Sports
UPDATE dbo.CS_SportBettypeMatrix WITH (ROWLOCK, UPDLOCK)
SET IsTest = 0
WHERE ProductId IN (3,8,5,27,28)
GO

-- Bet Builder
INSERT INTO dbo.CS_SportBettypeMatrix (SportType,BetType,IsLive,ProductID,Enabled,IsTest,EventType,SubProduct,RefTable,SportTypeGroup,BetTypeGroup)
VALUES (1, 38, 0, 1, 1, 0, 1, 'Bet Builder', 0, 1, 38)
GO