/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_SelArchiveDate]
AS

/*
	Created: 20190214@Sophia
	Task: Return archive date (MIN date of CS_SumWinloss table)
	DB: DBAGE.bodb02	
	Revisions:
		- 20190214@Sophia: Create new [RedmineID: #105660] 
	Param's Explanation:
		
			

*/

BEGIN
	SET NOCOUNT ON;
	
	SELECT  CONVERT(SMALLDATETIME, VValue) AS ArchiveDate
	FROM	dbo.SystemSettings
	WHERE   VName = 'CS_ArchiveDate'
	 

	SET NOCOUNT OFF

END
GO 
 