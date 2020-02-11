/*<info serverAlias="DBCUST-CustDB" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_Customer_CheckBelongingHeadline_ByDate]
	@HeadlineId		INT
	,@CustId		INT
	,@FromDate		SMALLDATETIME
	,@ToDate		SMALLDATETIME
	,@IsBelonging	BIT = 0 OUTPUT
AS

/*
	Created: 20190926@Percy
	DB: DBCUST.CustDB
	Task: CN88 - Check customer is belong to Healine from FromDate to ToDate

	Revisions:
		- 20190926@Percy: Initialize SP [Redmine: #118962]
*/

BEGIN
	SET NOCOUNT ON

	SET @IsBelonging = 0

	IF @CustId = @HeadlineId
	BEGIN
		SET @IsBelonging = 1
		RETURN
	END

	DECLARE @srecommend INT
	SELECT  @srecommend = srecommend FROM dbo.Customer WITH (NOLOCK) WHERE custid = @CustId

	IF EXISTS (
		SELECT 1
		FROM dbo.Acc_GroupExtraPTSetting WITH (NOLOCK)
		WHERE UplineId = @HeadlineId
			AND SuperId = @srecommend
			AND FromDate <= @ToDate
			AND ToDate >= @FromDate
	)
		SET @IsBelonging = 1
END
GO