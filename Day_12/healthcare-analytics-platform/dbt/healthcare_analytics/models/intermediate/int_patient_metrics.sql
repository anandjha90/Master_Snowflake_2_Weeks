-- One row per patient: lifetime admission behaviour.
with adm as (select * from {{ ref('stg_admissions') }})
select
    patient_id,
    count(*)                                  as total_admissions,
    sum(length_of_stay)                       as total_los_days,
    round(avg(length_of_stay), 1)             as avg_los_days,
    sum(case when is_readmission then 1 else 0 end) as readmission_count,
    min(admit_date)                           as first_admit_date,
    max(admit_date)                           as last_admit_date
from adm
group by patient_id
