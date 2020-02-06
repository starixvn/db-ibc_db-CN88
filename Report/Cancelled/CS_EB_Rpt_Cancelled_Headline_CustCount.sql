/*<info serverAlias="DBAGE-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_EB_Rpt_Cancelled_Headline_CustCount]
	@ReportMode			TINYINT = 1
	,@FromDate			SMALLDATETIME
	,@ToDate			SMALLDATETIME
	,@MoveBetsDay		SMALLDATETIME
	,@SporttypeGroups	VARCHAR(MAX) = '0' -- all
	,@BettypeGroup		SMALLINT = 0 -- all
	,@IsLive			TINYINT = 2  -- all
	,@IsExcludedTest	BIT = 1
	,@ReportType 		TINYINT = 1
AS

/*
	Created: 20191210@Percy
	Task: CN88 - EB - Cancelled Report - View Headlines - Customer Counter
	DB: DBAGE.bodb02	
	
	Revisions:
		- 20191210@Percy: Initiliaze SP [RedmineID: #125186]
		
	Param's Explanation:
		- @ReportMode: 1: current, 2: history
		- @SporttypeGroups: list of SporttypeGroup
		- @BettypeGroup: default = 0: All
		- @IsLive: (market) default = 2: All
									= 1: Live
									= 0: Dead
		- @ReportType:	= 1: Cancelled
						= 2: Abnormal Bet
*/

