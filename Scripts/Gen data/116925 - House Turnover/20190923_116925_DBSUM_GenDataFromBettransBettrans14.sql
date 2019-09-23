use bodb_Summary
go

/*
	Created: 20190923@Percy
	DB: DBSUM.bodb_Summary
	Task: Regen data for CN88 Customer - Gen data from bettrans & bettrans14
*/
-- bettrans14
declare @winlostdate smalldatetime = '2019-09-13' -- current BalanceUpDay

while @winlostdate <= '2019-09-18' -- current MoveBetsDay
begin
	exec dbo.Task_CS_SumWinloss_CheckAndCorrect @winlostdate = @winlostdate
	
	set @winlostdate = dateadd(day, 1, @winlostdate)
end
go


declare @winlostdate smalldatetime = '2019-09-19' -- current MoveBetsDay + 1

while @winlostdate <= '2019-09-22' -- current yesterday
begin
	exec dbo.Task_CS_SumWinloss @winlostdate = @winlostdate
	
	set @winlostdate = dateadd(day, 1, @winlostdate)
end
go