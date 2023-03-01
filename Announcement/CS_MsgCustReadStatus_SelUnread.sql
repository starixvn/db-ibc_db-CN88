/*<info serverAlias="DBMSG-bodb_Message" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[CS_MsgCustReadStatus_SelUnread]
	@CustId		INT
	,@SubAccId	INT = 0
	,@IsTest	BIT = 0
	,@TargetId	VARCHAR(100) = '0'
AS

/*
	Created: 20190731@Percy
	Task: CN88 - Announcement - Get unread messages
	DB: DBMSG.bodb_Message
	
	Revisions:
		- 20190731@Percy: Initialize SP [Redmind: #94705]
		- 20230301@Sophia: use Linked-server for bodb02 [redmine: #184200]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @Targets TABLE (MsgType INT, TargetID INT)

	-- Targerts
	IF @TargetId <> '0'
	BEGIN
		INSERT INTO @Targets (MsgType, TargetID)
		SELECT 3, val
		FROM dbo.strSplit(@TargetId, ',')

		INSERT INTO @Targets (MsgType, TargetID)
		SELECT MsgType, CONVERT(INT, LEFT(RTRIM(TargetID), 2) + '00' + RIGHT(RTRIM(TargetID), 2) + '0')
		FROM @Targets
		WHERE TargetID BETWEEN 1000 AND 9999
	END

	/* ==== Main Account ===== */
	INSERT INTO @Targets (MsgType, TargetID)
	VALUES (1, @CustId)
	/* ==== End Main Account ===== */

	/* ===== Sub Account ===== */
	DECLARE @IsAllDownline BIT = 1

	IF @SubAccId <> 0
	BEGIN
		SELECT @IsAllDownline = ISNULL(IsAllDownline, 0) FROM DBAGE.bodb02.dbo.custSub WITH (NOLOCK) WHERE SubAccId = @SubAccId
	END
	/* ===== End Sub Account ===== */
	
	/* ===== Last seen messages ===== */
	DECLARE @lastSeenNormalMsg		DATETIME
			,@lastSeenSpecialMsg	DATETIME
			,@lastSeenPersonalMsg	DATETIME

	SELECT	@lastSeenNormalMsg		= LastSeenNormalMsg
			,@lastSeenSpecialMsg	= LastSeenSpecialMsg
			,@lastSeenPersonalMsg	= LastSeenPersonalMsg
	FROM dbo.MsgCustReadStatus WITH (NOLOCK)
	WHERE CustId = @CustId AND SubAccID = @SubAccId
	
	DECLARE @minLastSeen DATETIME
	SELECT  @minLastSeen = @lastSeenNormalMsg
	IF @minLastSeen > @LastSeenSpecialMsg	SELECT @minLastSeen = @LastSeenSpecialMsg
	IF @minLastSeen > @lastSeenPersonalMsg	SELECT @minLastSeen = @lastSeenPersonalMsg
	/* ===== End Last seen messages ===== */
	
	SELECT	SUM(CASE WHEN m.MsgType = 3 AND m.IsSticky = 0 AND m.PostTime > @lastSeenNormalMsg THEN 1 ELSE 0 END) AS Normal
			,SUM(CASE WHEN m.IsSticky = 1 AND m.PostTime > @lastSeenSpecialMsg THEN 1 ELSE 0 END) AS Special		
			,SUM(CASE WHEN m.MsgType = 1 AND m.PostTime > @lastSeenPersonalMsg THEN 1 ELSE 0 END) AS Personal
	FROM dbo.Msg m WITH (NOLOCK, INDEX = IX_PostTime)
		INNER JOIN dbo.MsgTarget mt WITH (NOLOCK, INDEX = IX_TargetId) ON m.MessageId = mt.MessageId
	WHERE m.isDeleted = 0
		AND mt.isDeleted = 0		
		AND m.IsTest = @IsTest
		AND m.PostTime > @minLastSeen
		AND (
			(@IsAllDownline = 1 AND EXISTS (SELECT 1 FROM @Targets t WHERE m.MsgType = t.MsgType AND mt.TargetId = t.TargetId))
			OR EXISTS (
				SELECT 1 FROM @Targets t WHERE m.MsgType = t.MsgType AND mt.TargetId = t.TargetId AND t.TargetId <> @CustId
			)
			OR EXISTS (
				SELECT 1
				FROM dbo.MsgTarget s WITH (NOLOCK)
					INNER JOIN DBAGE.bodb02.dbo.CS_SubAccManagement sa WITH (NOLOCK) ON s.TargetId = sa.DownlineId
				WHERE s.MessageId = m.MessageId AND s.TargetId = mt.TargetId AND m.MsgType = 1 AND sa.SubAccId = @SubAccId
			)
		)
END
GO