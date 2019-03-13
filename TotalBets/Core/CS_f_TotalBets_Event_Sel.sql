/*<info serverAlias="DB042-bodb02" select="bodbDownlineNet,bodbDownlineNetView" viewers="" isFunction="0"></info>*/	
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

		SELECT DISTINCT o.orId as MatchID, o.leagueid, l.sporttype, o.teamId As HomeID, 0 As AwayID, 0 AS livehomescore, 0 AS liveawayscore, '' as Showtime,'outright' AS TableName
		FROM  dbo.outright o WITH (NOLOCK) 
		INNER JOIN dbo.League l WITH (NOLOCK) 
			ON l.leagueid = o.leagueid
		WHERE o.oddsstatus IN ('Running','suspend', 'closePrice') 
				AND o.kickofftime > CURRENT_TIMESTAMP					
				AND @Type IN (0,4)	
				AND l.isTest <= @isTest
				AND (l.leagueid = @leagueid OR @leagueid = 0)
				AND (','+@SporttypeList+',' LIKE '%,'+ CONVERT(VARCHAR(5),l.Sporttype) + ',%' OR @SporttypeList = '')
				
		UNION ALL 
		
		SELECT  DISTINCT m.matchid as MatchID, m.leagueid, m.sporttype, 
				m.HomeID, m.AwayID, m.livehomescore, m.liveawayscore, m.showtime,
				'Match' AS TableName
		FROM  dbo.Match m  WITH (NOLOCK) 
		INNER JOIN dbo.Odds o WITH (NOLOCK) 
			ON m.matchid = o.matchid		
		WHERE   
			m.kickofftime > DATEADD(hour,-12,CURRENT_TIMESTAMP)  -- event started
			AND m.eventstatus='running' 							
			AND o.oddsstatus in ('running','suspend','closePrice') 		
			AND (
					(o.liveindicator = 1 AND @Type IN (0,1)	)    --- In play
					OR (o.liveindicator = 0 
						AND @Type IN (0,2,3)  --- not in play
						AND (
								(CONVERT(DATE,m.kickofftime) <= CONVERT(DATE,CURRENT_TIMESTAMP) AND @Type IN (0,2))	--- today						
								OR (CONVERT(DATE,m.kickofftime) > CONVERT(DATE,CURRENT_TIMESTAMP) AND @Type IN (0,3))  --- early
							)
						)				
				)			
			AND EXISTS ( SELECT 1 FROM League l WITH (NOLOCK) 
						 WHERE l.leagueid = m.leagueid 
								AND l.isTest <= @isTest AND (leagueid = @leagueid OR @leagueid = 0)
								AND (','+@SporttypeList+',' LIKE '%,'+ CONVERT(VARCHAR(5),l.Sporttype) + ',%' OR @SporttypeList = '')
								)		
			
	
GO
GRANT SELECT ON [dbo].[CS_f_TotalBets_Event_Sel] TO [bodbDownlineNet]
GO
GRANT SELECT ON [dbo].[CS_f_TotalBets_Event_Sel] TO [bodbDownlineNetView]
GO 