-- Grain: one row per treatment.
with t as (select * from {{ ref('stg_treatments') }}),
     a as (select admission_id, patient_id, hospital_id from {{ ref('stg_admissions') }})
select
    t.treatment_id,
    t.admission_id,
    a.patient_id        as patient_key,
    t.doctor_id         as doctor_key,
    a.hospital_id       as hospital_key,
    t.procedure_code,
    t.treatment_date,
    t.cost,
    t.outcome,
    case when t.outcome = 'Success' then 1 else 0 end as is_success
from t
left join a on t.admission_id = a.admission_id
