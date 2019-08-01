/*<info serverAlias="DBMSG-bodb_Message" executers="bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE bodb_Message
GO

ALTER PROCEDURE [dbo].[CS_CustomerSelMessages]
	@CustId			INT
	,@SubAccId		INT = 0
	,@TargetIds		VARCHAR(100) = '0'
	,@LastPostTime	DATETIME = '9999-12-31'
	,@TotalMessage	INT = 10
	,@IsTest		BIT = 0
AS

/*
	Created: 20190722@Percy
	DB: DBMSG.bodb_Message
	Task: CN88 - Home - Announcement

	Revisions:
		- 20190722@Percy: Initialize SP [RedmineID: #116825]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FromDate DATETIME
	SELECT  @FromDate = DATEADD(MONTH, -1, CURRENT_TIMESTAMP)

	DECLARE @Targets TABLE (TargetId INT)
	INSERT INTO @Targets (TargetId)
	SELECT val FROM dbo.strSplit(@TargetIds, ',')
	UNION ALL
	SELECT @CustId

	/* ===== Sub Account ===== */
	DECLARE @SubMsg TABLE (MessageId INT, BettransId VARCHAR(MAX))
	DECLARE @IsAllDownline BIT = 1
	
	IF @SubAccId <> 0
	BEGIN
		SELECT @IsAllDownline = ISNULL(IsAllDownline, 0) FROM bodb02.dbo.custSub WITH (NOLOCK) WHERE SubAccId = @SubAccId
	END
	/* ===== End Sub Account ===== */

	DECLARE @Msg TABLE (MessageId INT, TargetId INT)
	INSERT INTO @Msg (MessageId, TargetId)
	SELECT TOP (@TotalMessage) m.MessageId, mt.TargetId
	FROM dbo.Msg m WITH (NOLOCK)
		INNER JOIN dbo.MsgTarget mt WITH (NOLOCK) ON m.MessageId = mt.MessageId
	WHERE m.PostTime BETWEEN @FromDate AND @LastPostTime
		AND m.isDeleted = 0
		AND mt.isDeleted = 0
		AND m.MessageId > 522518
		AND m.IsTest <= ISNULL(@IsTest, 0)
		AND EXISTS (SELECT 1 FROM @Targets t WHERE mt.TargetID = t.TargetID)
		AND (
			@IsAllDownline = 1
			OR EXISTS (
				SELECT 1 FROM @Targets t WHERE mt.TargetID = t.TargetID AND t.TargetId <> @CustId
			)
			OR EXISTS (
				SELECT 1
				FROM dbo.MsgTarget s WITH (NOLOCK)
					INNER JOIN bodb02.dbo.CS_SubAccManagement sa WITH (NOLOCK) ON s.TargetId = sa.DownlineId
				WHERE s.MessageId = m.MessageId AND sa.SubAccId = @SubAccId
			)
		)
	ORDER BY m.TopLevel ASC, m.Posttime	DESC

	IF @IsAllDownline = 0
	BEGIN
		WITH CTE_Msg AS (
			SELECT mt.MessageId, mt.BetTransId
			FROM dbo.MsgTarget mt WITH (NOLOCK)
				CROSS APPLY (
					SELECT m.MessageId FROM @Msg m WHERE mt.MessageId = m.MessageId
				) AS m
			WHERE EXISTS (
				SELECT 1 FROM bodb02.dbo.CS_SubAccManagement sa WITH (NOLOCK)
				WHERE mt.TargetId = sa.DownlineId AND sa.SubAccId = @SubAccId
				)
		)
		INSERT INTO @SubMsg (MessageId, BettransId)
		SELECT
			MessageId
			,STUFF(
					(SELECT ',' + ISNULL(BetTransId, '') FROM CTE_Msg c WHERE tmp.MessageId = c.MessageId
					FOR XML PATH ('')
					), 1, 1, '') AS BetTransId
		FROM CTE_Msg tmp
		GROUP BY MessageId
	END

	SELECT DISTINCT TOP (@totalMessage) m.MessageId
			,m.Content_en, m.Content_cs, m.Content_ch, m.Content_jp, m.Content_th, m.Content_it
			,m.Content_ko, m.Content_es, m.Content_vn, m.Content_zhcn
			,m.PostTime, m.MsgType, m.IsSticky, m.LastUpdateTime
			,ISNULL(sm.bettransid, mt.bettransid) AS bettransid
			,mt.isRead, m.TopLevel
	FROM dbo.Msg m WITH(NOLOCK)
		INNER JOIN dbo.MsgTarget mt with (NOLOCK) ON m.MessageId = mt.MessageId
		CROSS APPLY (
			SELECT tmp.MessageId FROM @Msg tmp WHERE m.MessageId = tmp.MessageId AND mt.TargetId = tmp.TargetId
		) AS tmp
		LEFT JOIN @SubMsg sm ON m.MessageId = sm.MessageId AND @IsAllDownline = 0
	ORDER BY m.TopLevel ASC, m.Posttime	DESC
END
GO