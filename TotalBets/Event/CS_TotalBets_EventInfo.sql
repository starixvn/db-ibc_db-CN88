/*<info serverAlias="DB042-bodb02" executers="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0"></info>*/	
USE bodb02
GO 

ALTER PROCEDURE [dbo].[CS_TotalBets_EventInfo]
	@MatchId INT = 0
AS
 
/*
Created: 20190307@Sophia
Task : CN88 Total Bet: Match Info 
DB: DB042.bodb02
Original:

Revisions:
    - 20190307@Sophia: initial SP [Redmine: #109693] 
	
Param's Explanation:
 
*/
BEGIN
	SET NOCOUNT ON
	SELECT 	m.MatchID,
			m.Sporttype,
			m.leagueid,
			--mr.OfferLive,   
			0 as OfferLive,
			m.HomeId,	
			m.AwayId,
			m.LiveHomeScore,
			m.LiveAwayScore,
			m.Showtime,
			m.IsNeutral
	FROM dbo.Match m WITH (NOLOCK)
		INNER JOIN dbo.match_remark mr WITH (NOLOCK) ON m.MatchID = mr.MatchID 
	WHERE m.MatchID = @MatchID
	 
END
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_EventInfo] TO [bodbDownlineNet]
GO
GRANT EXECUTE ON [dbo].[CS_TotalBets_EventInfo] TO [bodbDownlineNetView]
GO 
