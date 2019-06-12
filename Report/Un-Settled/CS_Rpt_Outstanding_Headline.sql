/*<info serverAlias="DB042-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Rpt_Outstanding_Headline]
	@FromDate			SMALLDATETIME,
	@ToDate				SMALLDATETIME,
	@SporttypeGroup		SMALLINT = 0, -- all
	@BettypeGroup		SMALLINT = 0, -- all
	@IsLive				TINYINT = 2,  -- all
	@IsExcludedTest		BIT = 1
AS

/*
	Created: 20190521@Percy
	Task: CN88 - Headline Settled Report - Company view all Headlines
	DB: DB042.bodb02
	
	Revisions:
		- 20190521@Percy: Initialize SP [Redmine: #113828]
	 
		
	Param's Explanation:
		- @SporttypeGroup: default = 0: All
		- @BettypeGroup: default = 0: All
		- @IsLive: (market) default = 2: All
									= 1: Live
									= 0: Dead
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @isTest BIT
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	CREATE TABLE #tblSportType (SportType INT)
	INSERT INTO #tblSportType (SportType)
	SELECT DISTINCT SportType FROM dbo.CS_f_SporttypeMatrix_Sel (0, @SportTypeGroup, @BetTypeGroup, @IsTest)

	DECLARE @HeadlineInfo TABLE (SuperID INT, UplineID INT, BetType INT, EventType TINYINT, RefTable TINYINT)
	INSERT INTO @HeadlineInfo (SuperID, UplineID, BetType, EventType, RefTable)
	SELECT c.CustID, c.UplineId, b.BetType, b.EventType, b.RefTable
	FROM dbo.CustSuper c WITH (NOLOCK)
		CROSS APPLY dbo.CS_f_BettypeMatrix_Sel (0, @SportTypeGroup, @BetTypeGroup, @IsTest) b
	WHERE EXISTS (SELECT 1 FROM dbo.CS_CustSuper cs WITH (NOLOCK) WHERE cs.CustId = c.custid)
	
	CREATE TABLE #Outstanding
	(
		CustId		INT
		,Wagers		INT
		,Stake		MONEY
	)

	CREATE TABLE #tmpBettrans
	(
		CustId		INT
		,matchid	INT
		,eventtype	TINYINT
		,Wagers		INT
		,Stake		MONEY
	)

	-- bettrans
	INSERT INTO #tmpBettrans
	(
		CustId
		,matchid
		,eventtype
		,Wagers
		,Stake
	)
	SELECT
		c.UplineID
		,b.matchid
		,CASE WHEN c.BetType = 2799 THEN 1 ELSE c.EventType END AS EventType
		,COUNT(1) AS Wagers
		,SUM(b.stake) AS stake
	FROM @HeadlineInfo c
		CROSS APPLY (
			SELECT
				CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END AS matchid
				,b.winlostdate
				,b.stake
			FROM dbo.bettrans b WITH (NOLOCK)
				OUTER APPLY (
						SELECT TOP 1 bm.matchid
						FROM dbo.bettransm bm WITH (NOLOCK)
						WHERE b.refno = bm.refno AND b.bettype = 2799
					) AS s
			WHERE b.srecommend = c.SuperID
				AND b.bettype = c.BetType
				AND b.statusID IN (0, 1)
				AND c.RefTable = 0
				AND (
						@IsLive = 2
						OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
						OR (b.bettype = 2799 AND @IsLive = 0)
						OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
					)
				AND (@IsExcludedTest = 0 OR b.currency <> 20)
		) AS b
	WHERE b.winlostdate BETWEEN @FromDate AND @ToDate -- prevent using index on winlostdate
	GROUP BY
		c.UplineID
		,b.matchid
		,CASE WHEN c.BetType = 2799 THEN 1 ELSE c.EventType END

	-- translog
	INSERT INTO #tmpBettrans
	(
		CustId
		,matchid
		,eventtype
		,Wagers
		,Stake
	)
	SELECT
		c.UplineID
		,b.matchid
		,c.EventType
		,COUNT(1) AS Wagers
		,SUM(b.stake) AS stake
	FROM @HeadlineInfo c
		CROSS APPLY (
			SELECT
				CASE WHEN c.EventType = 0 THEN 0 ELSE t.eventid END AS matchid
				,t.stake
			FROM dbo.translog t WITH (NOLOCK)
			WHERE t.srecommend = c.SuperID
				AND t.gameID = c.BetType
				AND t.statusID IN (0, 1)
				AND t.winlostdate BETWEEN @FromDate AND @ToDate
				AND c.RefTable = 3
				AND (
						@IsLive = 2
						OR t.liveindicator = @IsLive
					)
				AND (@IsExcludedTest = 0 OR t.currency <> 20)
		) AS b
	GROUP BY
		c.UplineID
		,b.matchid
		,c.EventType
	-- End #tmpBettrans

	INSERT INTO #Outstanding
	(
		CustId
		,Wagers
		,Stake
	)
	SELECT
		b.CustId
		,SUM(b.Wagers) AS Wagers
		,SUM(b.Stake) AS Stake
	FROM #tmpBettrans b
		CROSS APPLY (
			SELECT m.sporttype
			FROM dbo.match m WITH (NOLOCK)
			WHERE b.matchid = m.matchid AND b.eventtype = 1 -- included Betradar VS Parlay

			UNION ALL
			SELECT l.sporttype
			FROM dbo.outright o WITH (NOLOCK)
				INNER JOIN dbo.League l WITH (NOLOCK) ON o.leagueid = l.leagueid
			WHERE b.matchid = o.orid AND b.eventtype = 2

			UNION ALL
			SELECT r.sporttype
			FROM dbo.VSRaceInfo r WITH (NOLOCK)
			WHERE b.matchid = r.EventID AND b.eventtype = 3

			UNION ALL
			SELECT 0 AS sporttype -- SB Parlay: sporttype = 0
			WHERE b.matchid <> 2799 AND b.eventtype = 0
		) AS m
	WHERE EXISTS (SELECT 1 FROM #tblSportType s WHERE m.sporttype = s.SportType OR m.sporttype = 0)
	GROUP BY
		b.CustId
	OPTION (HASH GROUP)
			
	SELECT
		c.CustId,
		c.Username,
		SUM(Wagers) AS Wagers,
		SUM(Stake) AS Stake,
		0 AS ValidStake,
		0 AS MemberIncome,
		0 AS SuperComm,
		0 AS HouseWinloss,
		0 AS HouseComm,
		0 AS HouseIncome,
		0 AS HeadlineStock
	FROM #Outstanding o
		INNER JOIN Customer c WITH (NOLOCK) ON o.CustID = c.CustID
	WHERE c.RoleID = 0
		AND (c.currency <> 20 OR @IsExcludedTest = 0)
	GROUP BY
		c.CustId
		,c.Username

	DROP TABLE #Outstanding
	DROP TABLE #tblSportType
	DROP TABLE #tmpBettrans
END
GO