# 1. Architecture

## Stack (only these three tools)
**AWS S3** (file storage) → **Snowflake** (warehouse) → **dbt Cloud** (transformation).

## Data flow
```
        ┌─────────────┐
        │   AWS S3    │   3 CSVs: admissions, treatments, claims
        │ /healthcare │
        └──────┬──────┘
               │  storage integration + external stage
               ▼
        ┌─────────────────────────────────────────────┐
        │                 SNOWFLAKE                     │
        │                                               │
        │  RAW schema      (COPY INTO from S3)          │  <- landing
        │      │                                        │
        │      ▼   dbt                                  │
        │  STAGING schema  (views: clean + typed)       │  <- stg_*
        │      │                                        │
        │      ▼   dbt (ephemeral)                      │
        │  intermediate    (reusable rollups)           │  <- int_*
        │      │                                        │
        │      ▼   dbt                                  │
        │  MARTS schema    (star schema: dims + facts)  │  <- dim_*, fact_*
        │                                               │
        │  SNAPSHOTS schema (SCD2 history)              │
        └─────────────────────────────────────────────┘
               ▲
               │  runs jobs, tests, docs
        ┌──────┴──────┐
        │  dbt Cloud  │
        └─────────────┘
```

## Layer responsibilities
| Layer | Schema | dbt materialization | Purpose |
|---|---|---|---|
| Landing / Raw | `RAW` | (loaded by COPY INTO) | Exact copy of source CSVs |
| Staging | `STAGING` | view | Rename, recast, decode codes, derive columns |
| Intermediate | (none — ephemeral) | ephemeral | Reusable business rollups, never persisted |
| Marts | `MARTS` | table | Star schema dims & facts for BI/SQL |
| Snapshots | `SNAPSHOTS` | snapshot | Slowly Changing Dimension Type 2 history |

## Naming conventions
- Sources: `raw.<entity>` (e.g. `raw.patient_admissions`)
- Staging: `stg_<entity>`  • Intermediate: `int_<subject>_metrics`
- Dimensions: `dim_<entity>` with surrogate `_key` columns
- Facts: `fact_<process>` at a stated grain (one row per admission / treatment / claim)
- YAML config files prefixed `_hc__` so they sort to the top of each folder.

## S3 folder structure
```
s3://<your-bucket>/healthcare/
    patient_admissions.csv
    treatment_records.csv
    insurance_claims.csv
```
