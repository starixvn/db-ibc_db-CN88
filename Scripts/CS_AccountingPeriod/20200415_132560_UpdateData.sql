USE [bodb02]
GO

/*
	Created: 20200415@Malcolm
	DB: DBPRO.bodb02
	Task: Support to add more Accounting Period
	Redmine: #132560
*/


UPDATE  t 
SET t.ToDate = '20200503'
FROM CS_AccountingPeriod t
WHERE t.Year = 2020 AND t.PeriodId = 4 

UPDATE  t 
SET t.FromDate = '20200504'
FROM CS_AccountingPeriod t
WHERE t.Year = 2020 AND t.PeriodId = 5