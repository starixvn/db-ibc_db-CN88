use bodb_Summary
go

/*
	Created: 20200117@Percy
	DB: DBSUM.bodb_Summary
	Task: CS_SumCancelled - Add new column House Turnover
*/

alter table dbo.CS_SumCancelled
	add HouseTurnover money NULL