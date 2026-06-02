with src as (
    select * from {{ source('raw', 'patient_admissions') }}
)
select
    admission_id,
    patient_id,
    doctor_id,
    hospital_id,
    department,
    diagnosis_code,
    case admission_type
        when 'EMG' then 'Emergency'
        when 'URG' then 'Urgent'
        when 'ELC' then 'Elective'
    end                                              as admission_type,
    admit_date,
    -- discharge_date is derived: admit + length_of_stay
    dateadd(day, length_of_stay, admit_date)         as discharge_date,
    length_of_stay,
    cast(readmission_flag as boolean)                as is_readmission
from src
