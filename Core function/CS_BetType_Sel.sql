/*<info serverAlias="DBAGE-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[CS_BetType_Sel]
	@SportTypeGroup SMALLINT = 0
AS

/*
	Created: 20190214@Percy
	DB: DBAGE.bodb02
	Task: Get Bet Type List

	Revisions:
		- 20190214@Percy: Initialize SP [RedmineID: #105338]
*/

BEGIN
	SELECT DISTINCT sbm.BettypeGroup, b.typenamee AS TypeName
	FROM dbo.BetType b WITH (NOLOCK)
		INNER JOIN dbo.CS_SportBettypeMatrix sbm WITH (NOLOCK) ON b.TypeId = sbm.BettypeGroup
	WHERE (@SportTypeGroup = 0 OR sbm.SportType = @SportTypeGroup)
		AND sbm.Enabled = 1 AND sbm.SubProduct = ''
END
GO