/*<info serverAlias="DBAGE-bodb02,DB042-bodb02" selecters="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="1" isNested="1"></info>*/
USE bodb02
GO

ALTER FUNCTION [dbo].[CS_f_GetDownlineBySubAcc]
(
	@SubAccId INT
)
RETURNS TABLE
AS

/*
	Created: 20190713@Percy
	DB: DBAGE.bodb02
	Task: Get direct downlines by Sub Account

	Revisions:
		- 20190713@Percy: Initialize function [RedmineID: #116825]
*/

RETURN
	SELECT DownlineId
	FROM dbo.CS_SubAccManagement WITH (NOLOCK)
	WHERE SubAccId = @SubAccId
GO