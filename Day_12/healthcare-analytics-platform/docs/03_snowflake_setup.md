# 3. Snowflake Setup (beginner, step-by-step)

> Run the scripts in `/snowflake` in order. They are heavily commented.

## A. Create a trial account
1. https://signup.snowflake.com → choose **Enterprise**, cloud = **AWS**,
   region = **same as your S3 bucket**. Verify email, set username/password.
2. Open a **Worksheet** (the SQL editor).

## B. Snowflake architecture in one minute
- **Storage** (your tables) and **Compute** (warehouses) are separate and billed separately.
- A **warehouse** is a cluster you turn on to run queries; auto-suspend saves money.
- **Database → Schema → Table** is the object hierarchy.
- **Roles** own objects and privileges (RBAC). `ACCOUNTADMIN` is the top role.

## C. Run the scripts
| Order | File | What it does | Run as |
|---|---|---|---|
| 1 | `01_account_setup.sql` | warehouse, db, 4 schemas, `HC_TRANSFORMER` role + grants | ACCOUNTADMIN |
| 2 | `02_storage_integration.sql` | secure S3 link; **`DESC INTEGRATION`** gives the ARN + external id for AWS | ACCOUNTADMIN |
| 3 | `03_file_formats_stages.sql` | CSV file format + external stage; `LIST` to verify | ACCOUNTADMIN |
| 4 | `04_raw_tables_ddl.sql` | RAW landing tables | ACCOUNTADMIN |
| 5 | `05_copy_into.sql` | loads the 3 CSVs from S3 | ACCOUNTADMIN |
| 6 | `06_validation.sql` | row counts, orphan-FK check, status mix | any |

## D. The integration handshake (the one tricky part)
1. Run script 02. In the `DESC INTEGRATION HC_S3_INT` output copy
   `STORAGE_AWS_IAM_USER_ARN` and `STORAGE_AWS_EXTERNAL_ID`.
2. Paste both into the **Trust relationship** of `snowflake-hc-role` in AWS (doc 2, step D3).
3. Now run scripts 03–05. `LIST @...HC_S3_STAGE` proving access, then `COPY INTO`.

## E. Validate
`06_validation.sql` should show 50,000 / 50,000 / 50,000 and **zero** orphan FKs.
