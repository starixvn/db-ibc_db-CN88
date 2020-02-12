use bodb_Summary
go

/*
	Created: 20200117@Percy
	DB: DBSUM.bodb_Summary
	Task: Regen data for CN88 Customer - Gen data from temp table
*/

select custid, winlostdate, productid, sporttype, bettype, islive, CancelType, HouseTurnover
into #__source
from dbarc.bodb_archive.dbo.CS_SumCancelled_p_xtest with (nolock)

update s with (rowlock)
set s.HouseTurnover = t.HouseTurnover
from dbo.CS_SumCancelled s
	inner join #__source t
		on s.custid = t.custid
			and s.winlostdate = t.winlostdate
			and s.sporttype = t.sporttype
			and s.bettype = t.bettype
			and s.islive = t.islive
			and s.CancelType = t.CancelType