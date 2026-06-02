{% snapshot snap_doctors %}
{{
    config(
      target_schema='snapshots',
      unique_key='doctor_id',
      strategy='check',
      check_cols=['specialty','years_experience']
    )
}}
-- Tracks history of doctor attributes. If a doctor's specialty or
-- experience changes in the seed, a new versioned row is created
-- with dbt_valid_from / dbt_valid_to (Slowly Changing Dimension Type 2).
select doctor_id, doctor_name, specialty, years_experience
from {{ ref('seed_doctors') }}
{% endsnapshot %}
