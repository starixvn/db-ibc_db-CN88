USE [bodb02]
GO

/*
	Created: 20200221@Malcolm
	DB: DBPRO.bodb02
	Task: Support to add more Accounting Period
	Redmine: #128964
*/

INSERT INTO CS_AccountingPeriod(Year,PeriodId,FromDate,ToDate)
VALUES (2020,5,'20200420','20200524'),
       (2020,6,'20200525','20200621'),
	   (2020,7,'20200622','20200712')