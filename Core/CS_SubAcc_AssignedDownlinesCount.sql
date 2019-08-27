/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_SubAcc_AssignedDownlinesCount]
	@SubAccId INT = 0
AS

/*
	Created: 20190713@Percy
	DB: DBAGE.bodb02
	Task: CN88 - Sub Account - Get Assigned Accounts / Total Direct Downlines

	Revisions:
		- 20190713@Percy: Initialize SP [RedmineID: #116825]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @CustId INT, @RoleId TINYINT
			,@TotalAssignedAccounts INT
			,@TotalDirectDownlines	INT

	SELECT @TotalAssignedAccounts = COUNT(1)
	FROM dbo.CS_SubAccManagement WITH (NOLOCK)
	WHERE SubAccId = @SubAccId

	SELECT @CustId = c.custid, @RoleId = c.roleid
	FROM dbo.custSub cs WITH (NOLOCK)
		INNER JOIN dbo.Customer c WITH (NOLOCK) ON cs.custid = c.custid
	WHERE subaccid = @SubAccId

	IF @RoleId = 4
		SELECT @TotalDirectDownlines = COUNT(1)
		FROM dbo.Customer WITH (NOLOCK)
		WHERE srecommend = @CustId AND roleid = 3
	ELSE IF @RoleId = 3
		SELECT @TotalDirectDownlines = COUNT(1)
		FROM dbo.Customer WITH (NOLOCK)
		WHERE mrecommend = @CustId AND roleid = 2
	ELSE IF @RoleId = 2
		SELECT @TotalDirectDownlines = COUNT(1)
		FROM dbo.Customer WITH (NOLOCK)
		WHERE recommend = @CustId AND roleid = 1

	SELECT	@TotalAssignedAccounts AS TotalAssignedAccounts
			,@TotalDirectDownlines AS TotalDirectDownlines
END
GO