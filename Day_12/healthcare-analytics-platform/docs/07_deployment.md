# 7. Deployment / Production Workflow

```
 1. New CSVs land in  s3://<bucket>/healthcare/   (manual upload or scheduled drop)
 2. Snowflake task / manual run: COPY INTO RAW.*  (load metadata skips dupes)
 3. dbt Cloud scheduled job:
        dbt deps  ->  dbt seed  ->  dbt run  ->  dbt snapshot  ->  dbt test
 4. dbt docs generated & served on each run
 5. BI tool / SQL reads MARTS.*  (the exposure documents this dependency)
```

## Promotion path (dev -> prod)
- **Dev**: developers build into personal schema `dbt_<name>` from a branch.
- **CI**: on Pull Request, dbt Cloud runs `dbt build --select state:modified+`
  against a CI schema (slim CI) and blocks merge on test failure.
- **Prod**: on merge to `main`, the deployment job builds into `MARTS` on a schedule.

## Operational guardrails
- `dbt test` failures fail the job → bad data never reaches BI.
- `dbt source freshness` alerts if a daily S3 file didn't arrive.
- Snapshots run **before** tests so SCD2 history is captured each run.
- Re-loads: `COPY INTO ... FORCE=TRUE` only when intentionally reprocessing.
