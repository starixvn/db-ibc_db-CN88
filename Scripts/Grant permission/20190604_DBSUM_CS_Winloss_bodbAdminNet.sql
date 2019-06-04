USE bodb_Summary
GO

/*
	Created: 20190604@Percy
	DB: DBSUM.bodb_Summary
	Task: Grant select permission
*/

GRANT SELECT ON dbo.CS_SumWinloss TO bodbAdminNet AS dbo
GO
GRANT SELECT ON dbo.CS_SumWinloss_Old TO bodbAdminNet AS dbo
GO