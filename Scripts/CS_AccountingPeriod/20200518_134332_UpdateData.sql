/*<info serverAlias="DBPRO-bodb02" executers="" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

/*
	Created: 10100518@Malcolm
	DB: DBPRO.bodb02
	Task: Support to update Accounting Period
	Redmine: #134332
*/


UPDATE  t 
SET t.ToDate = '20200621'
FROM CS_AccountingPeriod t
WHERE t.Year = 2020 AND t.PeriodId = 4 

UPDATE  t 
SET t.FromDate = NULL,
    t.ToDate   = NULL
FROM CS_AccountingPeriod t
WHERE t.Year = 2020 AND t.PeriodId = 6

