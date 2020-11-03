/*<info serverAlias="DBPRO-bodb02"></info>*/

USE [bodb02]
GO

/*
	Created: 20200908@Malcolm
	DB: DBPRO.bodb02
	Task: Support to update Accounting Period
	Redmine: #141033 
*/


UPDATE  t 
SET t.ToDate = '20200906'
FROM CS_AccountingPeriod t
WHERE t.Year = 2020 AND t.PeriodId = 4 


UPDATE  t 
SET t.FromDate = '20200907', t.ToDate = '20201004'
FROM CS_AccountingPeriod t
WHERE t.Year = 2020 AND t.PeriodId = 5

UPDATE  t 
SET t.FromDate = '20201005', t.ToDate = '20201101'
FROM CS_AccountingPeriod t
WHERE t.Year = 2020 AND t.PeriodId = 6

UPDATE  t 
SET t.FromDate = '20201102', t.ToDate = '20201206'
FROM CS_AccountingPeriod t
WHERE t.Year = 2020 AND t.PeriodId = 7


UPDATE  t 
SET t.FromDate = '20201207', t.ToDate = '20210103'
FROM CS_AccountingPeriod t
WHERE t.Year = 2020 AND t.PeriodId = 8

UPDATE  t 
SET t.FromDate = NULL,
    t.ToDate   = NULL
FROM CS_AccountingPeriod t
WHERE t.Year = 2020 AND t.PeriodId IN (9, 10,11,12,13)

