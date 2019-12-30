/*<info serverAlias="DBPRO-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_AccountingPeriod_Sel]
AS

/*
	Created: 20191230@Sophia
	DB: DBPRO.bodb02
	Task: Get EB - dropdown Period

	Revisions:
		- 20191230@Sophia: Initialize SP [RedmineID: #126316]
*/

BEGIN
	SELECT [Year], PeriodId, FromDate, ToDate
	FROM dbo.CS_AccountingPeriod WITH (NOLOCK)
	ORDER BY [Year], PeriodId
END
GO