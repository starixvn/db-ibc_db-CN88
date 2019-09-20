USE bodb_Summary
GO

/*
	Created: 20190809@Percy
	DB: DBSUM.bodb_Summary
	Task: New column HouseTurnover
*/

ALTER TABLE dbo.CS_SumWinloss
	ADD [HouseTurnover] [money] NULL
GO