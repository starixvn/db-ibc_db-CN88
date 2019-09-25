use bodb_Summary
go

/*
	Created: 20190925@Percy
	DB: DBSUM.bodb_Summary
	Task: Gen data for new column: House Turnover
*/

-- 1. Set default value
	-- 12760 rows
update dbo.CS_SumWinloss with (rowlock)
set HouseTurnover = 0
where WinlostDate between '2019-09-13' and '2019-09-18'
	and HouseTurnover is null


-- 2. Gen data
declare @winlostdate smalldatetime = '2019-09-13' -- current BalanceUpDay

while @winlostdate <= '2019-09-18' -- current MoveBetsDay
begin
	exec dbo.Task_CS_SumWinloss_CheckAndCorrect @winlostdate = @winlostdate
	
	set @winlostdate = dateadd(day, 1, @winlostdate)
end
go
