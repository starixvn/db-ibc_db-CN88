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
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @today SMALLDATETIME, @yesterday SMALLDATETIME
	SELECT  @today = CONVERT(DATE, GETDATE()), @yesterday = DATEADD(DAY, -1, @today)

	CREATE TABLE #Sports (SportTypeGroup INT, SportType INT)
	INSERT INTO #Sports (SportTypeGroup, SportType)
	SELECT DISTINCT SportTypeGroup, SportType FROM dbo.CS_SportBettypeMatrix WITH (NOLOCK)

	CREATE TABLE #tmpMatch (EventDate SMALLDATETIME, SportTypeGroup INT, CompletedEvent INT, IncompletedEvent INT)

	-- match
	INSERT INTO #tmpMatch (EventDate, SportTypeGroup, CompletedEvent, IncompletedEvent)
	SELECT
		EventDate			= m.eventdate
		,SportTypeGroup		= s.SportTypeGroup
		,CompletedEvent		= SUM(CASE WHEN m.eventstatus IN ('Completed', 'refund') THEN 1 ELSE 0 END)
		,IncompletedEvent	= SUM(CASE WHEN m.eventstatus NOT IN ('Completed', 'refund') THEN 1 ELSE 0 END)
	FROM dbo.match m WITH (NOLOCK)
		INNER JOIN #Sports s ON m.sporttype = s.SportType
	WHERE m.eventdate BETWEEN @yesterday AND @today
		AND m.eventstatus <> 'closed'
	GROUP BY
		m.EventDate
		,s.SportTypeGroup

	;WITH CTE_Sports AS (
		SELECT DISTINCT e.EventDate, s.SportTypeGroup
		FROM #Sports s
			CROSS JOIN (SELECT @yesterday AS EventDate UNION ALL SELECT @today) AS e
		WHERE s.SportTypeGroup <> 9 -- exclude Parlay Sport
	)
	SELECT s.EventDate, s.SportTypeGroup, ISNULL(m.CompletedEvent, 0) AS CompletedEvent, ISNULL(m.IncompletedEvent, 0) AS IncompletedEvent
	FROM CTE_Sports s
		LEFT JOIN #tmpMatch m ON s.SportTypeGroup = m.SportTypeGroup AND s.EventDate = m.EventDate

	DROP TABLE #Sports
	DROP TABLE #tmpMatch
END
GO