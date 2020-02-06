use bodb_Summary
go

/*
	Created: 20200210@Percy
	DB: DBSUM.bodb_Summary
	Task: Regen data for CN88 Customer - Gen data from bettrans & bettrans14
*/

-- Get current MBBU: exec bodb02.dbo.Age_SelBalanceUpDay

-- bettrans14
declare @winlostdate smalldatetime = '2020-01-31' -- current BalanceUpDay

while @winlostdate <= '2020-02-05' -- current MoveBetsDay
begin
	exec dbo.Task_CS_SumCancelled_CheckAndCorrect @winlostdate = @winlostdate

	exec dbo.Task_CS_SumWinloss_CheckAndCorrect @winlostdate = @winlostdate
	
	set @winlostdate = dateadd(day, 1, @winlostdate)
end
go


-- bettrans
declare @winlostdate smalldatetime = '2020-02-06' -- current MoveBetsDay + 1

while @winlostdate <= '2020-02-09' -- current yesterday
begin
	exec dbo.Task_CS_SumCancelled @winlostdate = @winlostdate

	exec dbo.Task_CS_SumWinloss @winlostdate = @winlostdate
	
	set @winlostdate = dateadd(day, 1, @winlostdate)
end
go