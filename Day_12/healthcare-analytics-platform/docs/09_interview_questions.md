# 9. Interview Questions with Answers

## Part A — Snowflake (30)

1. **What makes Snowflake's architecture unique?** Separation of storage, compute (virtual warehouses) and cloud services. Each scales independently, so you can resize compute without touching data.
2. **What is a virtual warehouse?** An MPP compute cluster that runs queries/loads. Billed per second while running; can auto-suspend/resume.
3. **Storage vs compute billing?** Storage billed per TB/month of compressed data; compute billed per second of warehouse runtime. They are independent.
4. **What is a micro-partition?** Snowflake's automatic ~50–500 MB compressed columnar storage units with min/max metadata enabling pruning. You don't manage them.
5. **What is pruning?** Skipping micro-partitions whose min/max metadata can't match a query's filter, reducing scanned data.
6. **What is clustering / a clustering key?** An optional ordering hint for very large tables to co-locate filter values and improve pruning. Costly to maintain; use sparingly.
7. **Explain the three caches.** Result cache (24h identical-query results), local disk cache (warehouse SSD), and metadata cache.
8. **What is Time Travel?** Query/restore historical data up to the retention period (1 day standard, up to 90 Enterprise) via `AT`/`BEFORE`.
9. **What is Fail-safe?** A non-configurable 7-day Snowflake-managed recovery period after Time Travel expires.
10. **Transient vs permanent table?** Transient tables have no Fail-safe and shorter Time Travel — cheaper, for reproducible/staging data.
11. **What is zero-copy cloning?** `CREATE TABLE x CLONE y` creates a metadata-only copy; storage is shared until changes diverge.
12. **What is a stage?** A pointer to file storage for loading/unloading. Internal (Snowflake-managed) or external (S3/GCS/Azure).
13. **What is a storage integration?** A secure, key-less object that lets Snowflake assume a cloud IAM role to access external storage.
14. **What does COPY INTO do?** Bulk-loads files from a stage into a table; tracks load metadata to avoid reloading the same file.
15. **How do you force a reload?** `COPY INTO ... FORCE = TRUE` (ignores load history).
16. **What is a file format object?** Reusable parsing rules (delimiter, header skip, NULL handling) referenced by stages/COPY.
17. **What is Snowpipe?** Continuous, event-driven micro-batch loading using `COPY` under the hood, triggered by cloud notifications.
18. **Explain RBAC in Snowflake.** Privileges are granted to roles; roles to users (or other roles). Access is the union of a user's active role hierarchy.
19. **Order ACCOUNTADMIN, SYSADMIN, SECURITYADMIN.** ACCOUNTADMIN top; SECURITYADMIN manages grants/users; SYSADMIN owns databases/warehouses. Custom roles usually under SYSADMIN.
20. **Scale up vs scale out?** Scale up = bigger warehouse (more power per query). Scale out = multi-cluster warehouse (more concurrency).
21. **What is a multi-cluster warehouse?** Auto-adds clusters under concurrent load and removes them when idle (Enterprise+).
22. **How to control cost?** Auto-suspend, right-size warehouses, resource monitors with credit quotas, transient tables, result cache.
23. **What is a resource monitor?** Tracks credit usage and can notify/suspend warehouses at thresholds.
24. **Variant / semi-structured support?** `VARIANT` stores JSON/Avro/Parquet; query with `:` path and `FLATTEN`.
25. **What is a secure view?** A view that hides its definition and underlying data from unauthorized roles; used for data sharing.
26. **What is Secure Data Sharing?** Share live data to other accounts without copying, via shares/reader accounts.
27. **What are streams & tasks?** A stream captures CDC (changed rows); a task schedules SQL — together they build pipelines.
28. **How does Snowflake handle concurrency?** Each warehouse runs queries independently; multi-cluster adds clusters to avoid queuing.
29. **What is the Query Profile?** A visual execution plan showing time per operator, partitions scanned, and spilling — the main tuning tool.
30. **How would you optimize a slow query?** Check Query Profile, reduce scanned columns/partitions, filter early, add clustering only if justified, size the warehouse appropriately, leverage caching.

## Part B — dbt (30)

