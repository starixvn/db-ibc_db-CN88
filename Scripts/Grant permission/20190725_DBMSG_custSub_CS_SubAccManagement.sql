use bodb02
go

/*
	Created: 20190725@Percy
	DB: DBMSG (DB05, DB05BK1)
	Task: CN88 - Sub Account - Grant permission on custSub and CS_SubAccManagement
*/

grant select on dbo.custSub to bodbAdminNet as dbo
go
grant select on dbo.custSub to bodbDownlineNet as dbo
go
grant select on dbo.custSub to bodbDownlineNetView as dbo
go

grant select on dbo.CS_SubAccManagement to bodbAdminNet as dbo
go
grant select on dbo.CS_SubAccManagement to bodbDownlineNet as dbo
go
grant select on dbo.CS_SubAccManagement to bodbDownlineNetView as dbo
go