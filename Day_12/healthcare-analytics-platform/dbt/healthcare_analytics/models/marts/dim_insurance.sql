select
    insurance_id     as insurance_key,
    insurance_id,
    insurer_name,
    plan_type
from {{ ref('seed_insurers') }}
