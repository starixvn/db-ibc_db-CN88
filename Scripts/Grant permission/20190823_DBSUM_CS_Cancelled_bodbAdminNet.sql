use bodb_Summary
go

/*
	Created: 20190823@Percy
	DB: DBSUM.bodb_Summary
	Task: Grant select on CS_SumCancelled to bodbAdminNet
*/

grant select on dbo.CS_SumCancelled to bodbAdminNet as dbo
go