# Healthcare Patient Journey & Revenue Analytics Platform

End-to-end analytics project using **only AWS S3 + Snowflake + dbt Cloud**.
Designed for a 2-hour live training and as a resume/interview project.

## What's inside
```
healthcare-analytics-platform/
├── README.md
├── data/                     3 source CSVs (50,000 rows each, < 3 MB)
│     patient_admissions.csv  treatment_records.csv  insurance_claims.csv
├── snowflake/                6 ordered SQL scripts (setup -> load -> validate)
├── dbt/healthcare_analytics/ full dbt project (staging -> intermediate -> marts)
└── docs/                     9 guides (architecture, AWS, Snowflake, dbt, KPIs,
                              optimization, deployment, 2-hr agenda, 80 interview Q&A)
```

## Data model (star schema)
- **Facts:** `fact_admissions` (per admission), `fact_treatments` (per treatment), `fact_claims` (per claim)
- **Dims:** `dim_patient`, `dim_doctor`, `dim_hospital`, `dim_insurance`
- **Snapshot:** `snap_doctors` (SCD2 history of doctor attributes)
- Everything keyed off `admission_id`. Verified zero orphan foreign keys.

## Run order (the whole pipeline)
1. **AWS** — `docs/02_aws_s3_setup.md`: bucket + `healthcare/` folder + IAM role; upload the 3 CSVs.
2. **Snowflake** — run `snowflake/01..06` in order (`docs/03_snowflake_setup.md`).
3. **dbt Cloud** — connect to Snowflake (`docs/04_dbt_cloud_setup.md`), then:
   ```
   dbt deps && dbt seed && dbt run && dbt snapshot && dbt test && dbt docs generate
   ```
4. **KPIs** — run queries from `docs/05_kpis.md` against `HC_DB.MARTS`.

## Validation status
- dbt project parses cleanly: **13 models, 1 snapshot, 36 data tests, 3 seeds, 3 sources, 1 exposure**.
- Datasets verified: 50,000 rows each, all foreign keys resolve.

## Tech notes
- `discharge_date` is intentionally derived in staging (`admit_date + length_of_stay`) — a teaching moment, and it keeps the CSV under 3 MB.
- Claim mix is ~70% approved / 15% rejected / 15% pending; rejected & pending have `approved_amount = 0`.
- Lookup names (doctors/hospitals/insurers) ship as dbt **seeds**, not in the big CSVs.
