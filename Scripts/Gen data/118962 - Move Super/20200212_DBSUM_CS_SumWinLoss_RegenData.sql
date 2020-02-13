use bodb_Summary
go

/*
	Created: 20200212@Percy
	DB: DBSUM.bodb_Summary
	Task: Regen data for CN88 Customer - Gen data from bettrans & bettrans14
*/

-- Get current MBBU: exec bodb02.dbo.Age_SelBalanceUpDay

-- bettrans14
declare @winlostdate smalldatetime = '2020-02-08' -- from 08 Feb 2020

while @winlostdate <= '2020-02-09' -- current MoveBetsDay
begin
	exec dbo.Task_CS_SumWinLoss_CheckAndCorrect @winlostdate = @winlostdate
	
	set @winlostdate = dateadd(day, 1, @winlostdate)
end
go

-- bettrans
declare @winlostdate smalldatetime = '2020-02-10' -- current MoveBetsDay + 1

while @winlostdate <= '2020-02-12' -- current yesterday
begin
	exec dbo.Task_CS_SumWinLoss @winlostdate = @winlostdate
	
	set @winlostdate = dateadd(day, 1, @winlostdate)
end
go
