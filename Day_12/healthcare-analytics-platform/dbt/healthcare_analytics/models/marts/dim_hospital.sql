select
    hospital_id      as hospital_key,
    hospital_id,
    hospital_name,
    city,
    bed_capacity
from {{ ref('seed_hospitals') }}
