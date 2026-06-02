-- One row per admission: treatment cost + success rollup.
with t as (select * from {{ ref('stg_treatments') }})
select
    admission_id,
    count(*)                                            as treatment_count,
    {{ money('sum(cost)') }}                            as total_treatment_cost,
    sum(case when outcome = 'Success' then 1 else 0 end) as success_count,
    round(100.0 * sum(case when outcome = 'Success' then 1 else 0 end)
          / nullif(count(*), 0), 1)                     as success_rate_pct
from t
group by admission_id
