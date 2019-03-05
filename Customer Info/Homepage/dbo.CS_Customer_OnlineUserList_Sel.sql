/*<info serverAlias="DBONUSER-ON_USER" executers="bodbDownlineNet, bodbDownlineNetView" viewers="" isFunction="0"></info>*/

ALTER PROCEDURE [dbo].[CS_Customer_OnlineUserList_Sel]
	@CustId INT,
	@pageSize INT = 50,
	@pageIndex INT = 0,
	@totalPages INT = 0 OUTPUT
AS
/*
	Created: 20190304@Johnson
	DB: DBONUSER.ON_USER
	Task: get online users list member level only

	Revisions:
		- 20190304@Johnson: Initialize SP [RedmineID: #105338]
*/

BEGIN
	SET NOCOUNT ON;
	
	DECLARE @roleid INT
	CREATE TABLE #tblOnlineList (custid INT, username VARCHAR(50), Name NVARCHAR(50), lastlogin DATETIME)
	
	SELECT @roleid = roleid
	FROM bodb02.dbo.custinfo WITH(NOLOCK)
	WHERE custid = @custid
	
	IF @roleid = 4
	BEGIN
		INSERT INTO #tblOnlineList(custid,username,name,lastlogin)
		SELECT c.custid, username, firstname, lastlogged
		FROM bodb02.dbo.customer c WITH(NOLOCK)
			INNER JOIN dbo.On_user o WITH(NOLOCK) ON c.custid = o.custid
		WHERE srecommend = @custid 
			AND roleid = 1
			AND o.iskickedout = 0
	END
	ELSE IF @roleid = 3
	BEGIN
		INSERT INTO #tblOnlineList(custid,username,name,lastlogin)
		SELECT c.custid, username, firstname, lastlogged
		FROM bodb02.dbo.customer c WITH(NOLOCK)
			INNER JOIN dbo.On_user o WITH(NOLOCK) ON c.custid = o.custid
		WHERE mrecommend = @custid 
			AND roleid = 1
			AND o.iskickedout = 0
	END
	ELSE IF @roleid = 2
	BEGIN
		INSERT INTO #tblOnlineList(custid,username,name,lastlogin)
		SELECT c.custid, c.username, firstname, lastlogged
		FROM bodb02.dbo.customer c WITH(NOLOCK)
			INNER JOIN bodb02.dbo.custinfo ci WITH(NOLOCK) ON ci.custid = c.custid
			INNER JOIN dbo.On_user o WITH(NOLOCK) ON c.custid = o.custid
		WHERE ci.recommend = @custid 
			AND ci.roleid = 1
			AND o.iskickedout = 0
	END
	
	DECLARE @RowCount int, @RowStart int, @RowEnd int  
	SELECT @PageIndex = @PageIndex - 1, 
		@RowStart = @PageSize * @PageIndex + 1, 
		@RowEnd = @RowStart + @PageSize - 1   

	SELECT @TotalPages = count(c.custid),@TotalPages=@TotalPages/@PageSize + CASE WHEN @TotalPages%@PageSize > 0 THEN 1 ELSE 0 END 
	FROM #tblOnlineList c
	
	SELECT custid,username,name,lastlogin
	FROM (
		SELECT *, ROW_NUMBER() OVER(ORDER BY LastLogin) rn 
		FROM #tblOnlineList
	)t
	WHERE rn BETWEEN @RowStart AND @RowEnd
END