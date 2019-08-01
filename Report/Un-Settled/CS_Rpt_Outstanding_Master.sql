/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Rpt_Outstanding_Master]
	@CustId				INT = 0,
	@IsOwner			BIT = 1,
	@SubAccId			INT = 0,
	@IsAllDownline		BIT = 1,
	@FromDate			SMALLDATETIME,
	@ToDate				SMALLDATETIME,
	@SporttypeGroup		SMALLINT = 0, -- all
	@BettypeGroup		SMALLINT = 0, -- all
	@IsLive				TINYINT = 2 -- all
AS

/*
	Created: 20190214@Sophia
	Task: CN88 - Master report
	DB: DB042.bodb02	
	
	Revisions:
		- 20190214@Sophia: Create new [RedmineID: #105660] 
		- 20190329@Sophia: Implement Non Sports [Redmine: #109521]
		- 20190528@Sophia: Fix bug VS [Redmine: #113482]
		- 20190708@Percy: Remove column HeadlineStock [RedmineID: #116088]
		- 20190713@Percy: Add sub account - permission on downlines [RedmineID: #116825]
		
	Param's Explanation:
		- @CustId: SuperID or MasterID
		- @SubAccId: sub account
		- @IsAllDownline: is view all downlines
		- @IsOwner: Is Master view Master or not (if @CustId = MasterID then @IsOwner = 1, if @CustId = SuperID then @IsOwner = 0)
		- @ProductId: default = 1: Sportsbook
		- @BettypeGroup: default = 0: All
		- @SporttypeGroup: default = 0: All
		- @IsLive: default = 2: All
						= 1: Live
						= 0: Dead 
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @n INT = 2147483647

	/* ===== Get SportBettypeMatrix ===== */
	BEGIN
		DECLARE @isTest BIT = 0
		SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

		CREATE TABLE #tblSportType (SportType INT)
		INSERT INTO #tblSportType (SportType)
		SELECT DISTINCT SportType FROM dbo.CS_f_SporttypeMatrix_Sel (0, @SportTypeGroup, @BetTypeGroup, @IsTest)
	END
	/* ===== End Get SportBettypeMatrix ===== */

	/* ===== Get Customer List ===== */
	BEGIN
		DECLARE @Customers TABLE (CustId INT, BetType INT, EventType TINYINT, RefTable TINYINT)
		DECLARE @Downlines TABLE (DownlineId INT)
		
		IF @IsOwner = 1 -- View owner
		BEGIN
			INSERT INTO @Customers (CustId, BetType, EventType, RefTable)
			SELECT @CustId, BetType, EventType, RefTable
			FROM dbo.CS_f_BettypeMatrix_Sel (0, @SportTypeGroup, @BetTypeGroup, @IsTest)

			/* ===== Get downline list by Sub Account ==== */
			IF ISNULL(@SubAccId, 0) <> 0 AND ISNULL(@IsAllDownline, 0) = 0
			BEGIN
				INSERT INTO @Downlines (DownlineId)
				SELECT DownlineId FROM dbo.CS_f_GetDownlineBySubAcc(@SubAccId)
			END
			/* ===== End Get downline list by Sub Account ==== */
		END
		ELSE -- Upline view
		BEGIN
			/* ===== Get downline list by Sub Account ==== */
			IF ISNULL(@SubAccId, 0) <> 0 AND ISNULL(@IsAllDownline, 0) = 0
			BEGIN
				INSERT INTO @Customers (CustId, BetType, EventType, RefTable)
				SELECT cs.DownlineId, bt.BetType, bt.EventType, bt.RefTable
				FROM dbo.CS_f_GetDownlineBySubAcc(@SubAccId) cs
					CROSS APPLY dbo.CS_f_BettypeMatrix_Sel (0, @SportTypeGroup, @BetTypeGroup, @IsTest) bt
			END
			/* ===== End Get downline list by Sub Account ==== */
			ELSE
			BEGIN
				INSERT INTO @Customers (CustId, BetType, EventType, RefTable)
				SELECT c.CustId, bt.BetType, bt.EventType, bt.RefTable
				FROM dbo.Customer c WITH (NOLOCK)
					CROSS APPLY dbo.CS_f_BettypeMatrix_Sel (0, @SportTypeGroup, @BetTypeGroup, @IsTest) bt
				WHERE c.srecommend = @CustId AND c.roleid = 3
			END

			SELECT @IsAllDownline = 1
		END
	END
	/* ===== End Get Customer List ===== */

	/* ===== Get data ===== */
	BEGIN
		DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME

		CREATE TABLE #tmpOutstanding
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
			b.mrecommend
			,b.matchid
			,CASE WHEN c.BetType = 2799 THEN 1 ELSE c.EventType END AS EventType
			,COUNT(1) AS Wagers
			,SUM(b.stake) AS stake
		FROM @Customers c
			CROSS APPLY (
				SELECT TOP (@n)
					b.mrecommend
					,CASE WHEN b.bettype = 2799 THEN s.matchid ELSE b.matchid END AS matchid
					,b.winlostdate
					,b.stake
				FROM dbo.bettrans b WITH (NOLOCK)
					OUTER APPLY (
							SELECT TOP 1 bm.matchid
							FROM dbo.bettransm bm WITH (NOLOCK)
							WHERE b.refno = bm.refno AND b.bettype = 2799
						) AS s
				WHERE b.mrecommend = c.CustId
					AND b.bettype = c.BetType
					AND b.statusID IN (0, 1)
					AND c.RefTable = 0
					AND (@IsAllDownline = 1 OR EXISTS (SELECT 1 FROM @Downlines d WHERE d.DownlineId = b.recommend))
					AND (
							@IsLive = 2
							OR (b.bettype = 29 AND ((@IsLive = 1 AND b.livehomescore = 1) OR (@IsLive = 0 AND b.livehomescore <> 1)))
							OR (b.bettype = 2799 AND @IsLive = 0)
							OR (b.bettype NOT IN (29, 2799) AND b.liveindicator = @IsLive)
						)
			) AS b
		WHERE b.winlostdate BETWEEN @FromDate AND @ToDate -- prevent using index on winlostdate
		GROUP BY
			b.mrecommend
			,b.matchid
			,CASE WHEN c.BetType = 2799 THEN 1 ELSE c.EventType END
		OPTION (OPTIMIZE FOR (@n = 1))

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
			b.mrecommend
			,b.matchid
			,c.EventType
			,COUNT(1) AS Wagers
			,SUM(b.stake) AS stake
		FROM @Customers c
			CROSS APPLY (
				SELECT TOP (@n)
					t.mrecommend
					,CASE WHEN c.EventType = 0 THEN 0 ELSE t.eventid END AS matchid
					,t.stake
				FROM dbo.translog t WITH (NOLOCK)
				WHERE t.mrecommend = c.CustId
					AND t.gameID = c.BetType
					AND t.statusID IN (0, 1)
					AND (@IsAllDownline = 1 OR EXISTS (SELECT 1 FROM @Downlines d WHERE d.DownlineId = t.recommend))
					AND t.winlostdate BETWEEN @FromDate AND @ToDate
					AND c.RefTable = 3
					AND (
							@IsLive = 2
							OR t.liveindicator = @IsLive
						)
			) AS b
		GROUP BY
			b.mrecommend
			,b.matchid
			,c.EventType
		OPTION (OPTIMIZE FOR (@n = 1))

		INSERT INTO #tmpOutstanding
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
	END
	/* ===== End Get data ===== */

	DROP TABLE #tmpBettrans
	DROP TABLE #tblSportType

	/* ===== Return data ===== */
	BEGIN
		SELECT
			c.CustId
			,c.Username
			,c.FirstName AS Name
			,SUM(Wagers) AS Wagers
			,SUM(Stake) AS Stake
			,0 AS ValidStake
			,0 AS MemberIncome
			,0 AS Agent
			,0 AS AgentResult
			,0 AS MasterIncome
			,0 AS MasterResult
			,0 AS MasterStock
			,0 AS Super
			,0 AS SuperIncome
			,0 AS SuperResult
			,0 AS SuperStock
		FROM #tmpOutstanding o
			INNER JOIN Customer c WITH (NOLOCK) ON o.CustID = c.CustID
		GROUP BY
			c.CustId
			,c.Username
			,c.FirstName
	END
	/* ===== End Return data ===== */

	DROP TABLE #tmpOutstanding
END
GO