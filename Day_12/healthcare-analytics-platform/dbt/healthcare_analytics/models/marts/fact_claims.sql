-- Grain: one row per claim.
with c as (select * from {{ ref('stg_claims') }}),
     a as (select admission_id, patient_id from {{ ref('stg_admissions') }})
select
    c.claim_id,
    c.admission_id,
    a.patient_id        as patient_key,
    c.insurance_id      as insurance_key,
    c.claim_amount,
    c.approved_amount,
    (c.claim_amount - c.approved_amount) as denied_amount,
    c.claim_status,
    c.claim_date,
    c.settle_date,
    c.days_to_settle
from c
left join a on c.admission_id = a.admission_id
