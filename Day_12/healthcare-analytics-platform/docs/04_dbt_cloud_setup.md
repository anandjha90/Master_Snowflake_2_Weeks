# 4. dbt Cloud Setup (beginner, step-by-step)

## A. Create a dbt Cloud account
1. https://www.getdbt.com → start free (Developer plan is enough for one user).
2. **Account settings → Projects → New Project**. Name: `healthcare_analytics`.

## B. Connect to Snowflake
1. Choose **Snowflake** as the warehouse. Fill:
   - **Account**: `<account>.<region>` (e.g. `ab12345.us-east-1`)
   - **Database**: `HC_DB`  • **Warehouse**: `HC_WH`  • **Role**: `HC_TRANSFORMER`
2. **Development credentials**: your Snowflake user + password (or key-pair),
   default schema e.g. `dbt_<yourname>`. Click **Test Connection**.

## C. Connect the code repository
- Easiest: **Managed repository** (dbt hosts it) → name `healthcare_analytics`.
- Or connect GitHub and push the `/dbt/healthcare_analytics` folder.

## D. Load this project
- Put the contents of `/dbt/healthcare_analytics` at the repo root.
- In the dbt Cloud IDE, run in order:
```
dbt deps      # installs dbt_utils
dbt seed      # loads doctors / hospitals / insurers into RAW
dbt run       # builds staging -> intermediate -> marts
dbt snapshot  # builds SCD2 doctor history
dbt test      # runs all 36 data tests
dbt docs generate  # builds the documentation site
```

## E. Create a deployment job
1. **Deploy → Environments → New** (type *Deployment*, schema `MARTS`).
2. **Deploy → Jobs → New Job**: commands `dbt seed`, `dbt run`, `dbt snapshot`, `dbt test`.
   Trigger: schedule (e.g. daily) or on merge. Enable **Generate docs on run**.

## F. Project structure reference
```
healthcare_analytics/
  dbt_project.yml        packages.yml      profiles_example.yml
  models/
    staging/             stg_*.sql + _hc__sources.yml + _hc__models.yml
    intermediate/        int_*.sql (ephemeral)
    marts/               dim_*, fact_* + _hc__marts.yml (+ exposure)
  macros/                dollars.sql
  snapshots/             snap_doctors.sql (SCD2)
  seeds/                 seed_doctors.csv, seed_hospitals.csv, seed_insurers.csv
  tests/                 assert_approved_not_exceed_claim.sql (singular test)
```
