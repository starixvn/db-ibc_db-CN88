USE bodb02
GO

UPDATE sbm WITH (ROWLOCK, UPDLOCK)
SET sbm.BetTypeGroup = ISNULL(f.GroupTypeId, sbm.BetType)
FROM dbo.CS_SportBettypeMatrix sbm
	LEFT JOIN dbo.f_GroupBettype() f ON sbm.BetType = f.Bettype