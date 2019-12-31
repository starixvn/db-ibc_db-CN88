use bodb_Archive
GO 

/*
Create: 20191212@Sophia
Task: NAP Report - Adhoc report to break down Headline share from Extra PT group [Redmine: 123159]
*/



DECLARE 
	@FromWinlostDate SMALLDATETIME = '2019-07-15' ,
	@ToWinlostDate SMALLDATETIME = '2019-11-05'

----------------------- reset winning	 
--Select SUM (Debit -  Credit) AS Amount 
--from transfer_bk b WITH (NOLOCK)
--INNER JOIN bodb02..ExchangeDailyOanda r WITH (NOLOCK)
--		    ON r.ExchangeDate = b.winlostdate AND r.ExchangeId = b.currency
-- Where winlostdate BETWEEN  @FromWinlostDate AND  @ToWinlostDate 
-- and bettype  IN ( 21001, 21002)
--and custID 
-- IN (35476102,
--35854105,
--35854106,
--35854107,
--37049556,
--37049557,
--37049559,
--37049560,
--37049561,
--37049564,
--37049566,
--37049568,
--37049572,
--37049574,
--37049576,
--37049577)


----------Breakdown 
 
BEGIN
	SET NOCOUNT ON
 
	CREATE TABLE #Headline(SuperID INT, UplineID INT)		 
	CREATE TABLE #Transfer (Custid INT, Reset MONEY, Winlostdate SMALLDATETIME )	
	CREATE TABLE #Reset (seq INT IDENTITY (1,1), Winlostdate SMALLDATETIME, CustId INT, ExtraPTWinlost MONEY, Reset MONEY, Variance MONEY)

	
	----Begin: Get Sport Bettype Matrix------
	-- Check SP Version
	DECLARE @isTest BIT = 0

	
	DECLARE @SportBettype TABLE(ProductID INT, Bettype INT,SubProduct VARCHAR(500))
	INSERT INTO @SportBettype
	SELECT ProductID, Bettype, SubProduct FROM bodb02.dbo.f_SportBettypeMatrix_Sel (0, 0, 0, 2, '', '', @isTest)

	DECLARE @ExtraPTProducts AS TABLE (ProductID INT)	
	INSERT INTO @ExtraPTProducts (ProductID) 
	SELECT DISTINCT ProductID FROM bodb02.dbo.Acc_GroupExtraPTSetting WITH(NOLOCK) 	
	
	
	DELETE @SportBettype WHERE ProductId NOT IN (SELECT ProductID FROM @ExtraPTProducts)

	-----End: Get Sport Bettype Matrix------
		 
	
	----Begin: Get Headline List ----
	
	INSERT INTO #Headline (SuperId, UplineId) 
	SELECT c.CustID AS SuperId, c.UplineId
	FROM bodb02.dbo.CustSuper c WITH (NOLOCK) 
	WHERE UplineID IS NOT NULL	 
 	
	 
	 
	--------------------------------------------Extra PT ---------------------------------------------------
	CREATE TABLE #wl 
	(	winlostdate 	SMALLDATETIME, 
		srecommend 		INT, 		
		Sporttype  		SMALLINT, 
		ProductId		INT, 
		SubProduct		VARCHAR(250), 
		WinlostForExtraPT MONEY,
		WinlostForExtraPTBase MONEY
	)
	
	CREATE TABLE #WLByProduct
	(
	    winlostdate			SMALLDATETIME, 
		ProductId			INT,
		SubProduct			VARCHAR(250),
		UplineId			INT,		
		ExtraPTWinlost		MONEY ,
		WinlostForExtraPTBase MONEY
	) 
	 
	INSERT INTO #wl (winlostdate, srecommend, Sporttype, ProductId, SubProduct, WinlostForExtraPT, WinlostForExtraPTBase)
	SELECT  b.winlostdate,
			b.srecommend,					
			CASE WHEN ISNULL(m.Sporttype, 0) <> 0 THEN m.Sporttype ELSE 0 END AS Sporttype,
			s.ProductId,
			CASE WHEN s.SubProduct IN ('MG-SuperLive','Bet Builder') THEN s.SubProduct ELSE '' END AS SubProduct,						
			- SUM(
					CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE b.winlost - b.actual_stake + b.scomm / (1 - b.tpositiontaking) END				
				) AS WinlostForExtraPT,
			- SUM(
					CASE WHEN b.tpositiontaking = 1 THEN 0 ELSE (b.winlost - b.actual_stake + b.scomm / (1 - b.tpositiontaking)) * r.actualrate END				
				) AS WinlostForExtraPTBase					
		FROM dbo.bettrans_BK b WITH (NOLOCK)			
		INNER JOIN @SportBettype s ON s.BetType = b.bettype
		LEFT JOIN dbo.Match_BK m WITH (NOLOCK) ON m.MatchId = b.MatchId  AND m.Sporttype = 44	
		INNER JOIN bodb02..ExchangeDailyOanda r WITH (NOLOCK)
		    ON r.ExchangeDate = b.Winlostdate AND r.ExchangeId = b.currency
				
		WHERE   b.Winlostdate BETWEEN  @FromWinlostDate AND  @ToWinlostDate 
			AND b.ruben = 1
			AND b.statusid NOT IN (101, 102, 103, 121)					 
			AND EXISTS (SELECT 1 FROM bodb02.dbo.CS_CustSuper cs WITH (NOLOCK) WHERE cs.CusTID = b.srecommend) 
		GROUP BY b.Winlostdate,				
				b.srecommend,	
				b.Currency,
				CASE WHEN ISNULL(m.Sporttype, 0) <> 0 THEN m.Sporttype ELSE 0 END,
				s.ProductId,				
				CASE WHEN s.SubProduct IN ('MG-SuperLive', 'Bet Builder') THEN s.SubProduct ELSE '' END
				 

	INSERT INTO #WLByProduct (Winlostdate, ProductId, UplineID, ExtraPTWinlost,WinlostForExtraPTBase ) 
	SELECT Winlostdate, ProductId, UplineID, SUM(ExtraPTWinlost), SUM (WinlostForExtraPTBase)
	FROM (		
			--- extraPT
			SELECT  w.Winlostdate, w.ProductId, 			
					cs.UplineID,
				   SUM(w.WinlostForExtraPT * ISNULL(s.ExtraPT,0)) as ExtraPTWinlost,
				   SUM(w.WinlostForExtraPTBase * ISNULL(s.ExtraPT,0)) as WinlostForExtraPTBase
			FROM	#wl w
			INNER JOIN bodb02.dbo.Acc_GroupExtraPTSetting s WITH(NOLOCK)
					ON w.srecommend = s.SuperId
					AND w.ProductId = s.ProductId
					AND w.SubProduct = s.SubProduct
					AND w.Sporttype = s.Sporttype 
					AND w.Winlostdate BETWEEN s.FromDate AND s.ToDate	
			INNER JOIN bodb02.dbo.CustSuper cs WITH (NOLOCK) 
					ON cs.CustId = w.srecommend AND cs.UplineID IS NOT NULL
			GROUP BY w.Winlostdate, w.ProductId, cs.UplineID
		) w
	GROUP BY w.Winlostdate, w.ProductId, w.UplineID	
	
	
	----view report 
    BEGIN 
	    ----- calculate reset 
		SELECT  ISNULL(e.UplineID, 0) as UplineID ,c.username, 
				ROUND(SUM(ISNULL(e.ExtraPTWinlost, 0)), 2) AS RealWinlost,
				--ROUND(SUM(ISNULL(e.ExtraPTWinlost, 0))* r.ActualRate, 2) AS BaseWinlost ,
				ROUND(SUM(ISNULL(e.WinlostForExtraPTBase, 0)), 2) AS WinlostForExtraPTBase
		FROM  (
					SELECT Winlostdate, UplineID, SUM(ExtraPTWinlost) AS ExtraPTWinlost,  SUM(WinlostForExtraPTBase) AS WinlostForExtraPTBase
					FROM  #WLByProduct 
					GROUP BY Winlostdate, UplineID
				) e 
		INNER JOIN bodb02.dbo.CustInfo c WITH (NOLOCK)
			ON c.CustID = e.UplineId
		--INNER JOIN bodb02..ExchangeDailyOanda r WITH (NOLOCK)
		--    ON r.ExchangeDate = e.Winlostdate AND r.ExchangeId = c.currency
		WHERE c.currency <> 20
		GROUP BY ISNULL(e.UplineID, 0) , c.username 
		
	END	 
	
	
	DROP TABLE #Headline
	DROP TABLE #Reset
	DROP TABLE #Transfer
	DROP TABLE #wl
	DROP TABLE #WLByProduct
	
END
GO