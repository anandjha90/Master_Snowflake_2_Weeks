select
    doctor_id        as doctor_key,
    doctor_id,
    doctor_name,
    specialty,
    years_experience,
    case
        when years_experience < 5  then 'Junior'
        when years_experience < 15 then 'Mid'
        else 'Senior'
    end as seniority_band
from {{ ref('seed_doctors') }}
