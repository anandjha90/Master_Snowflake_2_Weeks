# End-to-End Data Quality Validation Pipeline
## Snowpark Python · AWS S3 · Snowflake · Complete Documentation

---

> **Version:** 1.1 
> **Stack:** Snowpark Python · AWS S3 · Snowflake · Storage Integration · Native Email Notification
> **Last Updated:** 2026-05-28

---

|---|---|---|---|
| 1 | `AS NULLS` reserved keyword in Snowflake | **Every file rejected silently** via `except Exception` | Renamed alias to `AS NULL_CNT` in `check_null_pct()` |
| 2 | FK dimension seeding off-by-one (`SEQ4()` starts at 0) | `CUST-0050` missing → FK check always failed | Replaced `SEQ4()` with `ROW_NUMBER()` → generates `CUST-0001` to `CUST-0050` |
| 3 | `RECORD_DELIMITER` missing from file formats | Last column value could include `\r` | Added `RECORD_DELIMITER = '\n'` to both `CSV_FORMAT` and `CSV_FORMAT_NO_SKIP` |
| 4 | Files 02 and 03 designed to fail | Only 1 of 7 files could ever pass | Regenerated as clean PASS files with valid data |
| 5 | File 07 was a tiny 229-byte file | With `min_file_size_bytes=100` it passed the size gate unexpectedly | Redesigned as FK violation scenario — `CUST-9001..9050` not in dimension table |
| 6 | No `USE DATABASE/SCHEMA` at startup | Unresolved object name errors if session context differs | Added `session.sql('USE DATABASE ANALYTICS_DB')` at top of `main()` |
| 7 | Silent exception swallowing | No traceback printed on unexpected SQL errors | Added `traceback.format_exc()` print inside `except Exception` block |

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Diagram](#2-architecture-diagram)
3. [Snowflake Object Inventory](#3-snowflake-object-inventory)
4. [CSV Test File Catalogue](#4-csv-test-file-catalogue)
5. [Data Quality Checks — Full Reference](#5-data-quality-checks--full-reference)
6. [Pipeline Configuration Parameters](#6-pipeline-configuration-parameters)
7. [Snowflake DDL — Setup SQL](#7-snowflake-ddl--setup-sql)
8. [Snowpark Python Script — Full Code Reference](#8-snowpark-python-script--full-code-reference)
9. [S3 File Move — How It Works](#9-s3-file-move--how-it-works)
10. [Email Notification Design](#10-email-notification-design)
11. [Execution Walkthrough](#11-execution-walkthrough)
12. [Expected Results Per File](#12-expected-results-per-file)
13. [Audit Queries](#13-audit-queries)
14. [Deployment Guide](#14-deployment-guide)
15. [Troubleshooting & FAQ](#15-troubleshooting--faq)

---

## 1. Executive Summary

This pipeline is a **parameterised, team-agnostic data quality framework** built on Snowpark Python. It intercepts CSV files landing in an AWS S3 bucket, runs **12 sequential data quality gate checks**, and only loads files into Snowflake's RAW layer if every mandatory check passes. Files that fail are quarantined, logged in full detail, and trigger automated email alerts.

### Design Principles

| Principle | Implementation |
|---|---|
| **Zero-trust ingestion** | No file loads unless all gate and threshold checks pass |
| **Team-agnostic** | Entire behaviour driven by a single config dict |
| **Full audit trail** | Every check result written to DQ_METRICS_LOG |
| **Fail-fast** | Cheap checks (file size, column count) run first |
| **Per-file independence** | One file failing does not block other files |
| **Human alerting** | Snowflake native email on every rejection |
| **100% Snowflake-native** | No boto3, no external Python packages needed |

---

## 2. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           AWS S3 BUCKET                                 │
│  s3://snowflake-dq-pipeline-bucket/transactions/                        │
│                                                                         │
│   /incoming/    ← CSV files uploaded here before pipeline runs          │
│   /processed/   ← PASS files moved here by COPY FILES + REMOVE         │
│   /quarantine/  ← FAIL files moved here by COPY FILES + REMOVE         │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │  IAM Role Trust Policy
                               │  (Storage Integration)
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│              SNOWFLAKE  — Three External Stages                         │
│  S3_TRANSACTION_STAGE           → /incoming/                            │
│  S3_TRANSACTION_STAGE_PROCESSED → /processed/                           │
│  S3_TRANSACTION_STAGE_QUARANTINE→ /quarantine/                          │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│              SNOWPARK PYTHON — DATA QUALITY ENGINE (main.py)            │
│                                                                         │
│  For each CSV file:                                                     │
│                                                                         │
│  ── GATE CHECKS (fail-fast) ───────────────────────────────────────     │
│  [1]  File Size             < 100 bytes (dev) / 1 MB (prod) → REJECT   │
│  [2]  Column Count          < 7 columns                     → REJECT   │
│  [3]  Required Column Names missing mandatory columns        → REJECT   │
│                                                                         │
│  ── THRESHOLD CHECKS ──────────────────────────────────────────────     │
│  [4]  Row Count             < 10 rows                        → REJECT   │
│  [5]  Null % per Column     > 30% null in any column         → REJECT   │
│  [6]  Data Type Validation  non-castable values              → REJECT   │
│  [7]  Primary Key Uniqueness duplicate TRANSACTION_IDs       → REJECT   │
│  [8]  Foreign Key Constraint orphan CUSTOMER_ID / PRODUCT_ID → REJECT  │
│                                                                         │
│  ── ADVISORY CHECKS (warn only — file still loads) ────────────────     │
│  [9]  Duplicate Row Check   > 5% exact duplicate rows        → WARN    │
│  [10] Date Range Sanity     future / pre-2000 dates          → WARN    │
│  [11] Numeric Range Check   negative or extreme values       → WARN    │
│  [12] Allowed Values Check  unknown STATUS / CURRENCY values → WARN    │
│                                                                         │
│         ┌──────────────────────┬──────────────────────────┐            │
│         │ ALL CHECKS PASS      │ ANY CHECK FAILS           │            │
│         ▼                      ▼                           │            │
│  COPY INTO RAW.TRANSACTION  Log to DQ_METRICS_LOG          │            │
│  COPY FILES → /processed/   COPY FILES → /quarantine/      │            │
│  REMOVE from /incoming/     REMOVE from /incoming/          │            │
│                             SYSTEM$SEND_EMAIL to recipients │            │
└─────────────────────────────────────────────────────────────────────────┘
        │                              │
        ▼                              ▼
┌──────────────────┐        ┌──────────────────────────────┐
│ ANALYTICS_DB.RAW │        │ ANALYTICS_DB.DQ_MONITORING   │
│ .TRANSACTION     │        │   FILE_PROCESSING_LOG        │
│ (clean data only)│        │   DQ_METRICS_LOG             │
└──────────────────┘        │   EMAIL_RECIPIENT_LOG        │
                            └──────────────────────────────┘
```

---

## 3. Snowflake Object Inventory

### 3.1 Databases and Schemas

| Database | Schema | Purpose |
|---|---|---|
| `ANALYTICS_DB` | `RAW` | Target schema for clean ingested data + stages + file formats |
| `ANALYTICS_DB` | `DIM` | Dimension tables (CUSTOMERS, PRODUCTS) for FK checks |
| `ANALYTICS_DB` | `DQ_MONITORING` | All audit and monitoring tables |

---

### 3.2 File Formats

| Format Name | SKIP_HEADER | RECORD_DELIMITER | Purpose |
|---|---|---|---|
| `ANALYTICS_DB.RAW.CSV_FORMAT` | 1 | `\n` | Main data loading — skips header row |
| `ANALYTICS_DB.RAW.CSV_FORMAT_NO_SKIP` | 0 | `\n` | Header reading for column count check (Check 2) |

> Set `RECORD_DELIMITER = '\n'` to match the Unix line endings produced by the CSV generator (`lineterminator='\n'`). Without this, the last column in each row would have `\r` appended, corrupting values.

---

### 3.3 External Stages

| Stage Name | S3 URL | Purpose |
|---|---|---|
| `S3_TRANSACTION_STAGE` | `/transactions/incoming/` | Landing zone — files arrive here |
| `S3_TRANSACTION_STAGE_PROCESSED` | `/transactions/processed/` | PASS destination |
| `S3_TRANSACTION_STAGE_QUARANTINE` | `/transactions/quarantine/` | FAIL destination |

---

### 3.4 RAW.TRANSACTION — Target Table

| Column | Type | Constraint | Description |
|---|---|---|---|
| TRANSACTION_ID | VARCHAR(36) | PRIMARY KEY | UUID format transaction identifier |
| CUSTOMER_ID | VARCHAR(36) | FK → DIM.CUSTOMERS | Customer who made the transaction |
| PRODUCT_ID | VARCHAR(36) | FK → DIM.PRODUCTS | Product purchased |
| TRANSACTION_DATE | DATE | NOT NULL | Date of transaction |
| AMOUNT | FLOAT | CHECK > 0 | Transaction monetary value |
| QUANTITY | INT | CHECK > 0 | Units purchased |
| STATUS | VARCHAR(20) | Allowed values | COMPLETED / PENDING / CANCELLED / REFUNDED |
| REGION | VARCHAR(50) | NOT NULL | Geographic region |
| CURRENCY | VARCHAR(3) | Allowed values | USD / INR / EUR / GBP / AED |
| CREATED_AT | TIMESTAMP_NTZ | DEFAULT NOW() | Source system timestamp |
| _DQ_PIPELINE_RUN_ID | VARCHAR(36) | Pipeline audit | UUID of pipeline run that loaded this row |
| _SOURCE_FILE_NAME | VARCHAR(500) | Pipeline audit | Name of the source S3 file |
| _LOADED_AT | TIMESTAMP_NTZ | Pipeline audit | Exact timestamp of load |

---

### 3.5 Monitoring Tables

#### `DQ_MONITORING.FILE_PROCESSING_LOG` — One Row per File

| Column | Type | Description |
|---|---|---|
| LOG_ID | INT AUTOINCREMENT | Surrogate primary key |
| PIPELINE_RUN_ID | VARCHAR(36) | UUID grouping all files in one execution |
| FILE_NAME | VARCHAR(500) | S3 file name |
| FILE_SIZE_BYTES | BIGINT | File size at time of processing |
| ROW_COUNT | INT | Number of data rows detected |
| COLUMN_COUNT | INT | Number of columns detected |
| PROCESSING_STATUS | VARCHAR(20) | `PASSED` / `REJECTED` / `SKIPPED` |
| REJECTION_REASONS | VARCHAR(4000) | Pipe-separated list of failed check names |
| ROWS_LOADED | INT | Actual rows inserted into RAW.TRANSACTION |
| PROCESSED_AT | TIMESTAMP_NTZ | Timestamp of processing |
| TEAM_NAME | VARCHAR(100) | Team that ran the pipeline (from config) |

#### `DQ_MONITORING.DQ_METRICS_LOG` — One Row per Check per File

| Column | Type | Description |
|---|---|---|
| METRIC_ID | INT AUTOINCREMENT | Surrogate primary key |
| LOG_ID | INT | FK to FILE_PROCESSING_LOG |
| PIPELINE_RUN_ID | VARCHAR(36) | Run grouping key |
| FILE_NAME | VARCHAR(500) | Source file name |
| CHECK_NUMBER | INT | Check sequence (1–12) |
| CHECK_NAME | VARCHAR(100) | e.g. `NULL_COUNT_CHECK`, `PK_UNIQUENESS_CHECK` |
| CHECK_CATEGORY | VARCHAR(20) | `GATE` / `THRESHOLD` / `ADVISORY` |
| CHECK_STATUS | VARCHAR(10) | `PASS` / `FAIL` / `WARN` / `SKIP` |
| COLUMN_NAME | VARCHAR(100) | Relevant column (NULL for file-level checks) |
| THRESHOLD_VALUE | VARCHAR(200) | Configured threshold |
| ACTUAL_VALUE | VARCHAR(200) | Observed value |
| SEVERITY | VARCHAR(10) | `CRITICAL` / `HIGH` / `MEDIUM` / `LOW` |
| NOTES | VARCHAR(2000) | Human-readable explanation |
| CHECKED_AT | TIMESTAMP_NTZ | Timestamp when check ran |

#### `DQ_MONITORING.EMAIL_RECIPIENT_LOG` — Notification Recipients

| Column | Type | Description |
|---|---|---|
| RECIPIENT_ID | INT AUTOINCREMENT | Surrogate primary key |
| EMAIL_ADDRESS | VARCHAR(200) | Recipient email |
| TEAM_NAME | VARCHAR(100) | Filter — matches `config.notification.team_name` |
| NOTIFICATION_TYPE | VARCHAR(20) | `FAILURE` / `ALL` / `SUMMARY` |
| IS_ACTIVE | BOOLEAN | Toggle without deleting |
| ADDED_BY | VARCHAR(100) | Who registered this recipient |
| ADDED_AT | TIMESTAMP_NTZ | Registration timestamp |

---

## 4. CSV Test File Catalogue

### 4.1 File Overview

| File | Rows | Cols | Scenario | Expected Result | Failing Check |
|---|---|---|---|---|---|
| `file_01_happy_path.csv` | 500 | 10 | All data clean and valid | ✅ **PASS → /processed/** | None |
| `file_02_clean_regional.csv` | 300 | 10 | Clean data — Europe/ME/APAC regions | ✅ **PASS → /processed/** | None |
| `file_03_clean_currency.csv` | 200 | 10 | Clean data — non-USD currencies only | ✅ **PASS → /processed/** | None |
| `file_04_high_nulls.csv` | 200 | 10 | AMOUNT=60% null, CUSTOMER_ID=40% null | ❌ **REJECT → /quarantine/** | Check 5: Null % |
| `file_05_duplicate_pk.csv` | 100 | 10 | 15 duplicate TRANSACTION_IDs | ❌ **REJECT → /quarantine/** | Check 7: PK Uniqueness |
| `file_06_bad_datatypes.csv` | 80 | 10 | AMOUNT="N/A", DATE="not-a-date" | ❌ **REJECT → /quarantine/** | Check 6: Data Types |
| `file_07_fk_violation.csv` | 50 | 10 | CUSTOMER_ID = CUST-9001..9050 (not in DIM) | ❌ **REJECT → /quarantine/** | Check 8: FK Constraint |

> The requirement is 3 PASS files and 4 FAIL files, so both are generated as clean data files.

> The original file_07 was a 229-byte tiny file targeting the file size gate. With `min_file_size_bytes=100` (dev mode), 229 bytes passed the check. Redesigned as an FK violation using customer IDs `CUST-9001` to `CUST-9050` which do not exist in `DIM.CUSTOMERS`.

---

### 4.2 Injected DQ Issues Detail

#### File 04 — High Null Percentages
| Column | Null % | Threshold | Check Result |
|---|---|---|---|
| AMOUNT | 60% | 30% | **FAIL** — exceeds by 30% |
| CUSTOMER_ID | 40% | 30% | **FAIL** — exceeds by 10% |
| REGION | 30% | 30% | **WARN** — exactly at boundary |

#### File 05 — Duplicate Primary Keys
| Metric | Value |
|---|---|
| Total rows | 100 |
| Unique TRANSACTION_IDs | 85 |
| Duplicate IDs | 15 (same ID appears twice) |
| Check triggered | PK Uniqueness (Check 7) |

#### File 06 — Bad Data Types
| Column | Bad Values | Frequency | Check Triggered |
|---|---|---|---|
| AMOUNT | `N/A`, `unknown`, `#REF!`, `null`, `---`, `TBD` | Every 4th row | Check 6 |
| TRANSACTION_DATE | `not-a-date`, `32-13-2023`, `dd/mm/yyyy` | Every 5th row | Check 6 |
| QUANTITY | `many` (string) | Every 6th row | Check 6 |

#### File 07 — Foreign Key Violations
| Column | Bad Values | Count | Check Triggered |
|---|---|---|---|
| CUSTOMER_ID | `CUST-9001` to `CUST-9050` | All 50 rows | Check 8 — FK Constraint |

---

## 5. Data Quality Checks — Full Reference

### 5.1 Check Matrix

| # | Check Name | Category | Action | Config Param | Severity |
|---|---|---|---|---|---|
| 1 | File Size Gate | GATE | REJECT | `min_file_size_bytes` | CRITICAL |
| 2 | Column Count Gate | GATE | REJECT | `min_column_count` | CRITICAL |
| 3 | Required Columns Gate | GATE | REJECT | `required_columns` | CRITICAL |
| 4 | Row Count Threshold | THRESHOLD | REJECT | `min_row_count` | HIGH |
| 5 | Null % per Column | THRESHOLD | REJECT | `max_null_pct` | HIGH |
| 6 | Data Type Validation | THRESHOLD | REJECT | `column_dtype_map` | HIGH |
| 7 | Primary Key Uniqueness | THRESHOLD | REJECT | `pk_columns` | CRITICAL |
| 8 | Foreign Key Constraint | THRESHOLD | REJECT | `fk_checks` | HIGH |
| 9 | Duplicate Row Check | ADVISORY | WARN | `max_duplicate_row_pct` | MEDIUM |
| 10 | Date Range Sanity | ADVISORY | WARN | `date_range_checks` | LOW |
| 11 | Numeric Range Check | ADVISORY | WARN | `numeric_range_checks` | MEDIUM |
| 12 | Allowed Values Check | ADVISORY | WARN | `allowed_values` | LOW |

---

### 5.2 Check Details

#### Check 1 — File Size Gate [GATE | CRITICAL]
| Attribute | Detail |
|---|---|
| Purpose | Prevent ingestion of empty, corrupt, or incomplete files |
| Dev threshold | 100 bytes (`min_file_size_bytes = 100`) |
| Prod threshold | 1,048,576 bytes (1 MB) |
| Method | Read `size` column from `LIST @stage` output — no data read needed |
| Action on fail | IMMEDIATE REJECT — no further checks run |

#### Check 2 — Column Count Gate [GATE | CRITICAL]
| Attribute | Detail |
|---|---|
| Purpose | Reject structurally incomplete files before any data is processed |
| Threshold | `min_column_count = 7` |
| Method | Read header row using `CSV_FORMAT_NO_SKIP`, count non-null positional columns `$1`–`$12` |
| Action on fail | IMMEDIATE REJECT |
| Bug fix | `CSV_FORMAT_NO_SKIP` now has `RECORD_DELIMITER = '\n'` to prevent `\r` on last column |

#### Check 3 — Required Column Names [GATE | CRITICAL]
| Attribute | Detail |
|---|---|
| Purpose | Ensure all mandatory business columns are present by name |
| Method | Compare header names to `required_columns` list (case-insensitive) |
| Action on fail | REJECT — logs which specific columns are missing |

#### Check 4 — Row Count Threshold [THRESHOLD | HIGH]
| Attribute | Detail |
|---|---|
| Purpose | Reject truncated or near-empty file deliveries |
| Threshold | `min_row_count = 10` |
| Method | `COUNT(*)` on temp table |

#### Check 5 — Null % per Column [THRESHOLD | HIGH]
| Attribute | Detail |
|---|---|
| Purpose | Prevent columns with excessive missing data entering RAW layer |
| Threshold | `max_null_pct = 30.0` (% per column) |
| Method | `COUNT(*) - COUNT(col)` / `COUNT(*)` × 100 — **alias fixed to `NULL_CNT`** |
| Bug fix | v1.0 used `AS NULLS` which is a Snowflake reserved keyword causing SQL error on every file |
| Logging | One `DQ_METRICS_LOG` row per column checked |

#### Check 6 — Data Type Validation [THRESHOLD | HIGH]
| Attribute | Detail |
|---|---|
| Purpose | Ensure all values are castable to their expected types |
| Method | `TRY_TO_DATE()`, `TRY_TO_DOUBLE()`, `TRY_TO_NUMBER()` — count cast failures |
| Action on fail | REJECT if any column has > 0 non-castable rows |

#### Check 7 — Primary Key Uniqueness [THRESHOLD | CRITICAL]
| Attribute | Detail |
|---|---|
| Purpose | Prevent duplicate records on PK columns |
| Method | `COUNT(*) - COUNT(DISTINCT pk_col)` |
| Action on fail | REJECT if duplicate count > 0 |

#### Check 8 — Foreign Key Constraint [THRESHOLD | HIGH]
| Attribute | Detail |
|---|---|
| Purpose | Ensure FK values reference existing dimension records |
| Method | `LEFT JOIN` to dimension table — count rows where dimension key `IS NULL` |
| Action on fail | REJECT if orphan count > 0 |
| Bug fix | Dimension seeding fixed (`ROW_NUMBER()` instead of `SEQ4()`) — now correctly generates `CUST-0001` to `CUST-0050` matching the CSV data |

#### Checks 9–12 — Advisory Checks [ADVISORY | WARN]
All advisory checks log a `WARN` status but **do not reject the file**. The file proceeds to load.

| Check | What It Detects |
|---|---|
| 9 — Duplicate Rows | Exact duplicate rows (all columns identical) — threshold 5% |
| 10 — Date Range | Dates before 2000-01-01 or in the future |
| 11 — Numeric Range | AMOUNT < 0.01 or > 1,000,000; QUANTITY < 1 or > 10,000 |
| 12 — Allowed Values | STATUS or CURRENCY values not in allowed list |

---

## 6. Pipeline Configuration Parameters

```python
CFG = {
    'stage': {
        'stage_name':         'S3_TRANSACTION_STAGE',
        'file_format_name':   'ANALYTICS_DB.RAW.CSV_FORMAT',
        'header_format_name': 'ANALYTICS_DB.RAW.CSV_FORMAT_NO_SKIP',  # for col count check
    },
    'target': {
        'full_path': 'ANALYTICS_DB.RAW.TRANSACTION'
    },
    'monitoring': {
        'database':                 'ANALYTICS_DB',
        'schema':                   'DQ_MONITORING',
        'file_processing_table':    'FILE_PROCESSING_LOG',
        'dq_metrics_table':         'DQ_METRICS_LOG',
        'email_recipient_table':    'EMAIL_RECIPIENT_LOG',
        'notification_integration': 'EMAIL_NOTIFICATION_INTEGRATION',
    },
    'dq': {
        # Gate thresholds
        'min_file_size_bytes': 100,          # bytes — set 1048576 for production
        'min_column_count':    7,
        'required_columns': [
            'TRANSACTION_ID', 'CUSTOMER_ID', 'PRODUCT_ID',
            'TRANSACTION_DATE', 'AMOUNT', 'QUANTITY',
            'STATUS', 'REGION', 'CURRENCY',
        ],
        # Threshold checks
        'min_row_count': 10,
        'max_null_pct':  30.0,
        'column_dtype_map': {
            'TRANSACTION_ID':   'string',
            'CUSTOMER_ID':      'string',
            'PRODUCT_ID':       'string',
            'TRANSACTION_DATE': 'date',
            'AMOUNT':           'float',
            'QUANTITY':         'int',
            'STATUS':           'string',
            'REGION':           'string',
            'CURRENCY':         'string',
        },
        'pk_columns': ['TRANSACTION_ID'],
        'fk_checks': {
            'CUSTOMER_ID': 'ANALYTICS_DB.DIM.CUSTOMERS(CUSTOMER_ID)',
            'PRODUCT_ID':  'ANALYTICS_DB.DIM.PRODUCTS(PRODUCT_ID)',
        },
        # Advisory checks
        'max_duplicate_row_pct': 5.0,
        'allowed_values': {
            'STATUS':   ['COMPLETED', 'PENDING', 'CANCELLED', 'REFUNDED'],
            'CURRENCY': ['USD', 'INR', 'EUR', 'GBP', 'AED'],
        },
        'numeric_range_checks': {
            'AMOUNT':   {'min': 0.01,  'max': 1000000.0},
            'QUANTITY': {'min': 1,     'max': 10000},
        },
        'date_range_checks': {
            'TRANSACTION_DATE': {'min': '2000-01-01', 'max': 'today'},
        },
    },
    'notification': {
        'subject_prefix': '[DQ ALERT] Data Quality Failure',
        'send_on':        ['FAILURE'],
        'team_name':      'DATA_ENGINEERING',
    },
}
```

---

## 7. Snowflake DDL — Setup SQL

### Step 0 — ACCOUNTADMIN Objects

```sql
USE ROLE ACCOUNTADMIN;

-- S3 Storage Integration
CREATE STORAGE INTEGRATION IF NOT EXISTS S3_STORAGE_INTEGRATION
    TYPE                      = EXTERNAL_STAGE
    STORAGE_PROVIDER          = 'S3'
    ENABLED                   = TRUE
    STORAGE_AWS_ROLE_ARN      = 'arn:aws:iam::<your aws arn>'
    STORAGE_ALLOWED_LOCATIONS = ('s3://snowflake-dq-pipeline-bucket/transactions/');

-- Run DESC and copy output into AWS IAM Trust Policy
DESC INTEGRATION S3_STORAGE_INTEGRATION;

-- Email Notification Integration
CREATE NOTIFICATION INTEGRATION IF NOT EXISTS EMAIL_NOTIFICATION_INTEGRATION
    TYPE = EMAIL ENABLED = TRUE;

-- Role and grants
CREATE ROLE IF NOT EXISTS DATA_ENGINEER_ROLE;
GRANT ROLE DATA_ENGINEER_ROLE TO USER ANALYTICSWITHANAND;
GRANT CREATE DATABASE ON ACCOUNT TO ROLE DATA_ENGINEER_ROLE;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE DATA_ENGINEER_ROLE;
GRANT USAGE ON INTEGRATION S3_STORAGE_INTEGRATION TO ROLE DATA_ENGINEER_ROLE;
GRANT USAGE ON INTEGRATION EMAIL_NOTIFICATION_INTEGRATION TO ROLE DATA_ENGINEER_ROLE;
```

### Step 1–2 — Context + Schemas

```sql
USE ROLE DATA_ENGINEER_ROLE;
USE WAREHOUSE COMPUTE_WH;

CREATE DATABASE IF NOT EXISTS ANALYTICS_DB;
CREATE SCHEMA  IF NOT EXISTS ANALYTICS_DB.RAW;
CREATE SCHEMA  IF NOT EXISTS ANALYTICS_DB.DIM;
CREATE SCHEMA  IF NOT EXISTS ANALYTICS_DB.DQ_MONITORING;
USE SCHEMA ANALYTICS_DB.RAW;
```

### Step 3 — File Formats 

```sql
-- Main format — data loading (skips header)
-- Added RECORD_DELIMITER = '\n' to match Unix CSV endings
CREATE OR REPLACE FILE FORMAT CSV_FORMAT
    TYPE                         = 'CSV'
    FIELD_DELIMITER              = ','
    RECORD_DELIMITER             = '\n'  
    SKIP_HEADER                  = 1
    NULL_IF                      = ('', 'NULL', 'null', 'N/A', 'NA')
    EMPTY_FIELD_AS_NULL          = TRUE
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    TRIM_SPACE                   = TRUE
    DATE_FORMAT                  = 'YYYY-MM-DD'
    TIMESTAMP_FORMAT             = 'YYYY-MM-DD HH24:MI:SS';

-- Header-reading format — column count check (reads row 0)
-- Added RECORD_DELIMITER = '\n' to prevent \r on last col
CREATE OR REPLACE FILE FORMAT CSV_FORMAT_NO_SKIP
    TYPE                         = 'CSV'
    FIELD_DELIMITER              = ','
    RECORD_DELIMITER             = '\n'   
    SKIP_HEADER                  = 0
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    TRIM_SPACE                   = TRUE
    NULL_IF                      = ('NULL', 'null', '');
```

### Step 4 — Three External Stages

```sql
CREATE OR REPLACE STAGE S3_TRANSACTION_STAGE
    STORAGE_INTEGRATION = S3_STORAGE_INTEGRATION
    URL         = 's3://snowflake-dq-pipeline-bucket/transactions/incoming/'
    FILE_FORMAT = CSV_FORMAT;

CREATE OR REPLACE STAGE S3_TRANSACTION_STAGE_PROCESSED
    STORAGE_INTEGRATION = S3_STORAGE_INTEGRATION
    URL         = 's3://snowflake-dq-pipeline-bucket/transactions/processed/'
    FILE_FORMAT = CSV_FORMAT;

CREATE OR REPLACE STAGE S3_TRANSACTION_STAGE_QUARANTINE
    STORAGE_INTEGRATION = S3_STORAGE_INTEGRATION
    URL         = 's3://snowflake-dq-pipeline-bucket/transactions/quarantine/'
    FILE_FORMAT = CSV_FORMAT;

LIST @S3_TRANSACTION_STAGE;  -- verify: should list your 7 CSV files
```

### Step 5 — Target Table

```sql
CREATE TABLE IF NOT EXISTS ANALYTICS_DB.RAW.TRANSACTION (
    TRANSACTION_ID        VARCHAR(36)    NOT NULL,
    CUSTOMER_ID           VARCHAR(36)    NOT NULL,
    PRODUCT_ID            VARCHAR(36)    NOT NULL,
    TRANSACTION_DATE      DATE           NOT NULL,
    AMOUNT                FLOAT          NOT NULL,
    QUANTITY              INT            NOT NULL,
    STATUS                VARCHAR(20)    NOT NULL,
    REGION                VARCHAR(50)    NOT NULL,
    CURRENCY              VARCHAR(3)     NOT NULL,
    CREATED_AT            TIMESTAMP_NTZ  DEFAULT CURRENT_TIMESTAMP(),
    _DQ_PIPELINE_RUN_ID   VARCHAR(36),
    _SOURCE_FILE_NAME     VARCHAR(500),
    _LOADED_AT            TIMESTAMP_NTZ  DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_TRANSACTION PRIMARY KEY (TRANSACTION_ID)
);
```

### Step 6 — Dimension Tables (Bug Fixed Seeding)

```sql
CREATE TABLE IF NOT EXISTS ANALYTICS_DB.DIM.CUSTOMERS (
    CUSTOMER_ID   VARCHAR(36) NOT NULL PRIMARY KEY,
    CUSTOMER_NAME VARCHAR(200)
);
CREATE TABLE IF NOT EXISTS ANALYTICS_DB.DIM.PRODUCTS (
    PRODUCT_ID   VARCHAR(36) NOT NULL PRIMARY KEY,
    PRODUCT_NAME VARCHAR(200)
);

DELETE FROM ANALYTICS_DB.DIM.CUSTOMERS;
DELETE FROM ANALYTICS_DB.DIM.PRODUCTS;

-- BUG FIX v1.1: SEQ4() starts at 0 → generated CUST-0000..0049
-- ROW_NUMBER() generates 1,2,3... → CUST-0001..0050 (matches CSV files)
INSERT INTO ANALYTICS_DB.DIM.CUSTOMERS (CUSTOMER_ID, CUSTOMER_NAME)
SELECT 'CUST-' || LPAD(RN::STRING, 4, '0'), 'Customer ' || RN
FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS RN
      FROM TABLE(GENERATOR(ROWCOUNT => 50)));

INSERT INTO ANALYTICS_DB.DIM.PRODUCTS (PRODUCT_ID, PRODUCT_NAME)
SELECT 'PROD-' || LPAD(RN::STRING, 4, '0'), 'Product ' || RN
FROM (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS RN
      FROM TABLE(GENERATOR(ROWCOUNT => 30)));

-- Verify: MIN should be 0001, MAX should be 0050 / 0030
SELECT MIN(CUSTOMER_ID), MAX(CUSTOMER_ID) FROM ANALYTICS_DB.DIM.CUSTOMERS;
SELECT MIN(PRODUCT_ID),  MAX(PRODUCT_ID)  FROM ANALYTICS_DB.DIM.PRODUCTS;
```

### Step 7 — Monitoring Tables

```sql
USE SCHEMA ANALYTICS_DB.DQ_MONITORING;

CREATE TABLE IF NOT EXISTS FILE_PROCESSING_LOG (
    LOG_ID             INT AUTOINCREMENT PRIMARY KEY,
    PIPELINE_RUN_ID    VARCHAR(36), FILE_NAME    VARCHAR(500),
    FILE_SIZE_BYTES    BIGINT,      ROW_COUNT    INT,
    COLUMN_COUNT       INT,         PROCESSING_STATUS VARCHAR(20),
    REJECTION_REASONS  VARCHAR(4000), ROWS_LOADED INT,
    PROCESSED_AT       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    TEAM_NAME          VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS DQ_METRICS_LOG (
    METRIC_ID       INT AUTOINCREMENT PRIMARY KEY,
    LOG_ID          INT,            PIPELINE_RUN_ID VARCHAR(36),
    FILE_NAME       VARCHAR(500),   CHECK_NUMBER    INT,
    CHECK_NAME      VARCHAR(100),   CHECK_CATEGORY  VARCHAR(20),
    CHECK_STATUS    VARCHAR(10),    COLUMN_NAME     VARCHAR(100),
    THRESHOLD_VALUE VARCHAR(200),   ACTUAL_VALUE    VARCHAR(200),
    SEVERITY        VARCHAR(10),    NOTES           VARCHAR(2000),
    CHECKED_AT      TIMESTAMP_NTZ  DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS EMAIL_RECIPIENT_LOG (
    RECIPIENT_ID      INT AUTOINCREMENT PRIMARY KEY,
    EMAIL_ADDRESS     VARCHAR(200) NOT NULL,
    TEAM_NAME         VARCHAR(100), NOTIFICATION_TYPE VARCHAR(20),
    IS_ACTIVE         BOOLEAN DEFAULT TRUE,
    ADDED_BY          VARCHAR(100),
    ADDED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

DELETE FROM ANALYTICS_DB.DQ_MONITORING.EMAIL_RECIPIENT_LOG;
INSERT INTO ANALYTICS_DB.DQ_MONITORING.EMAIL_RECIPIENT_LOG
    (EMAIL_ADDRESS, TEAM_NAME, NOTIFICATION_TYPE, ADDED_BY) VALUES
    ('analyticswithanand@gmail.com', 'DATA_ENGINEERING', 'FAILURE', 'SYSTEM'),
    ('analyticswithanand@gmail.com', 'DATA_ENGINEERING', 'ALL',     'SYSTEM'),
    ('analyticswithanand@gmail.com', 'DATA_ENGINEERING', 'SUMMARY', 'SYSTEM');
```

---

## 8. Snowpark Python Script — Full Code Reference

### 8.1 Bug Fix — `check_null_pct()` Reserved Keyword

The single most critical bug. The column alias `NULLS` is reserved in Snowflake SQL (used in `ORDER BY col NULLS FIRST/LAST`). When Snowflake encountered `AS NULLS` in a `SELECT`, it threw a SQL parse error. Because the error was caught by the generic `except Exception` block in `main()`, all files were silently marked `REJECTED` with the error buried in the output.

```python
# v1.0 — BROKEN — NULLS is a Snowflake reserved keyword
row = session.sql(f"""
    SELECT
        COUNT(*) AS TOTAL,
        SUM(CASE WHEN ... END) AS NULLS      ← PARSE ERROR
    FROM {tmp_table}
""").collect()[0]
nulls = row['NULLS']                          ← KeyError even if SQL worked

# v1.1 — FIXED — renamed alias to NULL_CNT
row = session.sql(f"""
    SELECT
        COUNT(*) AS TOTAL,
        SUM(CASE WHEN ... END) AS NULL_CNT   ← valid alias
    FROM {tmp_table}
""").collect()[0]
nulls = int(row['NULL_CNT'])                  ← works correctly
```

### 8.2 Session Context Set at Startup

```python
def main(session):
    # Explicitly set DB and schema — prevents unresolved object name errors
    # if the Snowflake Python Worksheet session context differs
    session.sql('USE DATABASE ANALYTICS_DB').collect()
    session.sql('USE SCHEMA ANALYTICS_DB.RAW').collect()
```

### 8.3 Full Traceback on Unexpected Errors

```python
except Exception as unexpected:
    print(f'    [UNEXPECTED ERROR] {file_name}')
    print(f'    {type(unexpected).__name__}: {unexpected}')
    print('    Full traceback:')
    for line in traceback.format_exc().splitlines():
        print(f'    {line}')
```
Any future SQL errors are immediately visible in the Python Worksheet output panel.

### 8.4 DQResult Dataclass

```python
@dataclass
class DQResult:
    check_number:    int
    check_name:      str
    check_category:  str           # GATE | THRESHOLD | ADVISORY
    check_status:    str           # PASS | FAIL | WARN | SKIP
    column_name:     Optional[str] = None
    threshold_value: Optional[str] = None
    actual_value:    Optional[str] = None
    severity:        str           = 'HIGH'
    notes:           str           = ''
```

All 12 check functions return `List[DQResult]`. The orchestrator aggregates results and routes to PASS or FAIL path.

---

## 9. S3 File Move — How It Works

This is a critical section unique to the Snowflake-native implementation. **No boto3, no AWS SDK, no external libraries are needed.** Everything runs inside Snowflake using two built-in SQL commands.

### 9.1 The `move_file()` Function

```python
def move_file(session, stage_name: str, file_name: str, dest_folder: str):
    src  = f'ANALYTICS_DB.RAW.{stage_name}'
    dest = f'ANALYTICS_DB.RAW.{stage_name}_{dest_folder.upper()}'

    # Step 1: Copy the file to the destination stage (S3 folder)
    session.sql(f"""
        COPY FILES
        INTO @{dest}
        FROM @{src}
        FILES = ('{file_name}')
    """).collect()

    # Step 2: Delete the file from the source stage (S3 folder)
    session.sql(f"REMOVE @{src}/{file_name}").collect()
```

### 9.2 Stage Name Resolution

| `dest_folder` | `dest` variable | Points to S3 path |
|---|---|---|
| `'processed'` | `ANALYTICS_DB.RAW.S3_TRANSACTION_STAGE_PROCESSED` | `/transactions/processed/` |
| `'quarantine'` | `ANALYTICS_DB.RAW.S3_TRANSACTION_STAGE_QUARANTINE` | `/transactions/quarantine/` |

### 9.3 What Happens in S3

```
BEFORE pipeline run:
  /incoming/   file_01_happy_path.csv
               file_02_clean_regional.csv
               file_03_clean_currency.csv
               file_04_high_nulls.csv
               file_05_duplicate_pk.csv
               file_06_bad_datatypes.csv
               file_07_fk_violation.csv
  /processed/  (empty)
  /quarantine/ (empty)

AFTER pipeline run:
  /incoming/   (empty — all files moved)
  /processed/  file_01_happy_path.csv
               file_02_clean_regional.csv
               file_03_clean_currency.csv
  /quarantine/ file_04_high_nulls.csv
               file_05_duplicate_pk.csv
               file_06_bad_datatypes.csv
               file_07_fk_violation.csv
```

### 9.4 `COPY FILES` vs boto3

| Approach | Requires | Works in Snowflake Python Worksheet? |
|---|---|---|
| `COPY FILES` + `REMOVE` | Nothing — built into Snowflake | ✅ Yes |
| `boto3` | AWS credentials, pip install, network access | ❌ No |
| AWS Lambda | Separate AWS service | ❌ Not inside Snowflake |
| AWS CLI | Terminal access | ❌ Not inside Snowflake |

### 9.5 IAM Permissions Required

Your IAM role (`dq-pipeline-role`) must include both `s3:PutObject` (for `COPY FILES`) and `s3:DeleteObject` (for `REMOVE`):

```json
"Action": [
    "s3:GetObject",
    "s3:GetObjectVersion",
    "s3:ListBucket",
    "s3:PutObject",       ← required by COPY FILES INTO
    "s3:DeleteObject"     ← required by REMOVE
],
"Resource": [
    "arn:aws:s3:::snowflake-dq-pipeline-bucket",
    "arn:aws:s3:::snowflake-dq-pipeline-bucket/*"
]
```

If either permission is missing, `move_file()` prints `[MOVE WARN]` and continues — the file processing result is still logged correctly, the file just stays in `/incoming/`.

---

## 10. Email Notification Design

### 10.1 How It Triggers

```python
# Only sends when FAILURE is in send_on config
if 'FAILURE' not in cfg['notification']['send_on']:
    return

# Queries EMAIL_RECIPIENT_LOG for active recipients
recipients = session.sql("""
    SELECT EMAIL_ADDRESS
    FROM ANALYTICS_DB.DQ_MONITORING.EMAIL_RECIPIENT_LOG
    WHERE IS_ACTIVE = TRUE
      AND TEAM_NAME = 'DATA_ENGINEERING'
      AND NOTIFICATION_TYPE IN ('FAILURE', 'ALL')
""").collect()
```

### 10.2 Snowflake Native Email Call

```sql
CALL SYSTEM$SEND_EMAIL(
    'EMAIL_NOTIFICATION_INTEGRATION',    -- integration name
    'analyticswithanand@gmail.com',      -- recipient(s) comma-separated
    '[DQ ALERT] Data Quality Failure — file_04_high_nulls.csv — 2026-05-28',
    'Pipeline Run ID : abc-123...\nFile : file_04...\nStatus : REJECTED\n...'
);
```

> **Requirement:** Snowflake Enterprise or Business Critical edition.

### 10.3 Sample Email Body
```
Pipeline Run ID : a3f81c2e-7b9d-4c3e-91f2-...
Team            : DATA_ENGINEERING
File            : file_04_high_nulls.csv
File Size       : 22,447 bytes
Row Count       : 200
Status          : REJECTED

FAILED CHECKS
============================================================
Check #5 — NULL_COUNT_CHECK  [CRITICAL]
  Column    : AMOUNT
  Threshold : max 30.0% null
  Actual    : 60.0% null (120/200)
  Notes     : 120 of 200 rows have null/empty AMOUNT

Check #5 — NULL_COUNT_CHECK  [HIGH]
  Column    : CUSTOMER_ID
  Threshold : max 30.0% null
  Actual    : 40.0% null (80/200)

ACTION: File quarantined in S3. Fix data and re-upload.
Audit query:
  SELECT * FROM ANALYTICS_DB.DQ_MONITORING.DQ_METRICS_LOG
  WHERE FILE_NAME = 'file_04_high_nulls.csv' ORDER BY CHECK_NUMBER;
```

---

## 11. Execution Walkthrough

### 11.1 Execution Order

| Step | Where | What |
|---|---|---|
| 1 | SQL Worksheet | Run `01_ddl_setup.sql` — ACCOUNTADMIN section first, then DATA_ENGINEER_ROLE sections |
| 2 | S3 Console | Upload all 7 CSV files to `.../transactions/incoming/` |
| 3 | Snowflake | `LIST @S3_TRANSACTION_STAGE` — verify 7 files visible |
| 4 | Python Worksheet | Paste entire `main.py` → click Run |
| 5 | Python output | Copy the `Pipeline Run ID` printed at the top |
| 6 | SQL Worksheet | `SET RUN_ID = '<paste here>'` then run audit queries |

### 11.2 Expected Console Output

```
=================================================================
  DQ PIPELINE STARTED
  Pipeline Run ID : a3f81c2e-7b9d-4c3e-91f2-883d46a00c1f
  Timestamp       : 2026-05-28 09:00:00 UTC
=================================================================
  Files found in stage: 7
    file_01_happy_path.csv       61,012 bytes
    file_02_clean_regional.csv   36,027 bytes
    file_03_clean_currency.csv   24,361 bytes
    file_04_high_nulls.csv       22,447 bytes
    file_05_duplicate_pk.csv     12,254 bytes
    file_06_bad_datatypes.csv     9,824 bytes
    file_07_fk_violation.csv      6,206 bytes

  ────────────────────────────────────────────────────────────
  Processing: file_01_happy_path.csv  (61,012 bytes)
    [MOVE] file_01_happy_path.csv  →  /processed/
    STATUS: ✅ PASSED  |  500 rows loaded into RAW.TRANSACTION

  Processing: file_02_clean_regional.csv  (36,027 bytes)
    [MOVE] file_02_clean_regional.csv  →  /processed/
    STATUS: ✅ PASSED  |  300 rows loaded into RAW.TRANSACTION

  Processing: file_03_clean_currency.csv  (24,361 bytes)
    [MOVE] file_03_clean_currency.csv  →  /processed/
    STATUS: ✅ PASSED  |  200 rows loaded into RAW.TRANSACTION

  Processing: file_04_high_nulls.csv  (22,447 bytes)
    [MOVE] file_04_high_nulls.csv  →  /quarantine/
    [NOTIFY] Email sent to: analyticswithanand@gmail.com
    STATUS: ❌ REJECTED  |  Check 5 FAILED: null % exceeds threshold

  Processing: file_05_duplicate_pk.csv  (12,254 bytes)
    [MOVE] file_05_duplicate_pk.csv  →  /quarantine/
    [NOTIFY] Email sent to: analyticswithanand@gmail.com
    STATUS: ❌ REJECTED  |  Check 7 FAILED: primary key duplicates found

  Processing: file_06_bad_datatypes.csv  (9,824 bytes)
    [MOVE] file_06_bad_datatypes.csv  →  /quarantine/
    [NOTIFY] Email sent to: analyticswithanand@gmail.com
    STATUS: ❌ REJECTED  |  Check 6 FAILED: data type cast failures

  Processing: file_07_fk_violation.csv  (6,206 bytes)
    [MOVE] file_07_fk_violation.csv  →  /quarantine/
    [NOTIFY] Email sent to: analyticswithanand@gmail.com
    STATUS: ❌ REJECTED  |  Check 8 FAILED: foreign key violations found

=================================================================
  PIPELINE RUN COMPLETE
  Run ID      : a3f81c2e-7b9d-4c3e-91f2-883d46a00c1f
  Total Files : 7
  ✅ Passed   : 3
  ❌ Rejected : 4
  Rows Loaded : 1,000
=================================================================
```

---

## 12. Expected Results Per File

| File | Rows | Failure Mode | S3 Destination | Rows in RAW |
|---|---|---|---|---|
| file_01_happy_path.csv | 500 | None | ✅ `/processed/` | 500 |
| file_02_clean_regional.csv | 300 | None | ✅ `/processed/` | 300 |
| file_03_clean_currency.csv | 200 | None | ✅ `/processed/` | 200 |
| file_04_high_nulls.csv | 200 | AMOUNT 60% null | ❌ `/quarantine/` | 0 |
| file_05_duplicate_pk.csv | 100 | 15 duplicate PKs | ❌ `/quarantine/` | 0 |
| file_06_bad_datatypes.csv | 80 | AMOUNT="N/A", DATE invalid | ❌ `/quarantine/` | 0 |
| file_07_fk_violation.csv | 50 | CUST-9001..9050 not in DIM | ❌ `/quarantine/` | 0 |
| **TOTAL** | **1,430** | | | **1,000 loaded** |

---

## 13. Audit Queries

```sql
-- Set run ID once — used in all queries below
SET RUN_ID = 'PASTE-YOUR-RUN-ID-HERE';

-- Q1: Summary of all files
SELECT FILE_NAME, FILE_SIZE_BYTES, ROW_COUNT, PROCESSING_STATUS,
       REJECTION_REASONS, ROWS_LOADED, PROCESSED_AT
FROM ANALYTICS_DB.DQ_MONITORING.FILE_PROCESSING_LOG
WHERE PIPELINE_RUN_ID = $RUN_ID ORDER BY PROCESSED_AT;

-- Q2: Every check result for every file
SELECT FILE_NAME, CHECK_NUMBER, CHECK_NAME, CHECK_CATEGORY,
       CHECK_STATUS, COLUMN_NAME, THRESHOLD_VALUE, ACTUAL_VALUE,
       SEVERITY, NOTES
FROM ANALYTICS_DB.DQ_MONITORING.DQ_METRICS_LOG
WHERE PIPELINE_RUN_ID = $RUN_ID ORDER BY FILE_NAME, CHECK_NUMBER;

-- Q3: Only failed/warn checks
SELECT FILE_NAME, CHECK_NUMBER, CHECK_NAME, COLUMN_NAME,
       THRESHOLD_VALUE, ACTUAL_VALUE, SEVERITY, NOTES
FROM ANALYTICS_DB.DQ_MONITORING.DQ_METRICS_LOG
WHERE PIPELINE_RUN_ID = $RUN_ID AND CHECK_STATUS IN ('FAIL','WARN')
ORDER BY FILE_NAME, CHECK_NUMBER;

-- Q4: Confirm rows loaded by file
SELECT _SOURCE_FILE_NAME, COUNT(*) AS ROWS_LOADED
FROM ANALYTICS_DB.RAW.TRANSACTION GROUP BY 1 ORDER BY 1;

-- Q5: Preview loaded data
SELECT * FROM ANALYTICS_DB.RAW.TRANSACTION
WHERE _DQ_PIPELINE_RUN_ID = $RUN_ID LIMIT 20;

-- Q6: Check failure rate per check (useful for threshold tuning)
SELECT CHECK_NUMBER, CHECK_NAME, CHECK_CATEGORY,
       COUNT(*) AS TOTAL_RUNS,
       SUM(CASE WHEN CHECK_STATUS IN ('FAIL','WARN') THEN 1 ELSE 0 END) AS FAILURES,
       ROUND(FAILURES / NULLIF(TOTAL_RUNS,0) * 100, 1) AS FAILURE_RATE_PCT
FROM ANALYTICS_DB.DQ_MONITORING.DQ_METRICS_LOG
GROUP BY 1,2,3 ORDER BY FAILURE_RATE_PCT DESC;

-- Q7: Find latest run ID (if you forgot to copy it)
SELECT DISTINCT PIPELINE_RUN_ID, MAX(PROCESSED_AT) AS RUN_TIME
FROM ANALYTICS_DB.DQ_MONITORING.FILE_PROCESSING_LOG
GROUP BY 1 ORDER BY RUN_TIME DESC LIMIT 5;
```

---

## 14. Deployment Guide

### Prerequisites
```bash
# Python 3.8+ with Snowpark (only needed if running outside Snowflake UI)
pip install snowflake-snowpark-python

# When running inside Snowflake Python Worksheet:
# No pip installs needed — session is auto-injected
```

### IAM Role Policy (AWS)
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:GetObject", "s3:GetObjectVersion",
      "s3:ListBucket",
      "s3:PutObject",    "s3:DeleteObject"
    ],
    "Resource": [
      "arn:aws:s3:::snowflake-dq-pipeline-bucket",
      "arn:aws:s3:::snowflake-dq-pipeline-bucket/*"
    ]
  }]
}
```

### Scheduling via Snowflake Task
```sql
CREATE TASK DQ_PIPELINE_DAILY
    WAREHOUSE = COMPUTE_WH
    SCHEDULE  = 'USING CRON 0 6 * * * UTC'
AS
    CALL ANALYTICS_DB.RAW.DQ_PIPELINE_PROC();

ALTER TASK DQ_PIPELINE_DAILY RESUME;
```

---

## 15. Troubleshooting & FAQ

| Issue | Root Cause | Fix |
|---|---|---|
| All files rejected silently | `AS NULLS` reserved keyword bug (v1.0) | Upgrade to `main.py` v1.1 |
| FK check fails for clean files | Dimension seeding off-by-one (`SEQ4()` starts at 0) | Re-run DDL Step 6 with `ROW_NUMBER()` fix |
| Last column has `\r` appended | Missing `RECORD_DELIMITER = '\n'` in file format | Re-create both file formats from updated DDL Step 3 |
| `[UNEXPECTED ERROR]` in output | Full traceback now printed — read the error message | Find the check number and column in the traceback |
| File moves not working | IAM role missing `s3:PutObject` or `s3:DeleteObject` | Add both permissions to your IAM policy |
| Email not sending | Snowflake edition below Enterprise, or integration disabled | Verify edition; check `SHOW INTEGRATIONS` |
| `LIST @stage` returns empty | Storage integration trust policy not configured in AWS | Re-run `DESC INTEGRATION` and update IAM trust relationship |
| COPY INTO parsing errors | File format mismatch or encoding issues | Verify `RECORD_DELIMITER = '\n'` and `SKIP_HEADER = 1` in `CSV_FORMAT` |
| New team onboarding | Need isolated config | Copy `CFG` dict, update all parameters, set unique `team_name` |

---
