/*<info serverAlias="DBCUST-CustDB" executers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE CS_DBA_Customer_HeadlineIns
	@firstname NVARCHAR(50),
	@lastname NVARCHAR(50),
	@address NVARCHAR(80)=NULL,
	@postal NVARCHAR(50)=NULL,
	@city NVARCHAR(50)=NULL,
	@state NVARCHAR(50)=NULL,
	@country NVARCHAR(50)=NULL,
	@phone NVARCHAR(50),
	@mobilephone NVARCHAR(50),
	@email NVARCHAR(50) = '',
	@fax NVARCHAR(50),
	@refcode1 NVARCHAR(50)=NULL,
	@creator INT,
	@username VARCHAR(30),
	@userpwd VARCHAR(40),
	@site NVARCHAR(50),
	@currency INT,
	@GroupID INT = NULL,
	@ErrCode INT = 0 OUTPUT, 
	@ErrMsg NVARCHAR(1000) = '' OUTPUT
AS
/*
	Created: Johnson
	Date: 2019-03-20
	Task: create new tier0 account
	DB: DBCUST/CUSTDB
	
	Revisions:
		- 20190320@Johnson: initial sp [redmine: #105660]
	Sample: 	
	DECLARE @ErrCode INT = 0 , 
			@ErrMsg NVARCHAR(1000) = '' 
	EXEC CS_DBA_Customer_HeadlineIns
		@firstname=N'',
		@lastname=N'',
		@address='',
		@postal='',
		@city='',
		@state='',
		@country='',
		@phone=N'',
		@mobilephone=N'',
		@email='',
		@fax=N'',
		@refcode1=N'',
		@creator=8,
		@username='MainSH05',
		@userpwd='56E8A2D78170E87C928E480797CC73',
		@site=N'CN88',
		@currency=35,
		@GroupID = 27,
		@ErrCode = @ErrCode OUTPUT,
		@ErrMsg = @ErrMsg OUTPUT
		
*/
BEGIN
	SET NOCOUNT ON;
	
	DECLARE 
	@pwdexpiry DATETIME = NULL,
	@roleid TINYINT  =0,
	@srecommend INT =0, 
	@mrecommend INT =0, 
	@recommend INT = 0,
	@ugroup VARCHAR(10) ='',
	@custid INT,
	@isForcedChangeSecurityCode BIT = 1,
	@suspended BIT = 0,
	
	@Danger TINYINT = 0,
	@Danger2 TINYINT = 0,
	@Danger3 TINYINT = 0,
	@Abnormal TINYINT = 0,

	@closed BIT = 0,	
	@DisableOutright BIT = 0,
	@matchlimit SMALLMONEY = 0,
	@virtualmultiplier SMALLMONEY = 0,
	@DisableFinancial BIT = 0,
	@DisableAutoMPT BIT = 1,
	@IsInternal BIT = 0,
	
	@autosuspend BIT = 0,
	@autosuspend2 BIT = 0,

	@MaxPerMatch MONEY =0,
	@MaxPerMatchv2 MONEY=0,
	@MaxPerMatchv3 MONEY=0,
	@MaxPerMatchv5 MONEY=0,
	@MaxPerMatchv8 MONEY=0,
	@MaxPerMatchv10 MONEY=0,
	@MaxPerMatchv11 MONEY=0,
	@MaxPerMatchv44 MONEY=0,
	--v201
	@MaxPerMatchv201 MONEY = 0,
	@MaxPerMatchv99 MONEY = 0,
	@MaxPerMatchv99MP MONEY = 0,	
	
	@MaxPerMatchv1MP MONEY = 0,	
	
	@MaxPerMatchv161 MONEY = 0,	
	@MaxPerBallv161 MONEY = 0,	
	@MaxPerMatchv164 MONEY = 0,
	
	@DisableNumber BIT = 0,

	@DisableCasino BIT = 0,

	@DoubleCommLosing BIT = 0,
	@DisableCasinoBonus BIT = 0,	
	@DisableEsports BIT = 0,
	@DisableGoldDeluxe BIT = 0,
	@HideGoldDeluxe BIT = 0,
	
	@DisableColossusBet BIT = 1,
	@HideColossusBet BIT = 1,
	
	@DisableSuperLive BIT = 0,
	
	--Keno
	@HideKeno BIT = 0,	
	
	@credit MONEY = 0
	

	IF EXISTS(SELECT 1 FROM customer WITH(NOLOCK) WHERE username = @username)
	BEGIN
		PRINT 'Username exists'
		RETURN
	END

	INSERT INTO Customer   			
		(username, firstname, lastname, phone, mobilephone, fax, email, address,
		city, state, country, postal, userpwd, roleid, srecommend, mrecommend, recommend, 
		currency, pwdexpiry, creator, Site, creatdate, ugroup
		) 
	 VALUES (@username, @firstname, @lastname, @phone, @mobilephone, @fax, @email, @address, 
		@city, @state, @country, @postal, @userpwd, @roleid, @srecommend, @mrecommend, @recommend, 
		@currency, @pwdexpiry, @creator, @site, GETDATE(), @ugroup
		)	

	SELECT @custid=@@IDENTITY

	IF @custid IS NULL
		BEGIN
			print 'Create headline fail'

			DELETE customer WITH(UPDLOCK,ROWLOCK)
			WHERE custid = @custid
			
			RETURN;
		END
			
	EXEC DBMSG.bodb_Message.dbo.Age_MsgCustReadStatus_Ins  @custid, 0, @roleid, @ErrCode , @ErrMsg
		
	IF @ErrCode <>0
	BEGIN	
		print 'Create headline fail'
		
		DELETE customer WITH(UPDLOCK,ROWLOCK)
		WHERE custid = @custid	
		RETURN;
	END

	INSERT INTO dbo.CustLoginInfo
		(
			CustID, OldUserPwd, LastChangedPwdDate, isFirstLogin, SecurityCodeCount,
			SecurityCode, isForcedChangeSecurityCode, LastChangedSecurityCodeDate,ClosedReason
		)
		VALUES
		(
			@custid, NULL, GETDATE(), 1, 0,
			NULL, @isForcedChangeSecurityCode, NULL,0
		)	
	
	IF @@ERROR > 0
	BEGIN
		print 'Create headline fail'
		
		DELETE customer WITH(UPDLOCK,ROWLOCK)
		WHERE custid = @custid	
		EXEC DBMSG.bodb_Message.dbo.Age_MsgCustReadStatus_Del  @custid
		
		RETURN;
	END	
	
	INSERT INTO dbo.CS_HeadlineExtraPTGroup(HeadlineId,GroupID)
	VALUES (@custid,@groupid)
	
	IF @@ERROR > 0
	BEGIN
		print 'Create headline fail'
		
		DELETE customer WITH(UPDLOCK,ROWLOCK)
		WHERE custid = @custid	
		
		EXEC DBMSG.bodb_Message.dbo.Age_MsgCustReadStatus_Del  @custid
		
		DELETE CustLoginInfo WITH(UPDLOCK,ROWLOCK)
		WHERE custid = @custid	
		RETURN;
	END	
	
	INSERT INTO [dbo].[custinfo]
		(
			custid, currency,Disable151_AU
		  , maxpermatch, maxpermatch2, maxpermatch3, maxpermatch5, maxpermatch8, maxpermatch10, maxpermatch11,MaxPerMatch44, maxpermatch201
		  , maxpermatch99
		  , roleid, srecommend, mrecommend, recommend, dangercust, autosuspend, autosuspend2, reject, credit, closed, username
		  , MatchLimit, VirtualMultiplier
		  , DisableFinancial, DisableOutright, DisableCasino, DisableNumber, maxpermatch161, MaxPerMatch99MP, MaxPerBall161
		  --, MaxPerMatch180, MaxPerMatch181, MaxPerMatch186, maxpermatch182, maxpermatch184, maxpermatch183, maxpermatch185 , DisableVirtualSports, HideVirtualSports
		  , danger, danger2, danger3, Abnormal
		  ,  DoubleCommLosing, DisableCasinoBonus	 
		  , HideKeno, DisableEsports, DisableGoldDeluxe, HideGoldDeluxe, DisableSuperLive,DisableColossusBet,HideColossusBet
		  , MaxPerMatch1MP,maxpermatch164)
		VALUES
		(
			@custid, @currency,1
		  , @MaxPerMatch, @MaxPerMatchv2, @MaxPerMatchv3, @MaxPerMatchv5, @MaxPerMatchv8, @MaxPerMatchv10, @MaxPerMatchv11,@MaxPerMatchv44, @MaxPerMatchv201
		  , @MaxPerMatchv99
		  , @roleid, @srecommend, @mrecommend, @recommend, 0, @autosuspend, @autosuspend2, ISNULL(@suspended, 0), @credit, ISNULL(@closed, 0), @username
		  , @matchlimit, @virtualmultiplier
		  , @DisableFinancial, @DisableOutright, @DisableCasino, @DisableNumber,  @MaxPerMatchv161, @MaxPerMatchv99MP, @MaxPerBallv161
		  --, @MaxPerMatchv180, @MaxPerMatchv181, @MaxPerMatchv186, @maxpermatchv182, @maxpermatchv184, @maxpermatchv183, @maxpermatchv185, @Disable180_1201, @HideVirtualSports
		  , @danger, @danger2, @danger3, @Abnormal
		  ,  @DoubleCommLosing,@DisableCasinoBonus	
		  , @HideKeno, @DisableEsports, @DisableGoldDeluxe, @HideGoldDeluxe, @DisableSuperLive,@DisableColossusBet,@HideColossusBet
		  , @MaxPerMatchv1MP, @maxpermatchv164
		)

	IF @@ERROR > 0
	BEGIN
		print 'Create headline fail'
		
		DELETE customer WITH(UPDLOCK,ROWLOCK)
		WHERE custid = @custid	
		EXEC DBMSG.bodb_Message.dbo.Age_MsgCustReadStatus_Del  @custid
		
		DELETE CustLoginInfo WITH(UPDLOCK,ROWLOCK)
		WHERE custid = @custid
		
		DELETE CS_HeadlineExtraPTGroup WITH(UPDLOCK,ROWLOCK)
		WHERE HeadlineId = @custid
		RETURN;
	END	
	
END	
    	
		