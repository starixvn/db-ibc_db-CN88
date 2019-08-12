USE bodb_Summary
GO

/*
	Created: 20190809@Percy
	DB: DBSUM.bodb_Summary
	Task: New sum tables for CN88 - bettrans range
*/

CREATE TABLE [dbo].[CS_SumCancelled_Active](
	[CustID] [int] NOT NULL,
	[WinlostDate] [smalldatetime] NOT NULL,
	[ProductId] [smallint] NOT NULL,
	[Sporttype] [smallint] NOT NULL,
	[Bettype] [smallint] NOT NULL,
	[IsLive] [bit] NOT NULL,
	[CancelType] [tinyint] NOT NULL,
	[Wagers] [int] NULL,
	[Stake] [money] NULL,
	[HeadlineId] [int] NULL,
	CONSTRAINT [PK_CS_SumCancelled_Active] PRIMARY KEY NONCLUSTERED 
	(
		[CustID] ASC,
		[WinlostDate] ASC,
		[ProductId] ASC,
		[Sporttype] ASC,
		[Bettype] ASC,
		[IsLive] ASC,
		[CancelType] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)
)
GO

GRANT SELECT ON [dbo].[CS_SumCancelled_Active] TO [bodbAdminNet]
GO
GRANT SELECT ON [dbo].[CS_SumCancelled_Active] TO [bodbDownlineNet]
GO
GRANT SELECT ON [dbo].[CS_SumCancelled_Active] TO [bodbDownlineNetView]
GO

CREATE TABLE [dbo].[CS_SumWinloss_Active](
	[CustID] [int] NOT NULL,
	[WinlostDate] [smalldatetime] NOT NULL,
	[ProductId] [smallint] NOT NULL,
	[Sporttype] [smallint] NOT NULL,
	[Bettype] [smallint] NOT NULL,
	[IsLive] [bit] NOT NULL,
	[Wagers] [int] NULL,
	[Stake] [money] NULL,
	[ValidStake] [money] NULL,
	[MemberWinloss] [money] NULL,
	[MemberComm] [money] NULL,
	[Agent] [money] NULL,
	[AgentWinloss] [money] NULL,
	[AgentComm] [money] NULL,
	[AgentStock] [money] NULL,
	[AgentResultA] [money] NULL,
	[Master] [money] NULL,
	[MasterWinloss] [money] NULL,
	[MasterComm] [money] NULL,
	[MasterStock] [money] NULL,
	[Super] [money] NULL,
	[SuperWinloss] [money] NULL,
	[SuperComm] [money] NULL,
	[SuperStock] [money] NULL,
	[HeadlineWinloss] [money] NULL,
	[HeadlineComm] [money] NULL,
	[HeadlineStock] [money] NULL,
	[HeadlineId] [int] NULL,
	CONSTRAINT [PK_CS_SumWinloss_Active] PRIMARY KEY NONCLUSTERED 
	(
		[CustID] ASC,
		[WinlostDate] ASC,
		[Sporttype] ASC,
		[Bettype] ASC,
		[IsLive] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)
)
GO

GRANT SELECT ON [dbo].[CS_SumWinloss_Active] TO [bodbAdminNet]
GO
GRANT SELECT ON [dbo].[CS_SumWinloss_Active] TO [bodbDownlineNet]
GO
GRANT SELECT ON [dbo].[CS_SumWinloss_Active] TO [bodbDownlineNetView]
GO