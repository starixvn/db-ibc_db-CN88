/*<info serverAlias="DBMSG-bodb_Message" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE bodb_Message
GO

CREATE PROCEDURE [dbo].[CS_Msg_GetPrivateMessage]
	@CustId			INT
	,@SubAccId		INT = 0
	,@Special		INT = 2
	,@TotalMessage	INT = 10
	,@FromDate		DATETIME
	,@ToDate		DATETIME
	,@IsTest		BIT = 0
AS

/*
	Created: 20190722@Percy
	DB: DBMSG.bodb_Message
	Task: CN88 - Announcement - Private Message

	Revisions:
		- 20190722@Percy: Initialize SP [RedmineID: #116825]
*/

BEGIN
	SET NOCOUNT ON

	IF @TotalMessage = 0
	BEGIN
		SELECT @TotalMessage = COUNT(1)
		FROM dbo.Msg WITH (NOLOCK)
		WHERE PostTime BETWEEN @FromDate AND @ToDate
	END

	DECLARE @Msg TABLE (MessageId INT)

	/* ===== Sub Account ===== */
	DECLARE @SubMsg TABLE (MessageId INT, BettransId VARCHAR(MAX))
	DECLARE @IsAllDownline BIT = 1

	IF @SubAccId <> 0
	BEGIN
		SELECT @IsAllDownline = ISNULL(IsAllDownline, 0) FROM bodb02.dbo.custSub WITH (NOLOCK) WHERE SubAccId = @SubAccId
	END
	/* ===== End Sub Account ===== */

	INSERT INTO @Msg (MessageId)
	SELECT TOP (@TotalMessage) m.MessageId
	FROM dbo.Msg m WITH (NOLOCK)
		INNER JOIN dbo.MsgTarget mt WITH (NOLOCK) ON m.MessageId = mt.MessageId
	WHERE m.PostTime BETWEEN @FromDate AND @ToDate
			AND m.MsgType = 1
			AND m.isDeleted = 0
			AND mt.isDeleted = 0
			AND m.IsTest <= @IsTest
			AND mt.TargetID = @CustId
			AND (
				@Special = 2
				OR (@Special IN (0, 1) AND m.IsSticky = @Special)
			)
			AND (
				@IsAllDownline = 1
				OR EXISTS (
					SELECT 1
					FROM dbo.MsgTarget s WITH (NOLOCK)
						INNER JOIN bodb02.dbo.CS_SubAccManagement sa WITH (NOLOCK) ON s.TargetId = sa.DownlineId
					WHERE s.MessageId = m.MessageId AND sa.SubAccId = @SubAccId
				)
			)
	ORDER BY m.PostTime DESC

	-- Sub Account
	IF @IsAllDownline = 0
	BEGIN
		WITH CTE_Msg AS (
			SELECT mt.MessageId, mt.BetTransId
			FROM dbo.MsgTarget mt WITH (NOLOCK)
				CROSS APPLY (
					SELECT m.MessageId FROM @Msg m WHERE mt.MessageId = m.MessageId
				) AS m
			WHERE EXISTS (SELECT 1 FROM bodb02.dbo.CS_SubAccManagement sa WITH (NOLOCK) WHERE mt.TargetId = sa.DownlineId)
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

	SELECT	m.MessageId
			-- Content
			,m.Content_en, m.Content_cs, m.Content_ch, m.Content_jp, m.Content_th, m.Content_it
			,m.Content_ko, m.Content_es, m.Content_vn, m.Content_id, m.Content_el, m.Content_mx, m.Content_zhcn
			-- Others
			,m.PostTime, m.CreateTime, m.LastUpdateTime
			,m.MsgType, m.IsSticky, m.IsTest, m.MatchId, m.IsBatch
			,m.Creator, m.LastUpdator, m.CreatorName, m.LastUpdateName
			,mt.TargetName AS UserName, ISNULL(sm.BettransID, mt.BettransID) AS BettransID, mt.TargetId
			,DENSE_RANK() OVER(ORDER BY m.PostTime DESC) AS rownum
	FROM dbo.Msg m WITH (NOLOCK)
		INNER JOIN dbo.MsgTarget mt WITH (NOLOCK) ON m.MessageId = mt.MessageId
		CROSS APPLY (
			SELECT tmp.MessageId FROM @Msg tmp WHERE m.MessageId = tmp.MessageId
		) AS tmp
		LEFT JOIN @SubMsg sm ON m.MessageId = sm.MessageId AND @IsAllDownline = 0
	WHERE mt.TargetId = @CustId
	ORDER BY m.PostTime DESC
END
GO