1. **What is dbt?** A transformation framework: you write `SELECT` models in SQL/Jinja and dbt handles DDL, dependencies, testing and docs (the **T** in ELT).
2. **dbt Core vs Cloud?** Core is the open-source CLI; Cloud adds an IDE, scheduler, CI, hosted docs and managed environments.
3. **What is a model?** A `.sql` file with one `SELECT`; dbt wraps it in `CREATE TABLE/VIEW` based on its materialization.
4. **List the materializations.** view, table, incremental, ephemeral (and snapshot as a special case).
5. **When ephemeral?** Lightweight reusable logic you don't need to query directly — it's inlined as a CTE into downstream models (our `int_*`).
6. **What is `ref()`?** A function that references another model, builds the DAG, and inserts the correct schema-qualified name per environment.
7. **What is `source()`?** References raw tables declared in a `sources` YAML; enables lineage and freshness checks.
8. **How does dbt build the DAG?** From `ref()`/`source()` calls, computing build order and parallelism.
9. **What are the built-in generic tests?** `unique`, `not_null`, `accepted_values`, `relationships`.
10. **Singular vs generic test?** Singular = one `.sql` file returning failing rows; generic = parameterized, reusable, attached in YAML.
11. **What is `dbt_utils`?** A community macro package (e.g. `accepted_range`, `surrogate_key`, `equal_rowcount`).
12. **What is a seed?** A small CSV in `/seeds` loaded with `dbt seed` — ideal for lookups (our doctors/hospitals/insurers).
13. **What is a snapshot?** dbt's SCD2 implementation that records attribute history with `dbt_valid_from`/`dbt_valid_to`.
14. **timestamp vs check strategy?** `timestamp` uses an updated-at column; `check` compares listed columns for changes (we use `check`).
15. **What is an incremental model?** Processes only new/changed rows after the first full build, guarded by `is_incremental()`.
16. **Role of `unique_key` in incremental?** Lets dbt update/merge existing rows instead of duplicating them.
17. **What are macros?** Reusable Jinja/SQL functions (our `money()`); promote DRY SQL.
18. **What is `{{ this }}`?** The current model's relation — used in incremental filters.
19. **What are exposures?** YAML-declared downstream consumers (dashboards, ML) that appear in lineage/docs.
20. **What is source freshness?** `dbt source freshness` checks `loaded_at_field` vs warn/error thresholds.
21. **How does dbt do documentation?** `dbt docs generate` + `dbt docs serve` builds a searchable site with lineage from descriptions/tests.
22. **What is `dbt build`?** Runs models, tests, snapshots and seeds in DAG order in one command.
23. **What are tags / selectors?** Labels and `--select`/`--exclude` syntax to run subsets (e.g. `--select staging+`).
24. **Explain `+` selectors.** `model+` = model and descendants; `+model` = model and ancestors; `state:modified+` = changed nodes and downstream.
25. **What is Slim CI?** Running only modified models + downstream by comparing to a deferred prod manifest — fast PR checks.
26. **How do you parametrize environments?** `target.name`, env vars, and per-folder `+schema`/`+materialized` configs in `dbt_project.yml`.
27. **What is a custom schema?** dbt's `generate_schema_name` macro controls final schema; default concatenates the configured schema.
28. **How to handle PII?** Limit columns in staging, use secure views, mask in marts, document with `meta`/tags, restrict role grants.
29. **Project structure best practice?** Layered staging → intermediate → marts, one source of truth per entity, tests at every layer.
30. **Why ELT over ETL with dbt?** Load raw first (cheap storage), transform in-warehouse with version-controlled, tested SQL — reproducible and auditable.

## Part C — Healthcare Analytics (20)

1. **What is readmission rate and why track it?** Share of patients readmitted within a window (often 30 days); a core quality and reimbursement metric.
2. **What is Average Length of Stay (ALOS)?** Mean inpatient days; balances care quality vs bed turnover and cost.
3. **What is bed occupancy rate?** Occupied bed-days / available bed-days; signals capacity stress.
4. **Difference: charge, cost, reimbursement?** Charge = list price; cost = what the provider spends; reimbursement = what payer actually pays (our `approved_amount`).
5. **What is an ICD code?** Standardized diagnosis classification (ICD-10) used for billing and analytics.
6. **What is a CPT/procedure code?** Codes describing procedures/treatments performed (our `procedure_code`).
7. **What is the patient journey?** The sequence admission → treatment → discharge → claim, which this model links via `admission_id`.
8. **What is claim approval vs rejection rate?** Approved (or rejected) claims / total claims — payer-relationship and revenue-cycle health.
9. **What is denial management?** Analyzing/ reducing rejected or under-paid claims (our `denied_amount`).
10. **What is revenue cycle management (RCM)?** End-to-end financial process from admission to final payment.
11. **What is case mix / acuity?** The complexity/severity profile of patients; affects expected LOS and cost.
12. **Why is HIPAA relevant?** US law protecting PHI; drives de-identification, access control, and audit requirements.
13. **What is PHI?** Protected Health Information — identifiers tied to health data; must be secured/masked.
14. **How would you de-identify this data?** Drop direct identifiers, hash patient IDs, generalize dates, restrict via roles/secure views.
15. **What is a payer mix?** Distribution of claims across insurers/plan types; affects revenue predictability (our `dim_insurance.plan_type`).
16. **What is treatment effectiveness analysis?** Comparing outcomes (success/partial/failed) across procedures/doctors to guide care.
17. **What is a star schema's value here?** Fast, intuitive slicing of facts (admissions/treatments/claims) by conformed dims (patient/doctor/hospital/insurer).
18. **What is days-to-settle / claim aging?** Time from claim submission to settlement; long aging signals cash-flow risk.
19. **Name 3 operational KPIs for a hospital exec.** Occupancy, ALOS, readmission rate (plus claim approval rate and revenue per admission).
20. **How could this platform reduce readmissions?** Identify high-readmission diagnoses/doctors/hospitals, correlate with LOS and outcomes, and target interventions.
