USE [bodb02]
GO

/*
	Created: 20190220@Percy
	DB: DBPRO.bodb02
	Task: CN88 - Create new table CS_AccountingPeriod
*/

CREATE TABLE [dbo].[CS_AccountingPeriod]
(
	[Year] [smallint] NOT NULL,
	[PeriodId] [smallint] NOT NULL,
	[FromDate] [smalldatetime] NULL,
	[ToDate] [smalldatetime] NULL,
	CONSTRAINT [PK_CS_AccountingPeriod] PRIMARY KEY CLUSTERED 
	(
		[Year] ASC,
		[PeriodId] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [DATA]
) ON [DATA]
GO