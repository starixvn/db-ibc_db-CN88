/*<info serverAlias="DB042-bodb02" select="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="1"></info>*/	
USE bodb02
GO 

ALTER FUNCTION [dbo].[CS_f_TotalBets_Event_Sel]
	(	
		@Type TINYINT = 0,
	    @isTest BIT = 0,
		@LeagueId INT = 0, -- All
		@SporttypeList VARCHAR(MAX)= ''
		
	)
RETURNS TABLE
RETURN 
/*
Created: 20190313@Sophia
Task : CN88 - Total Bet - Core func get all running event by Type
DB: DB042.bodb02
Original:

Revisions:
    - 20190307@Sophia: initial SP [Redmine: #109693]
 
	
Param's Explanation:
	@Type = 0:  All, 
		  = 1: In-play, 
		  = 2: Today, 
		  = 3: Early,
		  = 4: Outright
	@LeagueId = 0 : all

*/

		SELECT DISTINCT o.orId as MatchID, o.leagueid, l.sporttype, 0 AS IsNeutral,
			   o.teamId As HomeID, 0 As AwayID, 0 AS livehomescore, 0 AS liveawayscore, '' as ShowtimeDT, 0 AS OfferLive, 4 AS Type
		FROM  dbo.outright o WITH (NOLOCK) 
		INNER JOIN dbo.League l WITH (NOLOCK) 
			ON l.leagueid = o.leagueid
		WHERE o.oddsstatus IN ('Running','suspend', 'closed', 'closePrice') 
				AND o.kickofftime > CURRENT_TIMESTAMP					
				AND @Type IN (0,4)	
				AND l.isTest <= @isTest
				AND (l.leagueid = @leagueid OR @leagueid = 0)
				AND (','+@SporttypeList+',' LIKE '%,'+ CONVERT(VARCHAR(5),l.Sporttype) + ',%' OR @SporttypeList = '')
				
		UNION ALL 
		
		SELECT  DISTINCT m.matchid as MatchID, m.leagueid, m.sporttype, m.IsNeutral,
				m.HomeID, m.AwayID,  
				m.livehomescore, m.liveawayscore, m.ShowTimeDT, r.OfferLive,
				CASE WHEN CONVERT(DATE,m.kickofftime) > CONVERT(DATE,CURRENT_TIMESTAMP) THEN 3
					ELSE CASE WHEN m.kickofftime <= CURRENT_TIMESTAMP THEN 1
							ELSE 2 
						END
					END AS Type
		FROM  dbo.Match m  WITH (NOLOCK) 
		INNER JOIN dbo.Match_remark r WITH (NOLOCK) 
			ON m.matchid = r.matchid		
		WHERE   
			m.kickofftime > DATEADD(hour,-12,CURRENT_TIMESTAMP)  -- event started
			AND m.eventstatus NOT IN ('completed','Internal')		
			AND EXISTS (SELECT 1 
						FROM dbo.odds o WITH(NOLOCK) 
						WHERE o.matchid	= m.matchid 
							AND o.oddsstatus <> 'closed')
			AND (	
					(CONVERT(DATE,m.kickofftime) > CONVERT(DATE,CURRENT_TIMESTAMP) AND @Type IN (0,3)) --- Early
					OR (m.kickofftime <= CURRENT_TIMESTAMP AND @Type IN (0,1))   --- In Play
					OR (CONVERT(DATE,m.kickofftime) <= CONVERT(DATE,CURRENT_TIMESTAMP) AND m.kickofftime > CURRENT_TIMESTAMP AND @Type IN (0,2))  --- Today
				)
			AND (','+@SporttypeList+',' LIKE '%,'+ CONVERT(VARCHAR(5),m.Sporttype) + ',%' OR @SporttypeList = '')				
			AND EXISTS ( SELECT 1 FROM League l WITH (NOLOCK) 
						 WHERE l.leagueid = m.leagueid 
								AND l.isTest <= @isTest AND (leagueid = @leagueid OR @leagueid = 0)								
								)		
			
	
GO
GRANT SELECT ON [dbo].[CS_f_TotalBets_Event_Sel] TO [bodbDownlineNet]
GO
GRANT SELECT ON [dbo].[CS_f_TotalBets_Event_Sel] TO [bodbDownlineNetView]
GO 