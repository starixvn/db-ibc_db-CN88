/*<info serverAlias="DBONUSER-ON_USER" executers="bodbDownlineNet, bodbDownlineNetView" viewers="" isFunction="0"></info>*/

ALTER PROCEDURE [dbo].[CS_Customer_TotalOnlineUser_Sel]
	@CustId INT
AS
/*
	Created: 20190304@Johnson
	DB: DBONUSER.ON_USER
	Task: count total online users member level only

	Revisions:
		- 20190304@Johnson: Initialize SP [RedmineID: #105338]
*/

BEGIN
	SET NOCOUNT ON
	
	DECLARE @cntOnUsers INT,
			@roleid TINYINT
			
	SELECT @roleid = roleid
	FROM bodb02.dbo.custinfo WITH(NOLOCK)
	WHERE custid = @custid
	
	IF @roleid = 4
	BEGIN
		SELECT @cntOnUsers = count(1)
		FROM bodb02.dbo.custinfo ci WITH(NOLOCK)
			INNER JOIN dbo.On_user o WITH(NOLOCK) ON ci.custid = o.custid
		WHERE srecommend = @custid 
			AND roleid = 1
			AND o.iskickedout = 0
	END
	ELSE IF @roleid = 3
	BEGIN
		SELECT @cntOnUsers = count(1)
		FROM bodb02.dbo.custinfo ci WITH(NOLOCK)
			INNER JOIN dbo.On_user o WITH(NOLOCK) ON ci.custid = o.custid
		WHERE mrecommend = @custid 
			AND roleid = 1
			AND o.iskickedout = 0
	END
	ELSE IF @roleid = 2
	BEGIN
		SELECT @cntOnUsers = count(1)
		FROM bodb02.dbo.custinfo ci WITH(NOLOCK)
			INNER JOIN dbo.On_user o WITH(NOLOCK) ON ci.custid = o.custid
		WHERE recommend = @custid 
			AND roleid = 1
			AND o.iskickedout = 0
	END
	
	SELECT ISNULL(@cntOnUsers,0) as cntOnUsers
END	