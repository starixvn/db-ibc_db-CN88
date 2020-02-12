use bodb_Archive
go

/*
	Created: 20200117@Percy
	DB: DBARC.bodb_Archive
	Task: Regen data for CN88 Customer - Create table for regen
*/

create table [dbo].[CS_SumCancelled_p_xtest](
	[CustID] [int] not null,
	[WinlostDate] [smalldatetime] not null,
	[ProductId] [smallint] not null,
	[Sporttype] [smallint] not null,
	[Bettype] [smallint] not null,
	[IsLive] [bit] not null,
	[CancelType] [tinyint] not null,
	[Wager] [int] null,
	[HouseTurnover] [money] null,
constraint [PK_CS_SumCancelled_p_xtest] primary key nonclustered 
(
	[CustID] asc,
	[WinlostDate] asc,
	[Sporttype] asc,
	[Bettype] asc,
	[IsLive] asc,
	[CancelType] asc
)with (pad_index = off, statistics_norecompute = off, ignore_dup_key = off, allow_row_locks = on, allow_page_locks = on) on [DATA]
) on [DATA]
go