use bodb_Archive
go

/*
	Created: 20200117@Percy
	DB: DBARC.bodb_Archive
	Task: Regen data for CN88 Customer - Gen data into tmp table
*/

-- 1. get data from bettrans_bk
select c.custid
into #__custids
from bodb02.dbo.custInfo c with (nolock)
	inner join bodb02.dbo.CS_CustSuper cs with (nolock) on c.srecommend = cs.custid
where c.roleid = 1

create table #__bettrans
(
	srecommend int,mrecommend int,recommend int,custid int,matchid int
	,winlostdate smalldatetime,bettype smallint,livehomescore smallint,liveindicator bit
	,stake money,tpositiontaking smallmoney,ExtraInfo varchar(1000)
)

/*
-- check on DB052/DB053: 0 row for bettype 2799 --> no need left join bettransm
select count(1)
from bodb_Summary.dbo.CS_SumCancelled with (nolock)
where bettype = 2799
*/

insert into #__bettrans
(
	srecommend,mrecommend,recommend,custid,matchid
	,winlostdate,bettype,livehomescore,liveindicator
	,stake,tpositiontaking,ExtraInfo
)
select
	b.srecommend,b.mrecommend,b.recommend,b.custid,b.matchid
	,b.winlostdate,b.bettype,b.livehomescore,b.liveindicator
	,b.stake,b.tpositiontaking,b.ExtraInfo
from dbo.bettrans_bk b with (nolock, index = ix_custid)
	inner join #__custids c on b.custid = c.custid
	--outer apply (select top 1 bm.matchid from dbo.bettransm bm with (nolock) where b.refno = bm.refno AND b.bettype = 2799) as bm
where b.winlostdate >= '2019-04-15'
	and b.statusID in (101, 102, 103)

-- 2. get eventtype, extraPT
select
	b.winlostdate,b.srecommend,b.mrecommend,b.recommend,b.custid,b.matchid,s.ProductID,b.bettype
	,case when b.bettype = 2799 then 1 else s.eventtype end as eventtype
	,case when b.bettype = 29 then case when b.livehomescore = 1 then 1 else 0 end else b.liveindicator end as IsLive
	,count(1) as Wager
	,sum(b.stake * (1 - b.tpositiontaking - isnull(e.ExtraPT, 0))) as HouseTurnover
	,case when b.ExtraInfo like '%p1%' AND t.c = 1 then 2 else 1 end as CancelType
into #__tmpdata
from #__bettrans b
	cross apply (
		select top 1 sbm.ProductID, sbm.eventtype from bodb02.dbo.CS_SportBettypeMatrix sbm with (nolock)
		where b.bettype = sbm.bettype
	) as s
	outer apply (
		select top 1 a.ExtraPT from bodb02.dbo.Acc_GroupExtraPTSetting a with (nolock)
		where b.srecommend = a.superid and s.ProductId = a.ProductId and a.Sporttype = 0 AND a.SubProduct = ''
			and b.winlostdate between a.FromDate AND a.ToDate
	) as e
	outer apply (select cast(('<xml>' + isnull(b.ExtraInfo, '') + '</xml>') as xml).value('data(/xml/p1/@ab)[1]','TINYINT')) as t(c)
group by
	b.winlostdate,b.srecommend,b.mrecommend,b.recommend,b.custid,b.matchid,s.ProductID,b.bettype
	,case when b.bettype = 2799 then 1 else s.eventtype end
	,case when b.bettype = 29 then case when b.livehomescore = 1 then 1 else 0 end else b.liveindicator end
	,case when b.ExtraInfo like '%p1%' AND t.c = 1 then 2 else 1 end

-- 3. get sporttype from matchid
select
	b.winlostdate,b.srecommend,b.mrecommend,b.recommend,b.custid,b.ProductId,m.Sporttype,b.bettype,b.IsLive,b.CancelType
	,sum(Wager) as Wager
	,sum(b.HouseTurnover) as HouseTurnover
into #__CS_SumCancelled_p_xtest
from #__tmpdata b
	cross apply (
		select m.sporttype
		from dbo.match_bk m with (nolock)
		where b.matchid = m.matchid and b.eventtype = 1 -- included Betradar VS Parlay

		union all
		select l.sporttype
		from dbo.outright_bk o with (nolock)
			inner join bodb02.dbo.League l with (nolock) on o.leagueid = l.leagueid
		where b.matchid = o.orid and b.eventtype = 2

		union all
		select r.sporttype
		from bodb02.dbo.VSRaceInfo r with (nolock)
		where b.matchid = r.EventID and b.eventtype = 3

		union all
		select case when b.matchid = 29 then 0 else b.matchid end as sporttype -- sb parlay: sporttype = 0
		where b.matchid <> 2799 and b.eventtype = 0
	) as m
group by
	b.winlostdate,b.srecommend,b.mrecommend,b.recommend,b.custid,b.ProductId,m.Sporttype,b.bettype,b.IsLive,b.CancelType

-- 4. final data
insert into dbo.CS_SumCancelled_p_xtest
(
	custid,winlostdate,ProductId,Sporttype,bettype,IsLive,CancelType,Wager,HouseTurnover
)
-- member
select
	custid,winlostdate,ProductId,Sporttype,bettype,IsLive,CancelType,Wager,HouseTurnover
from #__CS_SumCancelled_p_xtest
-- agent
union all
select
	recommend,winlostdate,ProductId,Sporttype,bettype,IsLive,CancelType
	,sum(Wager) as Wager
	,sum(HouseTurnover) as HouseTurnover
from #__CS_SumCancelled_p_xtest
group by
	recommend,winlostdate,ProductId,Sporttype,bettype,IsLive,CancelType
-- master
union all
select
	mrecommend,winlostdate,ProductId,Sporttype,bettype,IsLive,CancelType
	,sum(Wager) as Wager
	,sum(HouseTurnover) as HouseTurnover
from #__CS_SumCancelled_p_xtest
group by
	mrecommend,winlostdate,ProductId,Sporttype,bettype,IsLive,CancelType
-- super
union all
select
	srecommend,winlostdate,ProductId,Sporttype,bettype,IsLive,CancelType
	,sum(Wager) as Wager
	,sum(HouseTurnover) as HouseTurnover
from #__CS_SumCancelled_p_xtest
group by
	srecommend,winlostdate,ProductId,Sporttype,bettype,IsLive,CancelType

drop table #__bettrans
drop table #__tmpdata
drop table #__CS_SumCancelled_p_xtest
drop table #__custids