with src as (
    select * from {{ source('raw', 'treatment_records') }}
)
select
    treatment_id,
    admission_id,
    doctor_id,
    procedure_code,
    treatment_date,
    cost,
    case outcome
        when 'S' then 'Success'
        when 'P' then 'Partial'
        when 'F' then 'Failed'
    end                                              as outcome
from src
