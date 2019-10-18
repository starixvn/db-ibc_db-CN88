/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_EB_Rpt_PerformanceBonus]
	@FromDate			SMALLDATETIME
	,@ToDate			SMALLDATETIME
	,@Currency			INT
	,@HeadlineStock		MONEY = 0
	,@SuperUsernames	VARCHAR(MAX) = ''
	,@Conjunction		BIT = 0
AS

/*
	Created: 20190918@Percy
	DB: DBAGE.bodb02
	Task: CN88 - EB - Performance Bonus Report

	Revisions:
		- 20190918@Percy: Initialize SP [RedmineID: #119020]

	Param's Explanation:
		@Conjunction:
			0: AND	(>= @HeadlineStock AND @SuperUsernames)
			1: OR	(>= @HeadlineStock OR @SuperUsernames)
		@HeadlineStock: >= @HeadlineStock
		@SuperUsernames: list of super usernames
*/

BEGIN
	SET NOCOUNT ON

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
				SELECT c.CustId AS HeadlineId, c.Username AS HeadlineUsername
				FROM dbo.CustSuper cs WITH (NOLOCK)
					INNER JOIN dbo.Customer c WITH (NOLOCK) ON cs.UplineId = c.CustId
				WHERE s.CustId = cs.CustId
			) AS u
			CROSS APPLY (
				SELECT SUM(cs.HeadlineStock) AS HeadlineStock
				FROM bodb_Summary.dbo.CS_SumWinloss cs WITH (NOLOCK)
				WHERE cs.CustID = s.CustId
					AND cs.WinlostDate BETWEEN @FromDate AND @ToDate
				HAVING SUM(cs.HeadlineStock) >= @HeadlineStock
			) AS cs
	END
	ELSE
	BEGIN
		CREATE TABLE #Data
		(
			CustId			INT
			,HeadlineStock	MONEY
		)
		
		INSERT INTO #Data
		(
			CustId
			,HeadlineStock
		)
		SELECT
			s.CustId
			,cs.HeadlineStock
		FROM dbo.CS_CustSuper s WITH (NOLOCK)
			CROSS APPLY (
				SELECT cs.CustID, SUM(cs.HeadlineStock) AS HeadlineStock
				FROM bodb_Summary.dbo.CS_SumWinloss cs WITH (NOLOCK)
				WHERE cs.CustID = s.CustId
					AND cs.WinlostDate BETWEEN @FromDate AND @ToDate
				GROUP BY cs.CustID
			) AS cs

		SELECT
			c.CustId
			,c.Username
			,u.HeadlineId
			,u.HeadlineUsername
			,d.HeadlineStock
		FROM #Data d
			INNER JOIN dbo.Customer c WITH (NOLOCK) ON d.CustId = c.CustId AND c.currency = @Currency
			CROSS APPLY (
				SELECT c.CustId AS HeadlineId, c.Username AS HeadlineUsername
				FROM dbo.CustSuper cs WITH (NOLOCK)
					INNER JOIN dbo.Customer c WITH (NOLOCK) ON cs.UplineId = c.CustId
				WHERE d.CustId = cs.CustId
			) AS u
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
END
GO