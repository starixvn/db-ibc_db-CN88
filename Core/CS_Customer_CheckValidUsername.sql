/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_Customer_CheckValidUsername]
	@Usernames			VARCHAR(MAX)
	,@RoleId			TINYINT = NULL
	,@InvalidUsernames	VARCHAR(MAX) = '' OUTPUT
AS

/*
	Created: 20190918@Percy
	DB: DBAGE.bodb02
	Task: CN88 - Check list of usernames is valid or not

	Revisions:
		- 20190918@Percy: Initialize SP [RedmineID: #119020]
		- 20200210@Malcolm : New group of Headline XPG - Changes on EB [RedmineID : #127209]

	Param's Explanation:
		@Usernames: List of usernames
		@RoleId:
			NULL: all customers
			0,1,2,3,4: headline, member, agent, master, super
		@InvalidUsernames: return list of invalid usernames
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @tblCustomer TABLE (Username VARCHAR(MAX), RoleId TINYINT)
	INSERT INTO @tblCustomer (Username)
	SELECT val
	FROM dbo.strSplit (@Usernames, ',')

	UPDATE t
	SET t.RoleId = c.roleid
	FROM @tblCustomer t
		INNER JOIN dbo.Customer c WITH (NOLOCK) ON t.Username = c.username AND c.site = 'CN88'

	SELECT @InvalidUsernames = NULL
	
	SELECT @InvalidUsernames = COALESCE(@InvalidUsernames + ',', '') + Username
	FROM @tblCustomer
	WHERE RoleId IS NULL OR RoleId <> @RoleId OR Username like 'XP%'

	SELECT @InvalidUsernames = ISNULL(@InvalidUsernames, '')
END
GO