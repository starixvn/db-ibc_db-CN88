/*<info serverAlias="DBCUST-CustDB" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [CustDB]
GO

ALTER PROCEDURE [dbo].[CS_Customer_DownlineList_Sel]
	@CustId				INT,
	@DownlineUsername	NVARCHAR(50) = '',
	@SearchRoleId		TINYINT,
	@SearchUsername		NVARCHAR(50),
	@SearchStatusId		TINYINT = 0,
	@PageIndex			INT = 1,
	@PageSize			INT = 500,
	@TotalRows			INT = 0 OUTPUT
AS

/*
	Created: 20181218@Percy
	DB: DBCUST.CustDB
	Task: Member Information >> Downline List

	Revisions:
		- 20181218@Percy: Initialize SP [RedmineID: #105338]

	Param's Explanation:
		@CustId: SMA login
		@DownlineUsername: search downlines under @DownlineUsername, if search direct downline: no need
		@SearchRoleId:
			3: Master List (Super Login)
			2: Agent List (Super/Master Login)
			1: Member List (Super/Master/Agent Login)
		@SearchStatusId:
			0: All
			1: Open
			2: Suspended
			3: Closed
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @RoleId TINYINT
	SELECT  @RoleId = roleId FROM dbo.custInfo WITH (NOLOCK) WHERE custId = @custId

	DECLARE @tmpCustId INT
	
	IF @RoleId = 4 AND @SearchRoleId < 3
	BEGIN
		SELECT @tmpCustId = custid FROM dbo.custInfo WITH (NOLOCK)
		WHERE username = @DownlineUsername AND srecommend = @CustId AND roleId = @SearchRoleId + 1
	END
	ELSE IF @RoleId = 3 AND @SearchRoleId < 2
	BEGIN
		SELECT @tmpCustId = custid FROM dbo.custInfo WITH (NOLOCK)
		WHERE username = @DownlineUsername AND mrecommend = @CustId AND roleId = @SearchRoleId + 1
	END
	ELSE
	BEGIN
		SELECT @tmpCustId = @CustId
	END

	CREATE TABLE #CustInfo (custId INT, username NVARCHAR(50), credit MONEY, Status TINYINT, ClosedReason TINYINT)

	IF @SearchRoleId = 3
	BEGIN
		INSERT INTO #CustInfo (custId, username, credit, Status, ClosedReason)
		SELECT ci.custid, ci.username, ISNULL(ci.credit, 0),
				CASE	WHEN ISNULL(ci.reject, 0) = 0 AND ISNULL(ci.closed, 0) = 0 THEN 1 -- Open
						WHEN ISNULL(ci.reject, 0) = 1 AND ISNULL(ci.closed, 0) = 0 THEN 2 -- Suspended
						WHEN ISNULL(ci.closed, 0) = 1 THEN 3 -- Closed
				END,
				ISNULL(cl.ClosedReason, 0)
		FROM dbo.custInfo ci WITH (NOLOCK)
			INNER JOIN dbo.Customer cu WITH (NOLOCK) ON ci.custid = cu.custid
			LEFT JOIN dbo.CustLoginInfo cl WITH (NOLOCK) ON ci.custid = cl.custid
		WHERE ci.srecommend = @tmpCustId
			AND ci.roleId = 3
			AND (
				ci.username LIKE '%' + ISNULL(@SearchUsername, '') + '%'
				OR cu.firstname LIKE '%' + ISNULL(@SearchUsername, '') + '%'
			)
			AND (
				@SearchStatusId = 0
				OR (@SearchStatusId = 1 AND ISNULL(ci.reject, 0) = 0 AND ISNULL(ci.closed, 0) = 0)
				OR (@SearchStatusId = 2 AND ISNULL(ci.reject, 0) = 1 AND ISNULL(ci.closed, 0) = 0)
				OR (@SearchStatusId = 3 AND ISNULL(ci.closed, 0) = 1)
			)

		SELECT @TotalRows = @@ROWCOUNT
	END
	ELSE IF @SearchRoleId = 2
	BEGIN
		INSERT INTO #CustInfo (custId, username, credit, Status, ClosedReason)
		SELECT ci.custid, ci.username, ISNULL(ci.credit, 0),
				CASE	WHEN ISNULL(ci.reject, 0) = 0 AND ISNULL(ci.closed, 0) = 0 THEN 1 -- Open
						WHEN ISNULL(ci.reject, 0) = 1 AND ISNULL(ci.closed, 0) = 0 THEN 2 -- Suspended
						WHEN ISNULL(ci.closed, 0) = 1 THEN 3 -- Closed
				END,
				ISNULL(cl.ClosedReason, 0)
		FROM dbo.custInfo ci WITH (NOLOCK)
			INNER JOIN dbo.Customer cu WITH (NOLOCK) ON ci.custid = cu.custid
			LEFT JOIN dbo.CustLoginInfo cl WITH (NOLOCK) ON ci.custid = cl.custid
		WHERE ci.mrecommend = @tmpCustId
			AND ci.roleId = 2
			AND (
				ci.username LIKE '%' + ISNULL(@SearchUsername, '') + '%'
				OR cu.firstname LIKE '%' + ISNULL(@SearchUsername, '') + '%'
			)
			AND (
				@SearchStatusId = 0
				OR (@SearchStatusId = 1 AND ISNULL(ci.reject, 0) = 0 AND ISNULL(ci.closed, 0) = 0)
				OR (@SearchStatusId = 2 AND ISNULL(ci.reject, 0) = 1 AND ISNULL(ci.closed, 0) = 0)
				OR (@SearchStatusId = 3 AND ISNULL(ci.closed, 0) = 1)
			)

		SELECT @TotalRows = @@ROWCOUNT
	END
	ELSE IF @SearchRoleId = 1
	BEGIN
		INSERT INTO #CustInfo (custId, username, credit, Status, ClosedReason)
		SELECT ci.custid, ci.username, ISNULL(ci.credit, 0),
				CASE	WHEN ISNULL(ci.reject, 0) = 0 AND ISNULL(ci.closed, 0) = 0 THEN 1 -- Open
						WHEN ISNULL(ci.reject, 0) = 1 AND ISNULL(ci.closed, 0) = 0 THEN 2 -- Suspended
						WHEN ISNULL(ci.closed, 0) = 1 THEN 3 -- Closed
				END,
				ISNULL(cl.ClosedReason, 0)
		FROM dbo.custInfo ci WITH (NOLOCK)
			INNER JOIN dbo.Customer cu WITH (NOLOCK) ON ci.custid = cu.custid
			LEFT JOIN dbo.CustLoginInfo_Member cl WITH (NOLOCK) ON ci.custid = cl.custid
		WHERE ci.recommend = @tmpCustId
			AND ci.roleId = 1
			AND (
				ci.username LIKE '%' + ISNULL(@SearchUsername, '') + '%'
				OR cu.firstname LIKE '%' + ISNULL(@SearchUsername, '') + '%'
			)
			AND (
				@SearchStatusId = 0
				OR (@SearchStatusId = 1 AND ISNULL(ci.reject, 0) = 0 AND ISNULL(ci.closed, 0) = 0)
				OR (@SearchStatusId = 2 AND ISNULL(ci.reject, 0) = 1 AND ISNULL(ci.closed, 0) = 0)
				OR (@SearchStatusId = 3 AND ISNULL(ci.closed, 0) = 1)
			)

		SELECT @TotalRows = @@ROWCOUNT
	END

	/* ===== Paging ===== */
	DECLARE @RowStart INT, @RowEnd INT
	SELECT  @RowStart	= (@PageIndex - 1) * @PageSize + 1,
			@RowEnd		= @RowStart + @PageSize - 1

	SELECT custid, username, username2 AS nickname, firstname, credit, [group], CreatedDate, Status, ClosedReason
	FROM (
		SELECT	ci.custid, ci.username, cu.username2, cu.firstname, ci.credit, cu.ugroup AS [group],
				cu.creatdate AS CreatedDate, ci.Status, ci.ClosedReason,
				ROW_NUMBER() OVER(ORDER BY ci.Status, ci.username) AS RowId
		FROM #CustInfo ci
			INNER JOIN dbo.Customer cu WITH (NOLOCK) ON ci.custid = cu.custid
	) AS Result
	WHERE RowId BETWEEN @RowStart AND @RowEnd

	DROP TABLE #CustInfo
END
GO


