-- Derived dimension: patients don't have a source master, so we build
-- the dimension from their admission history.
with pm as (select * from {{ ref('int_patient_metrics') }})
select
    patient_id                              as patient_key,
    patient_id,
    total_admissions,
    avg_los_days,
    readmission_count,
    case when readmission_count > 0 then true else false end as has_readmitted,
    first_admit_date,
    last_admit_date
from pm
