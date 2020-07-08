/*<info serverAlias="DBPRO-bodb02"></info>*/

USE [bodb02]
GO

/*
	Created: 20200708@Malcolm
	DB: DBPRO.bodb02
	Task: Support to update Accounting Period
	Redmine: #135881
*/


UPDATE  t 
SET t.ToDate = '20200809'
FROM CS_AccountingPeriod t
WHERE t.Year = 2020 AND t.PeriodId = 4 

UPDATE  t 
SET t.FromDate = NULL,
    t.ToDate   = NULL
FROM CS_AccountingPeriod t
WHERE t.Year = 2020 AND t.PeriodId = 8