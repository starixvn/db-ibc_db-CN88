/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Rpt_SettlementSummary]
AS

/*
	Created: 20190214@Percy
	DB: DBAGE.bodb02
	Task: Report - Settlement Summary

	Revisions:
		- 20190214@Percy: Initialize SP [RedmineID: #105338]
		- 20190328@Percy: Exclude Keno/Lottery [RedmineID: #109521]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @isTest BIT
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	DECLARE @today SMALLDATETIME, @yesterday SMALLDATETIME
	SELECT  @today = CONVERT(DATE, GETDATE()), @yesterday = DATEADD(DAY, -1, @today)

	CREATE TABLE #Sports (SportTypeGroup INT, SportType INT)
	INSERT INTO #Sports (SportTypeGroup, SportType)
	SELECT DISTINCT SportTypeGroup, SportType FROM dbo.CS_SportBettypeMatrix WITH (NOLOCK)
	WHERE SportTypeGroup NOT IN (9, 12) -- Exclude Parlay, Keno/Lottery
		AND IsTest <= @isTest

	CREATE TABLE #tmpMatch (EventDate SMALLDATETIME, SportTypeGroup INT, CompletedEvent INT, IncompletedEvent INT)

	-- match
	INSERT INTO #tmpMatch (EventDate, SportTypeGroup, CompletedEvent, IncompletedEvent)
	SELECT
		EventDate			= m.eventdate
		,SportTypeGroup		= s.SportTypeGroup
		,CompletedEvent		= SUM(CASE WHEN m.eventstatus IN ('Completed', 'refund') THEN 1 ELSE 0 END)
		,IncompletedEvent	= SUM(CASE WHEN m.eventstatus NOT IN ('Completed', 'refund') THEN 1 ELSE 0 END)
	FROM dbo.match m WITH (NOLOCK)
		INNER JOIN dbo.league l WITH (NOLOCK) ON m.leagueid = l.leagueid
		INNER JOIN #Sports s ON m.sporttype = s.SportType
	WHERE m.eventdate BETWEEN @yesterday AND @today
		AND m.eventstatus <> 'closed'
		AND l.isTest <= @isTest
	GROUP BY
		m.EventDate
		,s.SportTypeGroup

	-- VSOutright
	INSERT INTO #tmpMatch (EventDate, SportTypeGroup, CompletedEvent, IncompletedEvent)
	SELECT
		EventDate			= o.eventdate
		,SportTypeGroup		= s.SportTypeGroup
		,CompletedEvent		= SUM(CASE WHEN o.EventStatus IN ('Completed', 'refund') THEN 1 ELSE 0 END)
		,IncompletedEvent	= SUM(CASE WHEN o.EventStatus NOT IN ('Completed', 'refund') THEN 1 ELSE 0 END)
	FROM dbo.VSOutright o WITH (NOLOCK)
		INNER JOIN dbo.VSRaceInfo r WITH (NOLOCK) ON o.EventID = r.EventID
		INNER JOIN #Sports s ON r.sporttype = s.SportType
	WHERE o.eventdate BETWEEN @yesterday AND @today
		AND o.EventStatus <> 'closed'
	GROUP BY
		o.EventDate
		,s.SportTypeGroup

	;WITH CTE_Sports AS (
		SELECT DISTINCT e.EventDate, s.SportTypeGroup
		FROM #Sports s
			CROSS JOIN (SELECT @yesterday AS EventDate UNION ALL SELECT @today) AS e
	)
	SELECT s.EventDate, s.SportTypeGroup, SUM(ISNULL(m.CompletedEvent, 0)) AS CompletedEvent, SUM(ISNULL(m.IncompletedEvent, 0)) AS IncompletedEvent
	FROM CTE_Sports s
		INNER JOIN dbo.CS_f_SportTypeGroup_OrderSel(1) f ON s.SportTypeGroup = f.SportTypeGroup
		LEFT JOIN #tmpMatch m ON s.SportTypeGroup = m.SportTypeGroup AND s.EventDate = m.EventDate
	GROUP BY s.EventDate, s.SportTypeGroup, f.OrderId
	ORDER BY f.OrderId

	DROP TABLE #Sports
	DROP TABLE #tmpMatch
END
GO