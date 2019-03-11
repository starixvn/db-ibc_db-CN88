/*<info serverAlias="DBCUST-CustDB" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [CustDB]
GO

ALTER PROCEDURE [dbo].[CS_Customer_Status_Upd]
	@UserId			INT,
	@SubAccId		INT = 0,
	@CustId			INT,
	@UpdStatusId	TINYINT,
	@SystemID		TINYINT = 1,
	@IP				VARCHAR(15) = '',
	@Language		VARCHAR(2) = 'E',
	@ErrCode		INT = 0 OUTPUT,
	@ErrMsg			NVARCHAR(4000) = '' OUTPUT
AS

/*
	Created: 20181218@Percy
	DB: DBCUST.CustDB
	Task: Member Information >> Downline List >> Update Given Credit

	Revisions:
		- 20181218@Percy: Initialize SP [RedmineID: #105338]

	Param's Explanation:
		@UpdStatusId:
			1: Open
			2: Suspended
			3: Closed
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @StartRun DATETIME, @Duration INT
	SELECT  @StartRun = GETDATE()

	-- Check disable account
	EXEC dbo.Acc_CustomerSelCheckEnable
		@CustId		= @CustId,
		@ErrCode	= @ErrCode OUTPUT,
		@ErrMsg		= @ErrMsg OUTPUT

	IF @ErrCode <> 0
		RETURN

	IF @UserID <> @CustID AND CURRENT_USER <> 'bodbAdminNet' AND EXISTS (SELECT 1 FROM custInfo WITH (NOLOCK) WHERE custid = @CustID AND LockUpd = 1 AND roleid = 1)
	BEGIN
		-- You are currently not authorized to perform this action. Please contact the Customer Service Department for further assistance.
		 SELECT @ErrCode = 101, @ErrMsg = dbo.f_Get_MsgNamebyMsgID (40033, @Language)
         RETURN
	END

	DECLARE @StatusId TINYINT, @RoleId TINYINT, @username NVARCHAR(50), @srecommend INT, @mrecommend INT, @recommend INT
	SELECT  @StatusId	= CASE	WHEN ISNULL(reject, 0) = 0 AND ISNULL(closed, 0) = 0 THEN 1 -- Open
								WHEN ISNULL(reject, 0) = 1 AND ISNULL(closed, 0) = 0 THEN 2 -- Suspended
								WHEN ISNULL(closed, 0) = 1 THEN 3 -- Closed
								END,
			@RoleId		= roleid,
			@username	= username,
			@srecommend = srecommend,
			@mrecommend = mrecommend,
			@recommend	= recommend
	FROM dbo.custInfo WITH (NOLOCK)
	WHERE custId = @CustId

	IF ISNULL(@RoleId, 0) NOT BETWEEN 1 AND 4
	BEGIN
		-- Invalid user!!
		SELECT @ErrCode = 102, @ErrMsg = dbo.f_Get_MsgNamebyMsgID (40002, @Language)
		RETURN
	END

	-- Check allowed downlines during peak hour at weekend
	EXEC dbo.Acc_CustomerSelCheckAllowedDownlines
		@CustId		= @CustId,
		@RoleId		= @RoleId,
		@isExecRep	= 1,
		@Language	= @Language,
		@ErrCode	= @ErrCode OUTPUT,
		@ErrMsg		= @ErrMsg OUTPUT
		
	IF @ErrCode <> 0
		RETURN

	-- Check upline status
	DECLARE @UplineId INT, @UplineStatusId TINYINT
	SELECT  @UplineId = CASE @RoleId WHEN 1 THEN @recommend WHEN 2 THEN @mrecommend WHEN 3 THEN @srecommend END

	IF @RoleId = 4
		SELECT @UplineStatusId = 1
	ELSE
		SELECT @UplineStatusId = CASE	WHEN ISNULL(reject, 0) = 0 AND ISNULL(closed, 0) = 0 THEN 1 -- Open
										WHEN ISNULL(reject, 0) = 1 AND ISNULL(closed, 0) = 0 THEN 2 -- Suspended
										WHEN ISNULL(closed, 0) = 1 THEN 3 -- Closed
										END
		FROM dbo.custInfo WITH (NOLOCK)
		WHERE custId = @UplineId

	IF @UplineStatusId = 2
	BEGIN
		-- This user's upline was suspended. Cannot edit.
		SELECT @ErrCode = 103, @ErrMsg = dbo.f_Get_MsgNamebyMsgID (60002, @Language)
		RETURN
	END
	ELSE IF @UplineStatusId = 3
	BEGIN
		-- This user's upline was closed. Cannot edit.
		SELECT @ErrCode = 103, @ErrMsg = dbo.f_Get_MsgNamebyMsgID (60003, @Language)
		RETURN
	END

	IF @UpdStatusId = @StatusId
	BEGIN
		-- Data not change
		RETURN
	END

	-- Update status process

	-- 1. Selected account
	BEGIN TRY
		UPDATE dbo.custInfo WITH (ROWLOCK, UPDLOCK)
		SET reject	= CASE @UpdStatusId WHEN 1 THEN 0 WHEN 2 THEN 1 ELSE reject END,
			closed	= CASE @UpdStatusId WHEN 1 THEN 0 WHEN 2 THEN 0 ELSE 1 END
		WHERE custid = @CustId
	END TRY
	BEGIN CATCH
		-- Update process is unsuccessful!
		SELECT @ErrCode = 100, @ErrMsg = dbo.f_Get_MsgNamebyMsgID (90001, @Language)
		RETURN
	END CATCH

	-- Update closed account
	IF @UpdStatusId = 3
	BEGIN
		IF @RoleId = 1
		BEGIN
			UPDATE dbo.CustLoginInfo_Member WITH (ROWLOCK, UPDLOCK)
			SET ClosedReason = CASE WHEN @SystemId = 1 THEN 1 ELSE 2 END
			WHERE custid = @CustId

			IF @@ROWCOUNT = 0
				INSERT INTO dbo.CustLoginInfo_Member (CustId, SecurityCode, IP, LastChangedID, LastChangedDate, ClosedReason)
				SELECT @CustId, NULL, @IP, @UserID, GETDATE(), CASE WHEN @SystemId = 1 THEN 1 ELSE 2 END
		END
		ELSE
		BEGIN
			UPDATE dbo.CustLoginInfo WITH (ROWLOCK, UPDLOCK)
			SET ClosedReason = CASE WHEN @SystemId = 1 THEN 1 ELSE 2 END
			WHERE custid = @CustId
		END
	END
	ELSE
	BEGIN
		IF @RoleId = 1
		BEGIN
			UPDATE dbo.CustLoginInfo_Member WITH (ROWLOCK, UPDLOCK)
			SET ClosedReason = 0
			WHERE custid = @CustId
		END
		ELSE
		BEGIN
			UPDATE dbo.CustLoginInfo WITH (ROWLOCK, UPDLOCK)
			SET ClosedReason = 0
			WHERE custid = @CustId
		END

		-- Reset LoginCount
		IF EXISTS (
			SELECT 1
			FROM dbo.Customer WITH (NOLOCK)
			WHERE custid = @CustId
				AND (
					roleId = 1 AND LoginCount = 5
					OR LoginCount > 5
				)
		)
		BEGIN
			UPDATE dbo.Customer WITH (ROWLOCK, UPDLOCK)
			SET LoginCount = 0
			WHERE custid = @CustId
		END
	END

	-- 2. Downlines
	IF @UpdStatusId IN (2,3) AND @RoleId BETWEEN 2 AND 4
	BEGIN
		EXEC dbo.CS_DynamicCustomerInfo_01
			@CustId			= @CustId,
			@RoleId			= @RoleId,
			@Action			= 'UpdateStatus',
			@StatusId		= @StatusId,
			@UpdStatusId	= @UpdStatusId,
			@SystemId		= @SystemId
	END

	SELECT @Duration = DATEDIFF (MILLISECOND, @startRun, GETDATE())

	-- Write log
	DECLARE @LogDataOld VARCHAR(500), @LogDataNew VARCHAR(500)
	SELECT  @LogDataOld = '<Age_CS_Customer_Status_Upd'
						+ ' CustID="' + COALESCE(CONVERT(VARCHAR(50), @CustId), SPACE(1)) + '"'
						+ ' Status="' + COALESCE(CASE @StatusId WHEN 1 THEN 'Open' WHEN 2 THEN 'Suspended' WHEN 3 THEN 'Closed' END, SPACE(1)) + '"'
						+ ' SubAccName="' + COALESCE(dbo.f_GetSubUsername(@SubAccID), SPACE(1)) + '"'
						+ ' IP="' + COALESCE(@IP, SPACE(1)) + '"'
						+ ' />',
			@LogDataNew = '<Age_CS_Customer_Status_Upd'
						+ ' CustID="' + COALESCE(CONVERT(VARCHAR(50), @CustId), SPACE(1)) + '"'
						+ ' Status="' + COALESCE(CASE @UpdStatusId WHEN 1 THEN 'Open' WHEN 2 THEN 'Suspended' WHEN 3 THEN 'Closed' END, SPACE(1)) + '"'
						+ ' SubAccName="' + COALESCE(dbo.f_GetSubUsername(@SubAccID), SPACE(1)) + '"'
						+ ' IP="' + COALESCE(@IP, SPACE(1)) + '"'
						+ ' />'

	BEGIN TRY
		EXEC DBLOG.bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP
			@UserId			= @UserId,
			@CustId			= @CustId,
			@ActionId		= 165004,
			@TrackingValue	= @LogDataNew,
			@TrackingValue2	= @LogDataOld,
			@Duration		= @Duration
	END TRY
	BEGIN CATCH	
		EXEC bodb_CustomerLog.dbo.WriteLog_UserLog_RunSP
			@UserId			= @UserId,
			@CustId			= @CustId,
			@ActionId		= 165004,
			@TrackingValue	= @LogDataNew,
			@TrackingValue2	= @LogDataOld,
			@Duration		= @Duration
	END CATCH
END
GO