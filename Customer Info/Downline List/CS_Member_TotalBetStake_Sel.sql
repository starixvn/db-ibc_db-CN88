/*<info serverAlias="DBTXN-bodb02" executers="bodbAdminNet,bodbDownlineNet,bodbDownlineNetView" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_Member_TotalBetStake_Sel]
	@CustId INT
AS

/*
	Created: 20190214@Percy
	DB: DBTXN.bodb02
	Task: Get Member Used Credit

	Revisions:
		- 20190214@Percy: Initialize SP [RedmineID: #105338]
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @today SMALLDATETIME
	SELECT  @today = CONVERT(DATE, GETDATE())

	/*
	-- for local testing
	DELETE dbo.DailyBetStake WITH (ROWLOCK, UPDLOCK)
	WHERE  CustId = @CustId AND Date = @today
	*/

	EXEC dbo.Dot_Member_CalcDailyBetStake_CN88_test @CustId = @CustId, @Date = @today, @Stake = 0

	/*

	DECLARE @today SMALLDATETIME
	SELECT  @today = CONVERT(DATE, GETDATE())

	DECLARE @isTest BIT
	SELECT  @isTest = dbo.f_CheckSPVersion(@@PROCID)

	CREATE TABLE #BetType (BetType INT, RefTable TINYINT)
	INSERT INTO #BetType (BetType, RefTable)
	SELECT DISTINCT BetType, RefTable FROM dbo.CS_f_BettypeMatrix_Sel(0,0,0,@isTest)

	SELECT ISNULL(SUM(stake), 0) AS UsedCredit
	FROM
	(
	-- 1. bettrans
		SELECT SUM(stake) AS stake
		FROM dbo.bettrans b WITH (NOLOCK)
			INNER JOIN #BetType bt ON b.bettype = bt.BetType
		WHERE b.custid = @CustId
			AND b.winlostdate >= @today
			AND bt.RefTable = 0

		UNION ALL
	
	-- 2. bettransRnG
		SELECT SUM(stake) AS stake
		FROM dbo.bettransRnG b WITH (NOLOCK)
			INNER JOIN #BetType bt ON b.gameID = bt.BetType
		WHERE b.custid = @CustId
			AND b.winlostdate >= @today
			AND bt.RefTable = 1

		UNION ALL

	-- 3. bettransLC
		SELECT SUM(stake) AS stake
		FROM dbo.bettransLC b WITH (NOLOCK)
			INNER JOIN #BetType bt ON b.gameID = bt.BetType
		WHERE b.custid = @CustId
			AND b.winlostdate >= @today
			AND bt.RefTable = 2

		UNION ALL
	
	-- 4. translog
		SELECT SUM(stake) AS stake
		FROM dbo.translog t WITH (NOLOCK)
			INNER JOIN #BetType bt ON t.gameID = bt.BetType
		WHERE t.custid = @CustId
			AND t.winlostdate >= @today
			AND bt.RefTable = 3
	) AS bt

	DROP TABLE #BetType
	*/
END
GO