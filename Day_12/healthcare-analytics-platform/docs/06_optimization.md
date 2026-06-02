# 6. Performance Optimization

## Snowflake
- **Warehouse sizing**: start `XSMALL`; size up only if `dbt run` is slow.
  Use a separate larger warehouse for the load, a small one for BI. Keep
  `AUTO_SUSPEND=60` and `AUTO_RESUME=TRUE` to avoid idle credit burn.
- **Micro-partitions**: Snowflake auto-partitions on load order; you rarely manage this.
- **Clustering**: only for large tables (>1 TB) queried by a filter column. For this
  project clustering is unnecessary; if `fact_admissions` grew huge and was usually
  filtered by date: `ALTER TABLE fact_admissions CLUSTER BY (admit_date);`
- **Query optimization**: select only needed columns, filter early, prefer joins on
  the surrogate `_key` columns, and use the **Query Profile** to find spilling.
- **Result cache**: identical queries within 24h return instantly for free.

## dbt
- **Materializations**: views for staging (cheap, always fresh), ephemeral for
  intermediate (inlined, no objects), tables for marts (fast BI reads).
- **Incremental models**: for very large facts, switch to incremental so only new
  rows are processed:
  ```sql
  {{ config(materialized='incremental', unique_key='admission_id') }}
  ... {% if is_incremental() %} where admit_date > (select max(admit_date) from {{ this }}) {% endif %}
  ```
- **Testing strategy**: keep cheap tests (`unique`, `not_null`) on every model;
  run heavier `relationships` tests in CI, not on every dev save.
- **Threads**: set `threads: 4–8` so independent models build in parallel.
- **Source freshness**: `dbt source freshness` warns when S3 loads go stale.
