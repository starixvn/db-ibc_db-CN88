/*<info serverAlias="DBCUST-CustDB" executers="bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[CS_Customer_Homepage_Sel]
	@CustId INT,	
	@subAccID INT = 0,
	@fromdate DATETIME,
	@todate	DATETIME		
AS
/*
	Created: 20190304@Johnson
	DB: DBCUST.CustDB
	Task: get general info for home page

	Revisions:
		- 20190304@Johnson: Initialize SP [RedmineID: #105338]
*/

BEGIN
	SET NOCOUNT ON
	
	DECLARE @credit MONEY,
			@CreditBalance MONEY,
			@roleid TINYINT,
			@cntNewMember INT,
			@LastLogin SMALLDATETIME,
			@LastChangePwd DATETIME
	
	CREATE TABLE #tblStatus (roleid TINYINT, cntActive INT, cntClosed INT, cntSuspend INT)
	
	SELECT	@credit = credit, @roleid = roleid
	FROM dbo.CustInfo WITH(NOLOCK)
	WHERE custid = @custid
	
	--get credit balance	
	IF @roleid = 4
	BEGIN
		SELECT @CreditBalance = SUM(Credit)
		FROM dbo.Custinfo WITH(NOLOCK)
		WHERE srecommend = @custid	
			AND roleid = 3
		
		SELECT @cntNewMember = COUNT(1)
		FROM dbo.Customer WITH(NOLOCK)
		WHERE srecommend = @custid	
			AND roleid = 1
			AND creatdate BETWEEN @fromdate AND @todate	
	END
	ELSE IF @roleid = 3
	BEGIN
		SELECT @CreditBalance = SUM(Credit)
		FROM dbo.Custinfo WITH(NOLOCK)
		WHERE mrecommend = @custid	
			AND roleid = 2
		
		SELECT @cntNewMember = COUNT(1)
		FROM dbo.Customer WITH(NOLOCK)
		WHERE mrecommend = @custid	
			AND roleid = 1
			AND creatdate BETWEEN @fromdate AND @todate			
	END
	ELSE IF @roleid = 2
	BEGIN
		SELECT @CreditBalance = SUM(Credit),
			@cntNewMember = COUNT(1)
		FROM dbo.Custinfo ci WITH(NOLOCK)
			INNER JOIN Customer c (NOLOCK) on c.custid = ci.custid
		WHERE c.recommend = @custid	
			AND c.roleid = 1
	END
	
	--get last login date
	SELECT @LastLogin = lastlogged
	FROM dbo.Customer WITH(NOLOCK)
	WHERE custid = @custid
	
	IF @subAccID = 0
	BEGIN
		SELECT @LastChangePwd = LastChangedPwdDate
		FROM dbo.CustLoginInfo WITH(NOLOCK)
		WHERE custid = @custid
		
		IF @roleid = 4
		BEGIN
			INSERT INTO #tblStatus(roleid, cntActive, cntClosed, cntSuspend)
			SELECT roleid, 
				ISNULL(SUM(CASE WHEN Closed = 0 AND ISNULL(reject, 0) = 0 THEN 1 ELSE 0 END), 0) as cntActive,
				ISNULL(SUM(CASE WHEN Closed = 1 THEN 1 ELSE 0 END), 0) as cntClosed,
				ISNULL(SUM(CASE WHEN ISNULL(reject, 0) = 1 AND Closed = 0 THEN 1 ELSE 0 END), 0) as cntSuspend
			FROM custinfo WITH(NOLOCK)
			WHERE srecommend = @custid	
				AND roleid IN (1,2,3)				
			GROUP BY roleid	
		END
		ELSE IF @roleid = 3
		BEGIN
			INSERT INTO #tblStatus(roleid, cntActive, cntClosed, cntSuspend)
			SELECT roleid, 
				ISNULL(SUM(CASE WHEN Closed = 0 AND ISNULL(reject, 0) = 0 THEN 1 ELSE 0 END), 0) as cntActive,
				ISNULL(SUM(CASE WHEN Closed = 1 THEN 1 ELSE 0 END), 0) as cntClosed,
				ISNULL(SUM(CASE WHEN ISNULL(reject, 0) = 1 AND Closed = 0 THEN 1 ELSE 0 END), 0) as cntSuspend
			FROM custinfo WITH(NOLOCK)
			WHERE mrecommend = @custid	
				AND roleid IN (1,2)
			GROUP BY roleid	
		END
		ELSE IF @roleid = 2
		BEGIN
			INSERT INTO #tblStatus(roleid, cntActive, cntClosed, cntSuspend)
			SELECT c.roleid, 
				ISNULL(SUM(CASE WHEN Closed = 0 AND ISNULL(reject, 0) = 0 THEN 1 ELSE 0 END), 0) as cntActive,
				ISNULL(SUM(CASE WHEN Closed = 1 THEN 1 ELSE 0 END), 0) as cntClosed,
				ISNULL(SUM(CASE WHEN ISNULL(reject, 0) = 1 AND Closed = 0 THEN 1 ELSE 0 END), 0) as cntSuspend
			FROM dbo.Custinfo ci WITH(NOLOCK)
				INNER JOIN Customer c WITH(NOLOCK) on c.custid = ci.custid
			WHERE c.recommend = @custid	
				AND c.roleid = 1
			GROUP BY c.roleid	
		END
	END
	ELSE
	BEGIN
		SELECT @LastChangePwd = LastChangedPwdDate
		FROM dbo.CustLoginInfoSub WITH(NOLOCK)
		WHERE custid = @custid
			AND subAccID = @subAccID
	END
	
	SELECT @credit as Credit,
		@CreditBalance as CreditBalance,
		ISNULL(@cntNewMember,0) as cntNewMember,
		@LastLogin as LastLogin,
		@LastChangePwd as LastChangePwd
	
	SELECT *
	FROM #tblStatus
END	