BEGIN
	SET NOCOUNT ON

	/* ===== Get Sport/Bettype ===== */
	BEGIN
		DECLARE @isTest BIT
		SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

		CREATE TABLE #tblSportType (SportType INT)
		INSERT INTO #tblSportType (SportType)
		SELECT DISTINCT SportType FROM dbo.CS_f_SporttypeMatrix_Sel (0, @SporttypeGroups, @BetTypeGroup, @IsTest)

		CREATE TABLE #tblBetType (ProductID INT, BetType INT, EventType TINYINT)
		INSERT INTO #tblBetType (ProductID, BetType, EventType)
		SELECT DISTINCT ProductID, BetType, EventType FROM dbo.CS_f_BettypeMatrix_Sel (0, @SporttypeGroups, @BetTypeGroup, @IsTest)
	END
	/* ===== End Get Sport/Bettype ===== */

	/* ===== Get Data ===== */
	BEGIN
		CREATE TABLE #CustomerCounter
		(
			UplineId	INT
			,srecommend	INT
			,mrecommend	INT
			,recommend	INT
			,custid		INT
		)

		DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME

		-- bettrans
		IF @ReportMode = 1 AND @ToDate > @MoveBetsDay
		BEGIN
			SELECT	@FDate = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
					,@TDate = @ToDate
		
			IF OBJECT_ID('tempdb..#tmpBettrans') IS NOT NULL
				DROP TABLE #tmpBettrans

			IF OBJECT_ID('tempdb..#__refno') IS NOT NULL
				DROP TABLE #__refno

			CREATE TABLE #tmpBettrans
			(
				UplineId	INT
				,srecommend	INT
				,mrecommend	INT
				,recommend	INT
				,custid		INT
				,matchid	INT
				,eventtype	TINYINT
			)

			-- For VS Parlay (bettype = 2799)
			SELECT b.refno, b.matchid
			INTO #__refno
			FROM dbo.CS_CustSuper c WITH (NOLOCK)
				CROSS APPLY (
					SELECT b.refno, bm.matchid
					FROM dbo.bettrans b WITH (NOLOCK)
						CROSS APPLY (SELECT TOP 1 bm.matchid FROM dbo.bettransm bm WITH (NOLOCK) WHERE b.refno = bm.refno) AS bm
					WHERE c.custid = b.srecommend AND b.matchid = 2799 AND b.winlostdate BETWEEN @FDate AND @TDate
						AND b.statusID IN (101, 102, 103)
			) AS b

			INSERT INTO #tmpBettrans
			(
				UplineId
				,srecommend
				,mrecommend
				,recommend
				,custid
				,matchid
				,eventtype
			)
			SELECT
				e.UplineId
				,b.srecommend
				,b.mrecommend
				,b.recommend
				,b.custid
				,b.matchid
				,b.eventtype
			FROM CS_CustSuper cs WITH (NOLOCK)
				CROSS APPLY (
					SELECT
						b.srecommend
						,b.mrecommend
						,b.recommend
						,b.custid
						,CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END AS matchid
						,b.bettype
						,CASE WHEN b.bettype = 2799 THEN 1 ELSE bt.eventtype END AS eventtype
						,bt.ProductID
						,b.winlostdate
					FROM dbo.bettrans b WITH (NOLOCK)
						INNER JOIN #tblBetType bt ON b.bettype = bt.bettype
						OUTER APPLY (
							SELECT r.matchid FROM #__refno r WHERE b.refno = r.refno AND b.bettype = 2799
						) AS s
						OUTER APPLY (SELECT CAST(('<xml>' + ISNULL(b.ExtraInfo, '') + '</xml>') AS XML).value('data(/xml/p1/@ab)[1]','TINYINT')) AS t(c)
					WHERE cs.CustId = b.srecommend
						AND b.statusID IN (101, 102, 103)
						AND b.winlostdate BETWEEN @FDate AND @TDate
						AND (
								@IsLive = 2
								OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
								OR (b.bettype = 2799 AND @IsLive = 0)
								OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
							)
						AND @ReportType = CASE	WHEN b.ExtraInfo LIKE '%p1%' AND t.c = 1 THEN 2  --- Abnormal bet
												ELSE 1  --- Cancelled
											END
						AND (b.currency <> 20 OR @IsExcludedTest = 0)
				) AS b
				CROSS APPLY (
					SELECT ag.UplineId, ag.ExtraPT
					FROM dbo.Acc_GroupExtraPTSetting ag WITH (NOLOCK)
					WHERE cs.CustId = ag.SuperId
						AND b.winlostdate BETWEEN ag.FromDate AND ag.ToDate
						AND b.ProductID = ag.ProductId
						AND ag.Sporttype = 0
						AND ag.SubProduct = ''
				) AS e
			GROUP BY
				e.UplineId
				,b.srecommend
				,b.mrecommend
				,b.recommend
				,b.custid
				,b.matchid
				,b.eventtype

			DROP TABLE #__refno

			INSERT INTO #CustomerCounter
			(
				UplineId
				,srecommend
				,mrecommend
				,recommend
				,custid
			)
			SELECT
				b.UplineId
				,b.srecommend
				,b.mrecommend
				,b.recommend
				,b.custid
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
					SELECT CASE WHEN b.matchid = 29 THEN 0 ELSE b.matchid END AS sporttype -- SB Parlay: sporttype = 0
					WHERE b.matchid <> 2799 AND b.eventtype = 0
				) AS m
				INNER JOIN #tblSportType s ON m.sporttype = s.SportType
			GROUP BY
				b.UplineId
				,b.srecommend
				,b.mrecommend
				,b.recommend
				,b.custid
			OPTION (HASH GROUP)

			DROP TABLE #tmpBettrans
		END
		-- End bettrans

		-- CS_SumCancelled
		IF (@ReportMode = 1 AND @FromDate <= @MoveBetsDay) OR @ReportMode = 2
		BEGIN
			SELECT	@FDate = @FromDate
					,@TDate = CASE WHEN @ReportMode = 1 AND @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

			IF @FDate <= @TDate
			BEGIN
				INSERT INTO #CustomerCounter
				(
					UplineId
					,srecommend
					,mrecommend
					,recommend
					,custid
				)
				SELECT
					s.UplineId
					,c.srecommend
					,c.mrecommend
					,c.recommend
					,c.custid
				FROM dbo.CS_CustSuper cs WITH (NOLOCK)
					INNER JOIN dbo.Customer c WITH (NOLOCK) ON cs.custid = c.srecommend AND c.roleid = 1
					CROSS APPLY (
						SELECT
							s.HeadlineId AS UplineId
						FROM bodb_Summary.dbo.CS_SumCancelled s WITH (NOLOCK)
						WHERE c.CustId = s.CustID
							AND s.WinlostDate BETWEEN @FDate AND @TDate
							AND EXISTS (SELECT 1 FROM #tblBetType bt WHERE s.Bettype = bt.BetType)
							AND EXISTS (SELECT 1 FROM #tblSportType st WHERE s.Sporttype = st.SportType)
							AND (@IsLive = 2 OR IsLive = @IsLive)
							AND s.CancelType = @ReportType
					) AS s
				WHERE (c.currency <> 20 OR @IsExcludedTest = 0)
				GROUP BY
					s.UplineId
					,c.srecommend
					,c.mrecommend
					,c.recommend
					,c.custid
			END
		END
		-- End CS_SumCancelled
	END
	/* ===== End Get Data ===== */

	/* ===== Return Data ===== */
	BEGIN
		SELECT
			COUNT(DISTINCT UplineId)	AS HeadlineCount
			,COUNT(DISTINCT srecommend)	AS SuperCount
			,COUNT(DISTINCT mrecommend)	AS MasterCount
			,COUNT(DISTINCT recommend)	AS AgentCount
			,COUNT(DISTINCT custid)		AS MemberCount
		FROM #CustomerCounter
	END
	/* ===== End Return Data ===== */

	DROP TABLE #CustomerCounter
	DROP TABLE #tblBetType
	DROP TABLE #tblSportType
END
GO