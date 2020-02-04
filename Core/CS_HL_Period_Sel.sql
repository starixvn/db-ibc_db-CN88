/*<info serverAlias="DBPRO-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[CS_HL_Period_Sel]
 	 	@IsViewAllPeriod BIT
AS

/*
	Created: 20200203@Malcolm
	Date: 2020-02-03
	Task:   Configuration for CN88 Headlines to view all periods - [Redmine: #127520]
	DB: DBPRO.bodb02

	Revisions:
		- 20200203@Malcolm:  Configuration for CN88 Headlines to view all periods - [Redmine: #127520]
	Parameter's explaination:
*/

BEGIN
    SET NOCOUNT ON
    DECLARE @CurrentDate DATE = GETDATE(), @CurrentID SMALLINT;
	DECLARE @Period AS TABLE (ID SMALLINT IDENTITY (1,1), Year SMALLINT, PeriodId SMALLINT, FromDate SMALLDATETIME , ToDate SMALLDATETIME)
	CREATE TABLE #tmp  (ID SMALLINT IDENTITY (1,1), Year SMALLINT, PeriodId SMALLINT, FromDate SMALLDATETIME , ToDate SMALLDATETIME)	

	CREATE  CLUSTERED INDEX ix_tmp ON #tmp([ID])

	INSERT INTO #tmp (Year, PeriodId, FromDate, ToDate)
	SELECT Year, PeriodId, FromDate, ToDate
	FROM dbo.CS_AccountingPeriod cs WITH(NOLOCK)
	ORDER BY Year DESC, PeriodId DESC

	SELECT @CurrentID = ID
	FROM #tmp WITH(NOLOCK) 
	WHERE FromDate <= @CurrentDate AND ToDate >= @CurrentDate 

	IF @IsViewAllPeriod = 'True'
	BEGIN
		INSERT INTO @Period (Year, PeriodId, FromDate, ToDate)
		SELECT Year, PeriodId, FromDate, ToDate
		FROM #tmp WITH(NOLOCK)
		WHERE ID >= @CurrentID + 2 
		ORDER BY ID DESC
		END
     ELSE
	BEGIN
	     INSERT INTO @Period(Year, PeriodId, FromDate, ToDate)
	     SELECT Year, PeriodId, FromDate, ToDate
		 FROM #tmp WITH(NOLOCK)
		 WHERE ID  IN (@CurrentID + 2, @CurrentID + 3)
		 ORDER BY ID DESC
	END 

	SELECT Year, ID AS PeriodId, FromDate, ToDate
	FROM @Period 
	ORDER BY Year, PeriodId

	DROP TABLE #tmp
	
END
GO