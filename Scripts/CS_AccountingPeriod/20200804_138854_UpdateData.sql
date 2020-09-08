/*<info serverAlias="DBPRO-bodb02"></info>*/

USE [bodb02]
GO

/*
	Created: 20200804@Malcolm
	DB: DBPRO.bodb02
	Task: Support to update Accounting Period
	Redmine: #138854 
*/


UPDATE  t 
SET t.ToDate = '20201004'
FROM CS_AccountingPeriod t
WHERE t.Year = 2020 AND t.PeriodId = 4 

UPDATE  t 
SET t.FromDate = NULL,
    t.ToDate   = NULL
FROM CS_AccountingPeriod t
WHERE t.Year = 2020 AND t.PeriodId IN (9, 10)

