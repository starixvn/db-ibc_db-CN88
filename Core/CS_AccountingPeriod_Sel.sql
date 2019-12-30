/*<info serverAlias="DBPRO-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_AccountingPeriod_Sel]
AS

/*
	Created: 20190214@Percy
	DB: DBPRO.bodb02
	Task: Get Accounting Period

	Revisions:
		- 20190214@Percy: Initialize SP [RedmineID: #105338]
		- 20191231@Sophia: Show 2 years data of Period [Redmine: #126316]
*/

BEGIN
	DECLARE @MaxYear SMALLINT, @LoopID SMALLINT
	SELECT @MaxYear = MAX(Year)
	FROM dbo.CS_AccountingPeriod WITH (NOLOCK)
	
	DECLARE @Period AS TABLE (ID SMALLINT IDENTITY (1,1), Year SMALLINT, PeriodId SMALLINT, FromDate SMALLDATETIME , ToDate SMALLDATETIME)
	
	INSERT INTO @Period(Year, PeriodId, FromDate, ToDate)
	SELECT Year, PeriodId, FromDate, ToDate
	FROM dbo.CS_AccountingPeriod WITH (NOLOCK)
	WHERE Year >= @MaxYear - 1
	ORDER BY Year, PeriodId
	
	SELECT @LoopID = MAX(PeriodId)
	FROM  @Period
	WHERE Year = @MaxYear 
	
	WHILE @LoopID < 13 
	BEGIN 	
		SELECT @LoopID =  @LoopID + 1
		
		INSERT INTO @Period(Year, PeriodId, FromDate, ToDate)
		VALUES (@MaxYear, @LoopID, NULL, NULL)			
	END 	
	
	SELECT Year, PeriodId, FromDate, ToDate 
	FROM @Period
	ORDER BY Year, PeriodId
	
END
GO