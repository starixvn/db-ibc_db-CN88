/*<info serverAlias="DBPRO-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_AccountingPeriod_Sel]
AS

/*
	Created: 20190214@Percy
	DB: DBPRO.bodb02
	Task: Get Accounting Period

	Revisions:
		- 20190214@Percy: Initialize SP [RedmineID: #105338]
*/

BEGIN
	SELECT [Year], PeriodId, FromDate, ToDate
	FROM dbo.CS_AccountingPeriod WITH (NOLOCK)
	ORDER BY [Year], PeriodId
END
GO