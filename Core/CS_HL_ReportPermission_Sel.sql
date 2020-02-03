/*<info serverAlias="DBCUST-CustDB" executers="bodbDownlineNet, bodbDownlineNetView"  isFunction="0" isNested="0"></info>*/

USE [CustDB]
GO

CREATE PROCEDURE [dbo].[CS_HL_ReportPermission_Sel]
       @CustID INT
AS

/*
	Created: Malcolm
	Date: 2020-01-21
	Task:   Configuration for CN88 Headlines to view all periods - [Redmine: #127520]
	DB: DBCUST/CustDB

	Revisions:
		- 20200121@Malcolm:  Configuration for CN88 Headlines to view all periods - [Redmine: #127520]
	Parameter's explaination:
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @IsViewAllPeriod BIT = 0

	SELECT @IsViewAllPeriod = IsViewAllPeriod
	FROM CS_ReportPermission WITH(NOLOCK)
	WHERE CustID = @CustID

	SELECT @IsViewAllPeriod
END
GO


