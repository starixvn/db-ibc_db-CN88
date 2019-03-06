/*<info serverAlias="DBCUST-CustDB" executers="bodbDownlineNet, bodbDownlineNetView" viewers="" isFunction="0"></info>*/

ALTER PROCEDURE [dbo].[CS_Customer_CheckBelonging_Sel]
	@SessionCustID INT, --uplineID	
	@custid INT = NULL,	
	@isActive BIT = 1 OUTPUT,	
	@username VARCHAR(30) = '' OUTPUT,
	@roleid TINYINT = 0 OUTPUT --0: not belonged to
AS
/*
	Created: 20190306@Johnson
	Task: check downline belonging for headline 
	DB: DBCUST/CustDB
	Original: 
		
	Revisions:
		- 20190306@Johnson: initial sp [redmine: #105338]
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @SessionRoleID TINYINT

	IF @SessionCustID IS NULL --Not check
	BEGIN
		SELECT @roleid = roleid
		FROM custinfo c WITH (NOLOCK)
		WHERE c.custid = @custid
		RETURN
	END


	SELECT	@SessionRoleID = roleid,
			@isActive = CASE WHEN closed = 1 OR Enabled = 0 THEN 0 ELSE 1 END
	FROM custinfo WITH(NOLOCK)
	WHERE custID = @SessionCustID

	IF ISNULL(@sessionRoleid ,0) = 0 RETURN

	SELECT	@roleid = roleid, @username = username		
	FROM custinfo c WITH (NOLOCK)
	WHERE c.custid = @custid
		AND
		(EXISTS (SELECT TOP 1 1 
				FROM CustSuper s WITH(NOLOCK) 
				WHERE s.custid = c.srecommend 
					AND s.uplineID = @SessionCustID
				)
			OR @SessionRoleID >= 5)

	SELECT	@roleid = ISNULL(@roleid, 0), 
			@isActive = ISNULL(@isActive,0
END