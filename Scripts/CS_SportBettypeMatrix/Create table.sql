/*
	Created: 20190220@Percy
	DB: DBPRO.bodb02, DB042.bodb02, DB052.bodb02, DB053.bodb02, DB06.bodb02, DBTXN.bodb02
	Task: CN88 - Create new table CS_SportBettypeMatrix
*/

-- Script create table
USE [bodb02]
GO

CREATE TABLE dbo.CS_SportBettypeMatrix
(
	SportType		SMALLINT NOT NULL,
	Bettype			SMALLINT NOT NULL,
	IsLive			BIT NOT NULL,
	ProductID		TINYINT,
	Enabled			BIT,
	IsTest			BIT,
	EventType		TINYINT,
	SubProduct		VARCHAR(500),
	RefTable		TINYINT,
	SportTypeGroup	SMALLINT,
	BetTypeGroup	SMALLINT
	CONSTRAINT [PK_CS_SportBettypeMatrix] PRIMARY KEY CLUSTERED
	(
		SportType ASC,
		Bettype	ASC,
		IsLive ASC
	) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [DATA]
) ON [DATA]

-- Add table into publication on DBPRO: [bodb02]: Odds_Info