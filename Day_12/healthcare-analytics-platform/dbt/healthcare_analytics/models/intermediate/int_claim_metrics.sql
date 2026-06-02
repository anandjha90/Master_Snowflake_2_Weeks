-- One row per admission: claim financials rollup.
with c as (select * from {{ ref('stg_claims') }})
select
    admission_id,
    count(*)                                                   as claim_count,
    {{ money('sum(claim_amount)') }}                           as total_claimed,
    {{ money('sum(approved_amount)') }}                        as total_approved,
    sum(case when claim_status = 'Approved' then 1 else 0 end) as approved_count,
    sum(case when claim_status = 'Rejected' then 1 else 0 end) as rejected_count
from c
group by admission_id
