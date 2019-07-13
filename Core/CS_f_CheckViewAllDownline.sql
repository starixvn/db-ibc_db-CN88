/*<info serverAlias="DBAGE-bodb02,DB042-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="1" isNested="1"></info>*/
USE bodb02
GO

ALTER FUNCTION [dbo].[CS_f_CheckViewAllDownline]
(
	@SubAccId	INT
)
RETURNS BIT
AS

/*
	Created: 20190713@Percy
	DB: DBAGE.bodb02, DB042.bodb02
	Task: Check sub account permission is get all downlines or not

	Revisions:
		- 20190713@Percy: Initialize function [RedmineID: #116825]
*/

BEGIN
	DECLARE @IsAllDownline BIT = 0

	IF @SubAccId = 0
		SELECT @IsAllDownline = 1
	ELSE
		SELECT @IsAllDownline = ISNULL(IsAllDownline, 0)
		FROM dbo.custSub WITH (NOLOCK)
		WHERE subaccid = @SubAccId

	RETURN @IsAllDownline
END
GO