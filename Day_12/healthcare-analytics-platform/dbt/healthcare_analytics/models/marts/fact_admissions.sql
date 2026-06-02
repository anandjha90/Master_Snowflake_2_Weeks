-- Grain: one row per admission. Conformed dims + treatment/claim rollups.
with a  as (select * from {{ ref('stg_admissions') }}),
     tm as (select * from {{ ref('int_treatment_metrics') }}),
     cm as (select * from {{ ref('int_claim_metrics') }})
select
    a.admission_id,
    a.patient_id            as patient_key,
    a.doctor_id             as doctor_key,
    a.hospital_id           as hospital_key,
    a.admit_date,
    a.discharge_date,
    a.department,
    a.admission_type,
    a.diagnosis_code,
    a.length_of_stay,
    a.is_readmission,
    coalesce(tm.treatment_count, 0)        as treatment_count,
    coalesce(tm.total_treatment_cost, 0)   as total_treatment_cost,
    coalesce(cm.claim_count, 0)            as claim_count,
    coalesce(cm.total_claimed, 0)          as total_claimed,
    coalesce(cm.total_approved, 0)         as total_approved
from a
left join tm on a.admission_id = tm.admission_id
left join cm on a.admission_id = cm.admission_id
