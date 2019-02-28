/*<info serverAlias="DBCUST-CustDB" executers="bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [CustDB]
GO

ALTER PROCEDURE [dbo].[CS_Customer_Credit_Sel]
	@CustId INT
AS

/*
	Created: 20181218@Percy
	DB: DBCUST.CustDB
	Task: Member Information >> Downline List >> Credit Info

	Revisions:
		- 20181218@Percy: Initialize SP [RedmineID: #105338]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @srecommend INT, @mrecommend INT, @recommend INT
	DECLARE @RoleId TINYINT, @Credit MONEY, @UsedCredit MONEY, @BetCredit MONEY
	DECLARE @UplineCredit MONEY, @UplineUsedCredit MONEY
	DECLARE @MinCredit MONEY, @MaxCredit MONEY

	SELECT  @srecommend = srecommend, @mrecommend = mrecommend, @recommend = recommend,
			@RoleId = roleId, @Credit = ISNULL(credit, 0)
	FROM dbo.custInfo WITH (NOLOCK) WHERE custId = @custId

	IF @RoleId = 4
	BEGIN
		SELECT	@UsedCredit	= SUM(ISNULL(credit, 0))
		FROM dbo.custInfo WITH (NOLOCK)
		WHERE srecommend = @srecommend
			AND roleId = 3

		SELECT	@MinCredit = ISNULL(@UsedCredit, 0)
	END
	IF @RoleId = 3
	BEGIN
		SELECT	@UplineCredit		= SUM(CASE WHEN roleId = 4 THEN ISNULL(credit, 0) ELSE 0 END),
				@UplineUsedCredit	= SUM(CASE WHEN roleId = 3 THEN ISNULL(credit, 0) ELSE 0 END),
				@UsedCredit			= SUM(CASE WHEN mrecommend = @custId AND roleId = 2 THEN ISNULL(credit, 0) ELSE 0 END) 
		FROM dbo.custInfo WITH (NOLOCK)
		WHERE srecommend = @srecommend

		SELECT	@MinCredit = ISNULL(@UsedCredit, 0),
				@MaxCredit = ISNULL(@UplineCredit, 0) - ISNULL(@UplineUsedCredit, 0) + ISNULL(@Credit, 0)
	END
	ELSE IF @RoleId = 2
	BEGIN
		SELECT	@UplineCredit		= SUM(CASE WHEN roleId = 3 THEN ISNULL(credit, 0) ELSE 0 END),
				@UplineUsedCredit	= SUM(CASE WHEN roleId = 2 THEN ISNULL(credit, 0) ELSE 0 END),
				@UsedCredit			= SUM(CASE WHEN recommend = @custId AND roleId = 1 THEN ISNULL(credit, 0) ELSE 0 END) 
		FROM dbo.custInfo WITH (NOLOCK)
		WHERE mrecommend = @mrecommend

		SELECT	@MinCredit = ISNULL(@UsedCredit, 0),
				@MaxCredit = ISNULL(@UplineCredit, 0) - ISNULL(@UplineUsedCredit, 0) + ISNULL(@Credit, 0)
	END
	ELSE IF @RoleId = 1
	BEGIN
		DECLARE @Amount MONEY

		EXEC DBTXN.bodb02.dbo.Age_CS_Customer_TotalAmount_Sel @CustId = @CustId, @Amount = @Amount OUTPUT

		SELECT @BetCredit = ISNULL(@Amount, 0) + ISNULL(@Credit, 0)

		SELECT	@UplineCredit		= SUM(CASE WHEN roleId = 2 THEN ISNULL(credit, 0) ELSE 0 END),
				@UplineUsedCredit	= SUM(CASE WHEN roleId = 1 THEN ISNULL(credit, 0) ELSE 0 END)
		FROM dbo.custInfo WITH (NOLOCK)
		WHERE recommend = @recommend

		SELECT	@MinCredit = CASE WHEN @BetCredit > 0 THEN 0 ELSE - @BetCredit END,
				@MaxCredit = ISNULL(@UplineCredit, 0) - ISNULL(@UplineUsedCredit, 0) + ISNULL(@Credit, 0)
	END

	SELECT	@CustId		AS CustId,
			@UsedCredit AS UsedCredit, -- for SMA level
			@BetCredit	AS BetCredit, -- for Member level
			@MinCredit	AS MinCredit,
			@MaxCredit	AS MaxCredit -- NULL for Super = unlimitted
END
GO


