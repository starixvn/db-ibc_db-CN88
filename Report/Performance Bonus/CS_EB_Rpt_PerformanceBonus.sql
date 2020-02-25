/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_EB_Rpt_PerformanceBonus]
	@FromDate			SMALLDATETIME
	,@ToDate			SMALLDATETIME
	,@Currency			INT
	,@SporttypeGroups	VARCHAR(MAX) = '0' -- all
	,@HeadlineStock		MONEY = 0
	,@SuperUsernames	VARCHAR(MAX) = ''
	,@Conjunction		BIT = 0
	,@HeadlineGroupId   SMALLINT = 1 -- TPG
AS

/*
	Created: 20190918@Percy
	DB: DBAGE.bodb02
	Task: CN88 - EB - Performance Bonus Report

	Revisions:
		- 20190918@Percy: Initialize SP [RedmineID: #119020]
		- 20190926@Percy: Get UplineId (HeadlineId) from sum tables instead of CustSuper [Redmine: #118962]
		- 20191210@Percy: Add @SporttypeGroups for drop down Sports [RedmineID: #124603]
		- 20200210@Malcolm : New group of Headline XPG - Changes on EB [RedmineID : #127209]
		- 20200212@Percy: Fix filter by conjunction [RedmineID: #128372]

	Param's Explanation:
		@Conjunction:
			0: AND	(>= @HeadlineStock AND @SuperUsernames)
			1: OR	(>= @HeadlineStock OR @SuperUsernames)
		@HeadlineStock: >= @HeadlineStock
		@SuperUsernames: list of super usernames
		@SporttypeGroups: default = 0: All
		@HeadlineGroupId: default = 0: all headlines
		                          = 1: TPG headlines
								  = 2: XPG headlines
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @IsTest BIT = 0
	SELECT  @IsTest = dbo.f_CheckSPVersion(@@PROCID)

	CREATE TABLE #tblSportType (SportType INT)
	INSERT INTO #tblSportType (SportType)
	SELECT DISTINCT SportType FROM dbo.CS_f_SporttypeMatrix_Sel (0, @SporttypeGroups, '0', @IsTest)

	SELECT @SuperUsernames = ISNULL(@SuperUsernames, '')

	CREATE TABLE #Super (CustId INT, Username VARCHAR(50))

	IF @SuperUsernames <> ''
	BEGIN
		INSERT INTO #Super (CustId, Username)
		SELECT c.CustId, c.Username
		FROM dbo.Customer c WITH (NOLOCK)
			CROSS APPLY (SELECT u.val FROM dbo.strSplit (@SuperUsernames, ',') u WHERE c.username = u.val) u
		WHERE c.roleid = 4 AND c.site = 'CN88' AND c.currency = @Currency
	END

	CREATE TABLE #CS_CustSuper(CustID INT NOT NULL PRIMARY KEY, UplineId INT NULL)

	INSERT INTO #CS_CustSuper(CustID, UplineId)
	SELECT c.CustId, cs.UplineId
	FROM dbo.CS_CustSuper c 
		   INNER JOIN CustSuper cs ON c.CustId = cs.custid
		   LEFT JOIN dbo.f_GetHeadlineNoPT() f ON c.CustId = f.SuperId
	WHERE @HeadlineGroupId = 0 OR (@HeadlineGroupId = 2 AND f.SuperId IS NOT NULL) OR (@HeadlineGroupId = 1 AND f.SuperId IS NULL)

	IF @Conjunction = 0 AND @SuperUsernames <> ''
	BEGIN
		SELECT
			s.CustId
			,s.Username
			,u.HeadlineId
			,u.HeadlineUsername
			,cs.HeadlineStock
		FROM #Super s
			CROSS APPLY (
				SELECT cs.HeadlineId, SUM(cs.HeadlineStock) AS HeadlineStock
				FROM bodb_Summary.dbo.CS_SumWinloss cs WITH (NOLOCK)
				WHERE cs.CustID = s.CustId
					AND cs.WinlostDate BETWEEN @FromDate AND @ToDate
					AND EXISTS (SELECT 1 FROM #tblSportType st WHERE cs.Sporttype = st.SportType)
				GROUP BY cs.HeadlineId
				HAVING SUM(cs.HeadlineStock) >= @HeadlineStock
			) AS cs
			CROSS APPLY (
				SELECT c.CustId AS HeadlineId, c.Username AS HeadlineUsername
				FROM #CS_CustSuper cs 
					INNER JOIN dbo.Customer c WITH (NOLOCK) ON cs.UplineId = c.CustId
				WHERE s.CustId = cs.CustId
			) AS u
	END
	ELSE
	BEGIN
		CREATE TABLE #Data
		(
			CustId			INT
			,HeadlineId		INT
			,HeadlineStock	MONEY
		)
		
		INSERT INTO #Data
		(
			CustId
			,HeadlineId
			,HeadlineStock
		)
		SELECT
			s.CustId
			,cs.HeadlineId
			,cs.HeadlineStock
		FROM #CS_CustSuper s
			CROSS APPLY (
				SELECT cs.CustID, cs.HeadlineId, SUM(cs.HeadlineStock) AS HeadlineStock
				FROM bodb_Summary.dbo.CS_SumWinloss cs WITH (NOLOCK)
				WHERE cs.CustID = s.CustId
					AND cs.WinlostDate BETWEEN @FromDate AND @ToDate
					AND EXISTS (SELECT 1 FROM #tblSportType st WHERE cs.Sporttype = st.SportType)
				GROUP BY cs.CustID, cs.HeadlineId
			) AS cs

		SELECT
			c.CustId
			,c.Username
			,u.CustId AS HeadlineId
			,u.Username AS HeadlineUsername
			,d.HeadlineStock
		FROM #Data d
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON d.CustId = c.CustId AND c.currency = @Currency
			INNER JOIN dbo.Customer u WITH (NOLOCK) ON d.HeadlineId = u.CustId
		WHERE
			(
				@Conjunction = 0
				AND d.HeadlineStock >= @HeadlineStock
			)
			OR
			(
				@Conjunction = 1
				AND
				(
					d.HeadlineStock >= @HeadlineStock
					OR @SuperUsernames = ''
					OR EXISTS (SELECT 1 FROM #Super s WHERE c.CustId = s.CustId)
				)
			)
		
		DROP TABLE #Data
	END

	DROP TABLE #Super
	DROP TABLE #tblSportType
	DROP TABLE #CS_CustSuper
END
GO