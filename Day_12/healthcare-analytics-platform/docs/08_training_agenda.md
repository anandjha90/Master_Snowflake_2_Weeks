# 8. Two-Hour Live Training Agenda (120 min)

| # | Module | Time | What you do live |
|---|---|---|---|
| 1 | Introduction & architecture | 10 min | Walk the S3→Snowflake→dbt diagram; show the 3 datasets & star schema goal |
| 2 | AWS setup | 12 min | Create bucket, `healthcare/` folder, upload 3 CSVs, create IAM policy/role |
| 3 | Snowflake setup | 15 min | Run `01`–`02`; explain warehouse/db/schema/roles; do the integration handshake |
| 4 | Data loading | 12 min | Run `03`–`05` (file format, stage, RAW DDL, COPY INTO); `06` validation |
| 5 | dbt Cloud setup | 12 min | Connect dbt→Snowflake, load project, `dbt deps`, `dbt seed` |
| 6 | Transformations | 18 min | Build staging + intermediate; explain views vs ephemeral, code decoding, derived discharge_date |
| 7 | Star schema | 15 min | Build dims & facts; explain grain, surrogate keys, conformed dimensions |
| 8 | Testing & snapshots | 12 min | `dbt test` (unique/not_null/accepted_values/relationships) + run the SCD2 snapshot |
| 9 | KPIs | 8 min | Run 4–5 KPI queries live (readmission, ALOS, approval rate, revenue by dept) |
| 10 | Interview Q&A | 4 min | Rapid-fire 3–4 questions from doc 9; point to the full bank |
| — | Buffer | ~ | Absorb overrun in any module |

**Pre-class checklist:** AWS account ready, Snowflake trial ready, dbt Cloud account
ready, the 3 CSVs and `/snowflake` scripts open in tabs.
