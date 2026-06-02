with src as (
    select * from {{ source('raw', 'insurance_claims') }}
)
select
    claim_id,
    admission_id,
    insurance_id,
    claim_amount,
    approved_amount,
    case claim_status
        when 'A' then 'Approved'
        when 'R' then 'Rejected'
        when 'P' then 'Pending'
    end                                              as claim_status,
    claim_date,
    settle_date,
    datediff(day, claim_date, settle_date)           as days_to_settle
from src
