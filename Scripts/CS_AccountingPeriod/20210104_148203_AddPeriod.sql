/*<info serverAlias="DBPRO-bodb02"></info>*/

USE [bodb02]
GO

/*
	Created: 20200104@Malcolm
	DB: DBPRO.bodb02
	Task: Support to add Accounting Period
	Redmine: #148203
*/


INSERT INTO dbo.CS_AccountingPeriod (Year, PeriodId, FromDate, ToDate)
VALUES (2021, 1, '20210104', '20211231')

