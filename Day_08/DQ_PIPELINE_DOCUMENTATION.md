# End-to-End Data Quality Validation Pipeline
## Snowpark Python · AWS S3 · Snowflake · Complete Documentation

---
> **Stack:** Snowpark Python · AWS S3 · Snowflake · Storage Integration · Native Email Notification  
> **Last Updated:** 2026-05-26
---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Diagram](#2-architecture-diagram)
3. [Snowflake Object Inventory](#3-snowflake-object-inventory)
4. [CSV Test File Catalogue](#4-csv-test-file-catalogue)
5. [Data Quality Checks — Full Reference](#5-data-quality-checks--full-reference)
6. [Pipeline Configuration Parameters](#6-pipeline-configuration-parameters)
7. [Snowflake DDL — Setup SQL](#7-snowflake-ddl--setup-sql)
8. [Snowpark Python Script — Full Code](#8-snowpark-python-script--full-code)
9. [Email Notification Design](#9-email-notification-design)
10. [Execution Walkthrough](#10-execution-walkthrough)
11. [Expected Results per File](#11-expected-results-per-file)
12. [Deployment Guide](#12-deployment-guide)
13. [Troubleshooting & FAQ](#13-troubleshooting--faq)

---

## 1. Executive Summary

This pipeline is a **parameterised, team-agnostic data quality framework** built on Snowpark Python. It intercepts CSV files landing in an AWS S3 bucket, runs **12 sequential data quality gate checks**, and only loads files into Snowflake's RAW layer if every check passes. Files that fail any check are quarantined, logged, and trigger an automated email alert to configured recipients.

### Design Principles

| Principle | Implementation |
|---|---|
| **Zero-trust ingestion** | No file loads unless all gates pass |
| **Team-agnostic** | Entire behaviour driven by a single config dict |
| **Full audit trail** | Every check result written to DQ_METRICS_LOG |
| **Fail-fast** | Cheap checks (file size, column count) run first |
| **Per-file independence** | 1 file failing does not block other files |
| **Human alerting** | Snowflake native email on every rejection |

---

## 2. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           AWS S3 BUCKET                                 │
│                                                                         │
│   s3://your-bucket/transactions/incoming/   ← CSV files land here      │
│   s3://your-bucket/transactions/processed/ ← moved after PASS          │
│   s3://your-bucket/transactions/quarantine/← moved after FAIL          │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │  IAM Role Trust Policy
                               │  (Storage Integration)
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     SNOWFLAKE EXTERNAL STAGE                            │
│         S3_TRANSACTION_STAGE  →  LIST / READ files via stage            │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│              SNOWPARK PYTHON — DATA QUALITY ENGINE                      │
│                                                                         │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │                 GATE CHECKS  (Fail-Fast)                       │     │
│  │  [1] File Size Check          < 1 MB         → IMMEDIATE REJECT│     │
│  │  [2] Column Count Check       < 7 cols       → IMMEDIATE REJECT│     │
│  │  [3] Required Column Names    missing cols   → IMMEDIATE REJECT│     │
│  └──────────────────────────────┬─────────────────────────────────┘     │
│                                 │ Gates Passed                          │
│  ┌──────────────────────────────▼─────────────────────────────────┐     │
│  │                THRESHOLD CHECKS                                │     │
│  │  [4] Row Count Threshold      < 10 rows      → REJECT          │     │
│  │  [5] Null % per Column        > 30% null     → REJECT          │     │
│  │  [6] Data Type Validation     bad cast       → REJECT          │     │
│  │  [7] Primary Key Uniqueness   duplicates     → REJECT          │     │
│  │  [8] Foreign Key Constraint   orphan keys    → REJECT          │     │
│  └──────────────────────────────┬─────────────────────────────────┘     │
│                                 │ Thresholds Passed                     │
│  ┌──────────────────────────────▼─────────────────────────────────┐     │
│  │                ADVISORY CHECKS  (WARN only)                    │     │
│  │  [9]  Duplicate Rows           > 5% dupes    → WARN            │     │
│  │  [10] Date Range Sanity        future / old  → WARN            │     │
│  │  [11] Numeric Range            negative/huge → WARN            │     │
│  │  [12] Allowed Values           bad category  → WARN            │     │
│  └──────────────────────────────┬─────────────────────────────────┘     │
│                                 │                                       │
│             ┌───────────────────┴──────────────────┐                   │
│             │ PASS                                  │ FAIL              │
│             ▼                                       ▼                   │
│   ┌──────────────────┐               ┌─────────────────────────────┐   │
│   │  COPY INTO       │               │  Log to DQ_METRICS_LOG      │   │
│   │  RAW.TRANSACTION │               │  Update FILE_PROCESSING_LOG │   │
│   │  (Snowflake)     │               │  Send Email Notification    │   │
│   │                  │               │  Move file → /quarantine/   │   │
│   │  Move file →     │               └─────────────────────────────┘   │
│   │  /processed/     │                                                  │
│   └──────────────────┘                                                  │
└─────────────────────────────────────────────────────────────────────────┘
                               │
          ┌────────────────────┴───────────────────┐
          ▼                                        ▼
┌──────────────────────┐               ┌────────────────────────────┐
│  Snowflake RAW Layer │               │ DQ_MONITORING Schema        │
│  RAW.TRANSACTION     │               │  FILE_PROCESSING_LOG        │
│                      │               │  DQ_METRICS_LOG             │
│  (clean data only)   │               │  EMAIL_RECIPIENT_LOG        │
└──────────────────────┘               └────────────────────────────┘
                                                    │
                                                    ▼
                                       ┌────────────────────────────┐
                                       │  Snowflake Email            │
                                       │  Notification Integration   │
                                       │  SYSTEM$SEND_EMAIL          │
                                       └────────────────────────────┘
```

---

## 3. Snowflake Object Inventory

### 3.1 Databases and Schemas

| Database | Schema | Purpose |
|---|---|---|
| `ANALYTICS_DB` | `RAW` | Target schema for clean ingested data |
| `ANALYTICS_DB` | `DIM` | Dimension tables (CUSTOMERS, PRODUCTS) for FK checks |
| `ANALYTICS_DB` | `DQ_MONITORING` | All audit and monitoring tables |

---

### 3.2 Tables

#### `RAW.TRANSACTION` — Main Target Table

| Column | Type | Constraint | Description |
|---|---|---|---|
| TRANSACTION_ID | VARCHAR(36) | PRIMARY KEY | UUID format transaction identifier |
| CUSTOMER_ID | VARCHAR(36) | FK → DIM.CUSTOMERS | Customer who made the transaction |
| PRODUCT_ID | VARCHAR(36) | FK → DIM.PRODUCTS | Product purchased |
| TRANSACTION_DATE | DATE | NOT NULL | Date of transaction |
| AMOUNT | FLOAT | CHECK > 0 | Transaction value |
| QUANTITY | INT | CHECK > 0 | Units purchased |
| STATUS | VARCHAR(20) | IN allowed list | COMPLETED / PENDING / CANCELLED / REFUNDED |
| REGION | VARCHAR(50) | NOT NULL | Geographic region |
| CURRENCY | VARCHAR(3) | IN allowed list | USD / INR / EUR / GBP / AED |
| CREATED_AT | TIMESTAMP_NTZ | DEFAULT NOW() | Pipeline insertion timestamp |

---

#### `DQ_MONITORING.FILE_PROCESSING_LOG` — One Row per File Run

| Column | Type | Description |
|---|---|---|
| LOG_ID | INT AUTOINCREMENT | Surrogate key |
| PIPELINE_RUN_ID | VARCHAR(36) | UUID grouping all files in one run |
| FILE_NAME | VARCHAR(500) | S3 file name |
| FILE_SIZE_BYTES | BIGINT | File size at processing time |
| ROW_COUNT | INT | Number of data rows detected |
| COLUMN_COUNT | INT | Number of columns detected |
| PROCESSING_STATUS | VARCHAR(20) | PASSED / REJECTED / SKIPPED |
| REJECTION_REASONS | VARCHAR(2000) | Pipe-separated list of failed checks |
| ROWS_LOADED | INT | Actual rows inserted into RAW table |
| PROCESSED_AT | TIMESTAMP_NTZ | Timestamp of processing |
| TEAM_NAME | VARCHAR(100) | Team that ran the pipeline |

---

#### `DQ_MONITORING.DQ_METRICS_LOG` — One Row per Check per File

| Column | Type | Description |
|---|---|---|
| METRIC_ID | INT AUTOINCREMENT | Surrogate key |
| LOG_ID | INT | FK to FILE_PROCESSING_LOG |
| PIPELINE_RUN_ID | VARCHAR(36) | Run grouping key |
| FILE_NAME | VARCHAR(500) | File name |
| CHECK_NUMBER | INT | Check sequence number (1–12) |
| CHECK_NAME | VARCHAR(100) | e.g. NULL_COUNT_CHECK |
| CHECK_CATEGORY | VARCHAR(20) | GATE / THRESHOLD / ADVISORY |
| CHECK_STATUS | VARCHAR(10) | PASS / FAIL / WARN / SKIP |
| COLUMN_NAME | VARCHAR(100) | Relevant column (NULL if file-level check) |
| THRESHOLD_VALUE | VARCHAR(100) | Configured threshold |
| ACTUAL_VALUE | VARCHAR(100) | Observed value |
| SEVERITY | VARCHAR(10) | CRITICAL / HIGH / MEDIUM / LOW |
| NOTES | VARCHAR(1000) | Human-readable explanation |
| CHECKED_AT | TIMESTAMP_NTZ | Timestamp |

---

#### `DQ_MONITORING.EMAIL_RECIPIENT_LOG` — Notification Recipients

| Column | Type | Description |
|---|---|---|
| RECIPIENT_ID | INT AUTOINCREMENT | Surrogate key |
| EMAIL_ADDRESS | VARCHAR(200) | Recipient email |
| TEAM_NAME | VARCHAR(100) | Team filter |
| NOTIFICATION_TYPE | VARCHAR(20) | FAILURE / ALL / SUMMARY |
| IS_ACTIVE | BOOLEAN | Toggle without deleting |
| ADDED_BY | VARCHAR(100) | Who registered this recipient |
| ADDED_AT | TIMESTAMP_NTZ | Registration timestamp |

---

### 3.3 Storage & Integration Objects

| Object | Type | Purpose |
|---|---|---|
| `S3_STORAGE_INTEGRATION` | Storage Integration | Snowflake ↔ S3 IAM trust |
| `S3_TRANSACTION_STAGE` | External Stage | Points to S3 prefix |
| `CSV_FORMAT` | File Format | Comma-delimited, header=1, NULL_IF='' |
| `EMAIL_NOTIFICATION_INTEGRATION` | Notification Integration | SYSTEM$SEND_EMAIL |

---

## 4. CSV Test File Catalogue

### Overview Table

| File | Rows | Cols | Scenario | Expected Result | Check That Fails |
|---|---|---|---|---|---|
| `file_01_happy_path.csv` | 200 | 10 | All data clean and valid | ✅ **PASS → LOADED** | None |
| `file_02_low_row_count.csv` | 3 | 10 | Too few rows | ❌ **REJECT** | Check 4: Row Count |
| `file_03_missing_columns.csv` | 50 | 5 | Only 5 of 10 columns | ❌ **REJECT** | Check 2: Column Count |
| `file_04_high_nulls.csv` | 150 | 10 | AMOUNT=60% null, CUSTOMER_ID=40% null | ❌ **REJECT** | Check 5: Null % |
| `file_05_duplicate_pk.csv` | 100 | 10 | 15 duplicate TRANSACTION_IDs | ❌ **REJECT** | Check 7: PK Uniqueness |
| `file_06_bad_datatypes.csv` | 80 | 10 | AMOUNT="N/A", DATE="not-a-date" | ❌ **REJECT** | Check 6: Data Types |
| `file_07_small_file.csv` | 1 | 10 | File is 229 bytes (< 1 MB) | ❌ **REJECT** | Check 1: File Size |

---

### File 01 — Happy Path (`file_01_happy_path.csv`)

```
Rows:          200
Columns:       10 (all required columns present)
Null values:   0 across all columns
PK duplicates: 0
Data types:    All correct
File size:     ~24 KB   ← NOTE: This also fails file size check!
```

> **⚠️ Important Note on File Size:**  
> All generated test files are under 1 MB because synthetic CSV data is compact.  
> In production, set `min_file_size_bytes` to a value appropriate for your expected data volume  
> (e.g., `1024` bytes for testing, `1048576` for production). File 01 will pass all other checks  
> and represents the "happy path" logic. For demo purposes, set the size threshold to 100 bytes.

---

### File 02 — Low Row Count (`file_02_low_row_count.csv`)

```
Rows:          3   ← below threshold of 10
Columns:       10
Scenario:      Simulates a partially delivered/truncated file
Expected:      REJECT at Check 4 (Row Count Threshold)
```

**Sample rows:**
```
TRANSACTION_ID,CUSTOMER_ID,PRODUCT_ID,TRANSACTION_DATE,AMOUNT,QUANTITY,STATUS,REGION,CURRENCY,CREATED_AT
4751f698-...,CUST-0044,PROD-0020,2022-04-18,3948.24,42,CANCELLED,North America,EUR,2026-05-26
0e2e8598-...,CUST-0007,PROD-0018,2024-03-02,1427.89,47,PENDING,Europe,USD,2026-05-26
```

---

### File 03 — Missing Columns (`file_03_missing_columns.csv`)

```
Columns present: TRANSACTION_ID, CUSTOMER_ID, TRANSACTION_DATE, AMOUNT, STATUS  (5 only)
Columns missing: PRODUCT_ID, QUANTITY, REGION, CURRENCY, CREATED_AT
Rows:            50
Expected:        REJECT at Check 2 (Column Count) AND Check 3 (Required Columns)
```

---

### File 04 — High Null Percentages (`file_04_high_nulls.csv`)

```
Rows:              150
AMOUNT null:       60% of rows (threshold: 30%)
CUSTOMER_ID null:  40% of rows (threshold: 30%)
REGION null:       30% of rows (at threshold boundary)
Expected:          REJECT at Check 5 (Null % per Column) for AMOUNT and CUSTOMER_ID
```

---

### File 05 — Duplicate Primary Keys (`file_05_duplicate_pk.csv`)

```
Rows:            100 total
Unique IDs:      85
Duplicate IDs:   15 (same TRANSACTION_ID appears twice)
Duplicate rate:  15%
Expected:        REJECT at Check 7 (PK Uniqueness)
```

---

### File 06 — Bad Data Types (`file_06_bad_datatypes.csv`)

```
Rows:              80
Bad AMOUNT values: "N/A", "unknown", "#REF!", "null", "---", "TBD"  (every 4th row)
Bad DATE values:   "not-a-date", "32-13-2023", "dd/mm/yyyy"          (every 5th row)
Bad QUANTITY:      "many"                                             (every 6th row)
Bad STATUS:        "UNKNOWN_STATUS"                                   (every 8th row)
Expected:          REJECT at Check 6 (Data Type) and Check 12 (Allowed Values)
```

---

### File 07 — Tiny File (`file_07_small_file.csv`)

```
Rows:      1
File size: 229 bytes  (threshold: 1 MB = 1,048,576 bytes)
Expected:  REJECT at Check 1 (File Size) — fastest possible rejection
```

---

## 5. Data Quality Checks — Full Reference

### Check Matrix

| # | Check Name | Category | Reject or Warn | Config Parameter | Description |
|---|---|---|---|---|---|
| 1 | File Size Gate | GATE | REJECT | `min_file_size_bytes` | File must exceed minimum size |
| 2 | Column Count Gate | GATE | REJECT | `min_column_count` | File must have at least N columns |
| 3 | Required Columns Gate | GATE | REJECT | `required_columns` | All mandatory column names must exist |
| 4 | Row Count Threshold | THRESHOLD | REJECT | `min_row_count` | File must have at least N data rows |
| 5 | Null % per Column | THRESHOLD | REJECT | `max_null_pct` | Each column's null% must be below threshold |
| 6 | Data Type Validation | THRESHOLD | REJECT | `column_dtype_map` | Each column must be castable to expected type |
| 7 | Primary Key Uniqueness | THRESHOLD | REJECT | `pk_columns` | PK column(s) must have zero duplicates |
| 8 | Foreign Key Constraint | THRESHOLD | REJECT | `fk_checks` | FK values must exist in dimension tables |
| 9 | Duplicate Row Check | ADVISORY | WARN | `max_duplicate_row_pct` | Exact duplicate rows flagged if above % |
| 10 | Date Range Sanity | ADVISORY | WARN | `date_range_checks` | Dates must fall within configured min/max |
| 11 | Numeric Range Check | ADVISORY | WARN | `numeric_range_checks` | Numerics must fall within configured min/max |
| 12 | Allowed Values Check | ADVISORY | WARN | `allowed_values` | Categorical columns must use allowed values |

---

### Check 1 — File Size Gate

```
Purpose:    Prevent ingestion of empty, corrupt, or incomplete files
Threshold:  min_file_size_bytes (default: 1,048,576 = 1 MB)
Method:     Query stage metadata — LIST @stage PATTERN='.*filename.*'
            Extract size from SIZE column
Action:     REJECT immediately if size < threshold
Severity:   CRITICAL
```

---

### Check 2 — Column Count Gate

```
Purpose:    Ensure file has enough columns to be structurally valid
Threshold:  min_column_count (default: 7)
Method:     Read header row, count comma-separated fields
Action:     REJECT immediately if count < threshold
Severity:   CRITICAL
Note:       Runs before loading any data — purely structural
```

---

### Check 3 — Required Column Names Gate

```
Purpose:    Ensure all mandatory columns are present by exact name
Config:     required_columns list in config dict
Method:     Compare file header names against required_columns (case-insensitive)
Action:     REJECT if any required column is missing
            Log which columns are missing in REJECTION_REASONS
Severity:   CRITICAL
```

---

### Check 4 — Row Count Threshold

```
Purpose:    Reject suspiciously small files (truncated deliveries)
Threshold:  min_row_count (default: 10)
Method:     COUNT(*) after loading to temp table or via stage query
Action:     REJECT if row count < threshold
Severity:   HIGH
```

---

### Check 5 — Null % per Column

```
Purpose:    Prevent columns with excessive missing data from reaching RAW layer
Threshold:  max_null_pct per column (default: 30%)
Method:     For each column: (COUNT(*) - COUNT(col)) / COUNT(*) * 100
Action:     REJECT if ANY column exceeds threshold
            Log per-column null% in DQ_METRICS_LOG
Severity:   HIGH
Note:       Each column gets its own DQ_METRICS_LOG row
```

---

### Check 6 — Data Type Validation

```
Purpose:    Ensure values in each column are castable to expected type
Config:     column_dtype_map (string/int/float/date/timestamp)
Method:     TRY_CAST() each column → count failures
            For dates: TRY_TO_DATE()
            For floats: TRY_TO_DOUBLE()
            For ints: TRY_TO_NUMBER()
Action:     REJECT if any column has > 0 cast failures (configurable %)
Severity:   HIGH
```

---

### Check 7 — Primary Key Uniqueness

```
Purpose:    Ensure no duplicate records on PK columns
Config:     pk_columns list (can be composite)
Method:     COUNT(*) vs COUNT(DISTINCT pk_col)
            Or GROUP BY pk_col HAVING COUNT(*) > 1
Action:     REJECT if duplicate count > 0
            Log number of duplicate PK values
Severity:   CRITICAL
```

---

### Check 8 — Foreign Key Constraint

```
Purpose:    Ensure FK values reference existing dimension records
Config:     fk_checks dict: {col: "DB.SCHEMA.TABLE(COL)"}
Method:     LEFT JOIN file data to dimension table
            Count rows where dimension key IS NULL
Action:     REJECT if orphan FK count > configured threshold (default: 0)
Severity:   HIGH
Note:       Runs as Snowflake SQL via Snowpark
```

---

### Check 9 — Duplicate Row Check (Advisory)

```
Purpose:    Detect exact duplicate records (all columns identical)
Threshold:  max_duplicate_row_pct (default: 5%)
Method:     SELECT *, COUNT(*) GROUP BY all cols HAVING COUNT(*) > 1
Action:     WARN only (file still loads) — logged in DQ_METRICS_LOG
Severity:   MEDIUM
```

---

### Check 10 — Date Range Sanity (Advisory)

```
Purpose:    Flag dates that are implausibly old or in the future
Config:     date_range_checks: {col: {min: date, max: "today"}}
Method:     COUNT rows where date < min OR date > CURRENT_DATE()
Action:     WARN only — logged with count of out-of-range rows
Severity:   LOW
```

---

### Check 11 — Numeric Range Check (Advisory)

```
Purpose:    Flag values outside expected business ranges
Config:     numeric_range_checks: {col: {min: N, max: M}}
Method:     COUNT rows where val < min OR val > max
Action:     WARN only — logged with count and sample values
Severity:   MEDIUM
```

---

### Check 12 — Allowed Values Check (Advisory)

```
Purpose:    Flag records using unexpected categorical values
Config:     allowed_values: {col: [list of valid values]}
Method:     COUNT rows where col NOT IN (allowed list)
Action:     WARN only — logged with count and distinct bad values found
Severity:   LOW
```

---

## 6. Pipeline Configuration Parameters

```python
PIPELINE_CONFIG = {

    # ── Snowflake Connection ──────────────────────────────────────────────
    "snowflake": {
        "account":   "YOUR_ACCOUNT.snowflakecomputing.com",
        "user":      "DQ_PIPELINE_USER",
        "password":  "YOUR_PASSWORD",       # use env var in production
        "database":  "ANALYTICS_DB",
        "schema":    "RAW",
        "warehouse": "COMPUTE_WH",
        "role":      "DATA_ENGINEER_ROLE"
    },

    # ── AWS S3 ────────────────────────────────────────────────────────────
    "s3": {
        "bucket_url":   "s3://your-bucket/transactions/incoming/",
        "aws_role_arn": "arn:aws:iam::123456789012:role/snowflake-s3-role",
        "region":       "us-east-1"
    },

    # ── Snowflake Stage ───────────────────────────────────────────────────
    "stage": {
        "storage_integration_name": "S3_STORAGE_INTEGRATION",
        "stage_name":               "S3_TRANSACTION_STAGE",
        "file_format_name":         "CSV_FORMAT"
    },

    # ── Target Table ──────────────────────────────────────────────────────
    "target": {
        "database":  "ANALYTICS_DB",
        "schema":    "RAW",
        "table":     "TRANSACTION",
        "full_path": "ANALYTICS_DB.RAW.TRANSACTION"
    },

    # ── Monitoring Tables ─────────────────────────────────────────────────
    "monitoring": {
        "database":                 "ANALYTICS_DB",
        "schema":                   "DQ_MONITORING",
        "file_processing_table":    "FILE_PROCESSING_LOG",
        "dq_metrics_table":         "DQ_METRICS_LOG",
        "email_recipient_table":    "EMAIL_RECIPIENT_LOG",
        "notification_integration": "EMAIL_NOTIFICATION_INTEGRATION"
    },

    # ── Data Quality Thresholds ───────────────────────────────────────────
    "dq": {
        # Gate checks (fail-fast)
        "min_file_size_bytes":   1048576,   # 1 MB  ← set to 100 for local testing
        "min_column_count":      7,
        "required_columns": [
            "TRANSACTION_ID", "CUSTOMER_ID", "PRODUCT_ID",
            "TRANSACTION_DATE", "AMOUNT", "QUANTITY",
            "STATUS", "REGION", "CURRENCY"
        ],

        # Threshold checks
        "min_row_count":         10,
        "max_null_pct":          30.0,      # percent — applied per column

        "column_dtype_map": {
            "TRANSACTION_ID":   "string",
            "CUSTOMER_ID":      "string",
            "PRODUCT_ID":       "string",
            "TRANSACTION_DATE": "date",
            "AMOUNT":           "float",
            "QUANTITY":         "int",
            "STATUS":           "string",
            "REGION":           "string",
            "CURRENCY":         "string"
        },

        "pk_columns": ["TRANSACTION_ID"],

        "fk_checks": {
            "CUSTOMER_ID": "ANALYTICS_DB.DIM.CUSTOMERS(CUSTOMER_ID)",
            "PRODUCT_ID":  "ANALYTICS_DB.DIM.PRODUCTS(PRODUCT_ID)"
        },

        # Advisory checks (warn only)
        "max_duplicate_row_pct": 5.0,

        "allowed_values": {
            "STATUS":   ["COMPLETED", "PENDING", "CANCELLED", "REFUNDED"],
            "CURRENCY": ["USD", "INR", "EUR", "GBP", "AED"]
        },

        "numeric_range_checks": {
            "AMOUNT":   {"min": 0.01,  "max": 1000000.0},
            "QUANTITY": {"min": 1,     "max": 10000}
        },

        "date_range_checks": {
            "TRANSACTION_DATE": {
                "min": "2000-01-01",
                "max": "today"          # evaluated at runtime
            }
        }
    },

    # ── Notification ──────────────────────────────────────────────────────
    "notification": {
        "sender_email":    "dq-pipeline@yourcompany.com",
        "subject_prefix":  "[DQ ALERT] Data Quality Failure",
        "send_on":         ["FAILURE"],     # options: FAILURE / ALL / NONE
        "team_name":       "DATA_ENGINEERING"
    }
}
```

---

## 7. Snowflake DDL — Setup SQL

```sql
-- ============================================================
-- STEP 0: Run as ACCOUNTADMIN for integration objects
-- ============================================================
USE ROLE ACCOUNTADMIN;

-- ── Storage Integration ─────────────────────────────────────
CREATE STORAGE INTEGRATION S3_STORAGE_INTEGRATION
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = 'S3'
    ENABLED = TRUE
    STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::123456789012:role/snowflake-s3-role'
    STORAGE_ALLOWED_LOCATIONS = ('s3://your-bucket/transactions/');

-- Get the values needed to configure the IAM trust policy in AWS
DESC INTEGRATION S3_STORAGE_INTEGRATION;
-- Note: STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID
-- Add these to your IAM role trust relationship in AWS console

-- ── Email Notification Integration ─────────────────────────
CREATE NOTIFICATION INTEGRATION EMAIL_NOTIFICATION_INTEGRATION
    TYPE = EMAIL
    ENABLED = TRUE;

-- Grant usage to your pipeline role
GRANT USAGE ON INTEGRATION S3_STORAGE_INTEGRATION TO ROLE DATA_ENGINEER_ROLE;
GRANT USAGE ON INTEGRATION EMAIL_NOTIFICATION_INTEGRATION TO ROLE DATA_ENGINEER_ROLE;

-- ============================================================
-- STEP 1: Switch to pipeline role
-- ============================================================
USE ROLE DATA_ENGINEER_ROLE;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================
-- STEP 2: Create databases and schemas
-- ============================================================
CREATE DATABASE IF NOT EXISTS ANALYTICS_DB;

CREATE SCHEMA IF NOT EXISTS ANALYTICS_DB.RAW;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_DB.DIM;
CREATE SCHEMA IF NOT EXISTS ANALYTICS_DB.DQ_MONITORING;

-- ============================================================
-- STEP 3: File Format
-- ============================================================
USE SCHEMA ANALYTICS_DB.RAW;

CREATE OR REPLACE FILE FORMAT CSV_FORMAT
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    SKIP_HEADER = 1
    NULL_IF = ('', 'NULL', 'null', 'N/A', 'NA')
    EMPTY_FIELD_AS_NULL = TRUE
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    TRIM_SPACE = TRUE
    DATE_FORMAT = 'YYYY-MM-DD'
    TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS';

-- ============================================================
-- STEP 4: External Stage
-- ============================================================
CREATE OR REPLACE STAGE S3_TRANSACTION_STAGE
    STORAGE_INTEGRATION = S3_STORAGE_INTEGRATION
    URL = 's3://your-bucket/transactions/incoming/'
    FILE_FORMAT = CSV_FORMAT
    COMMENT = 'Landing zone for TRANSACTION CSV files from AWS S3';

-- Verify connectivity
LIST @S3_TRANSACTION_STAGE;

-- ============================================================
-- STEP 5: Target Table
-- ============================================================
CREATE TABLE IF NOT EXISTS ANALYTICS_DB.RAW.TRANSACTION (
    TRANSACTION_ID   VARCHAR(36)       NOT NULL,
    CUSTOMER_ID      VARCHAR(36)       NOT NULL,
    PRODUCT_ID       VARCHAR(36)       NOT NULL,
    TRANSACTION_DATE DATE              NOT NULL,
    AMOUNT           FLOAT             NOT NULL,
    QUANTITY         INT               NOT NULL,
    STATUS           VARCHAR(20)       NOT NULL,
    REGION           VARCHAR(50)       NOT NULL,
    CURRENCY         VARCHAR(3)        NOT NULL,
    CREATED_AT       TIMESTAMP_NTZ     DEFAULT CURRENT_TIMESTAMP(),
    -- Pipeline audit columns (added on load)
    _DQ_PIPELINE_RUN_ID  VARCHAR(36),
    _SOURCE_FILE_NAME    VARCHAR(500),
    _LOADED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_TRANSACTION PRIMARY KEY (TRANSACTION_ID)
);

-- ============================================================
-- STEP 6: Dimension Mock Tables (for FK checks)
-- ============================================================
CREATE TABLE IF NOT EXISTS ANALYTICS_DB.DIM.CUSTOMERS (
    CUSTOMER_ID  VARCHAR(36)  NOT NULL PRIMARY KEY,
    CUSTOMER_NAME VARCHAR(200),
    CREATED_AT   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS ANALYTICS_DB.DIM.PRODUCTS (
    PRODUCT_ID   VARCHAR(36)  NOT NULL PRIMARY KEY,
    PRODUCT_NAME VARCHAR(200),
    CREATED_AT   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Seed dimension tables with IDs matching test CSV files
INSERT INTO ANALYTICS_DB.DIM.CUSTOMERS (CUSTOMER_ID, CUSTOMER_NAME)
SELECT 'CUST-' || LPAD(SEQ4()::STRING, 4, '0'),
       'Customer ' || SEQ4()
FROM TABLE(GENERATOR(ROWCOUNT => 50));

INSERT INTO ANALYTICS_DB.DIM.PRODUCTS (PRODUCT_ID, PRODUCT_NAME)
SELECT 'PROD-' || LPAD(SEQ4()::STRING, 4, '0'),
       'Product ' || SEQ4()
FROM TABLE(GENERATOR(ROWCOUNT => 30));

-- ============================================================
-- STEP 7: Monitoring / Audit Tables
-- ============================================================
USE SCHEMA ANALYTICS_DB.DQ_MONITORING;

CREATE TABLE IF NOT EXISTS FILE_PROCESSING_LOG (
    LOG_ID              INT AUTOINCREMENT PRIMARY KEY,
    PIPELINE_RUN_ID     VARCHAR(36),
    FILE_NAME           VARCHAR(500),
    FILE_SIZE_BYTES     BIGINT,
    ROW_COUNT           INT,
    COLUMN_COUNT        INT,
    PROCESSING_STATUS   VARCHAR(20),    -- PASSED / REJECTED / SKIPPED
    REJECTION_REASONS   VARCHAR(4000),
    ROWS_LOADED         INT,
    PROCESSED_AT        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    TEAM_NAME           VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS DQ_METRICS_LOG (
    METRIC_ID           INT AUTOINCREMENT PRIMARY KEY,
    LOG_ID              INT,
    PIPELINE_RUN_ID     VARCHAR(36),
    FILE_NAME           VARCHAR(500),
    CHECK_NUMBER        INT,
    CHECK_NAME          VARCHAR(100),
    CHECK_CATEGORY      VARCHAR(20),    -- GATE / THRESHOLD / ADVISORY
    CHECK_STATUS        VARCHAR(10),    -- PASS / FAIL / WARN / SKIP
    COLUMN_NAME         VARCHAR(100),
    THRESHOLD_VALUE     VARCHAR(200),
    ACTUAL_VALUE        VARCHAR(200),
    SEVERITY            VARCHAR(10),    -- CRITICAL / HIGH / MEDIUM / LOW
    NOTES               VARCHAR(2000),
    CHECKED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS EMAIL_RECIPIENT_LOG (
    RECIPIENT_ID        INT AUTOINCREMENT PRIMARY KEY,
    EMAIL_ADDRESS       VARCHAR(200)  NOT NULL,
    TEAM_NAME           VARCHAR(100),
    NOTIFICATION_TYPE   VARCHAR(20),   -- FAILURE / ALL / SUMMARY
    IS_ACTIVE           BOOLEAN DEFAULT TRUE,
    ADDED_BY            VARCHAR(100),
    ADDED_AT            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Seed email recipients
INSERT INTO EMAIL_RECIPIENT_LOG (EMAIL_ADDRESS, TEAM_NAME, NOTIFICATION_TYPE, ADDED_BY)
VALUES
    ('data-engineer@yourcompany.com', 'DATA_ENGINEERING', 'FAILURE', 'SYSTEM'),
    ('data-lead@yourcompany.com',     'DATA_ENGINEERING', 'ALL',     'SYSTEM'),
    ('dq-alerts@yourcompany.com',     'DATA_ENGINEERING', 'SUMMARY', 'SYSTEM');
```

---

## 8. Snowpark Python Script — Full Code

> Full Python script delivered separately as `dq_pipeline_main.py`.  
> Architecture summary:

```
dq_pipeline/
├── config.py                   ← PIPELINE_CONFIG dict
├── main.py                     ← Orchestrator: runs checks per file
├── snowflake_connector.py      ← Session factory
├── s3_file_inspector.py        ← Lists stage, reads file metadata
├── dq_checks/
│   ├── check_01_file_size.py
│   ├── check_02_column_count.py
│   ├── check_03_required_columns.py
│   ├── check_04_row_count.py
│   ├── check_05_null_pct.py
│   ├── check_06_data_types.py
│   ├── check_07_primary_key.py
│   ├── check_08_foreign_key.py
│   ├── check_09_duplicates.py
│   ├── check_10_date_range.py
│   ├── check_11_numeric_range.py
│   └── check_12_allowed_values.py
├── loader.py                   ← COPY INTO logic
├── audit_logger.py             ← Writes to both log tables
└── notifier.py                 ← Email via SYSTEM$SEND_EMAIL
```

### Key Design Pattern — DQResult Dataclass

```python
@dataclass
class DQResult:
    check_number:     int
    check_name:       str
    check_category:   str          # GATE | THRESHOLD | ADVISORY
    check_status:     str          # PASS | FAIL | WARN | SKIP
    column_name:      str  = None
    threshold_value:  str  = None
    actual_value:     str  = None
    severity:         str  = "HIGH"
    notes:            str  = ""

# All checks return List[DQResult]
# Orchestrator aggregates → decides PASS / REJECT
```

---

## 9. Email Notification Design

### Email Template

```
Subject: [DQ ALERT] Data Quality Failure — file_04_high_nulls.csv — 2026-05-26 14:32:01

Pipeline Run ID : a3f81c2e-...
Team            : DATA_ENGINEERING
File            : file_04_high_nulls.csv
File Size       : 16,943 bytes
Row Count       : 150
Status          : ❌ REJECTED

─────────────────────────────────────────────────────────────
FAILED CHECKS
─────────────────────────────────────────────────────────────
Check #5 — NULL_COUNT_CHECK                     [CRITICAL]
  Column    : AMOUNT
  Threshold : max 30.0% null
  Actual    : 60.0% null
  Notes     : 90 of 150 rows have null AMOUNT

Check #5 — NULL_COUNT_CHECK                     [HIGH]
  Column    : CUSTOMER_ID
  Threshold : max 30.0% null
  Actual    : 40.0% null
  Notes     : 60 of 150 rows have null CUSTOMER_ID

─────────────────────────────────────────────────────────────
ACTION: File has been quarantined to s3://bucket/quarantine/
Review the file and re-deliver with corrected data.

View full audit log:
  SELECT * FROM ANALYTICS_DB.DQ_MONITORING.DQ_METRICS_LOG
  WHERE FILE_NAME = 'file_04_high_nulls.csv'
  ORDER BY CHECKED_AT DESC;
─────────────────────────────────────────────────────────────
```

---

## 10. Execution Walkthrough

### Step-by-Step Run

```
01  python main.py --config config.py

02  Snowpark session initialised
    Connected to: ANALYTICS_DB.RAW on COMPUTE_WH

03  Listing files from @S3_TRANSACTION_STAGE...
    Found 7 files:
      file_01_happy_path.csv         24,703 bytes
      file_02_low_row_count.csv         477 bytes
      file_03_missing_columns.csv     3,862 bytes
      file_04_high_nulls.csv         16,943 bytes
      file_05_duplicate_pk.csv       12,399 bytes
      file_06_bad_datatypes.csv       9,959 bytes
      file_07_small_file.csv            229 bytes

04  Processing file_07_small_file.csv...
    [CHECK 1] File Size     → FAIL  (229 < 1,048,576 bytes)  ← IMMEDIATE REJECT
    Status: REJECTED | Email sent to 2 recipients

05  Processing file_03_missing_columns.csv...
    [CHECK 1] File Size     → FAIL  (3,862 < 1,048,576 bytes) ← IMMEDIATE REJECT
    [CHECK 2] Column Count  → FAIL  (5 < 7)
    Status: REJECTED | Email sent

    NOTE: For local testing set min_file_size_bytes = 100

06  Processing file_02_low_row_count.csv...
    [CHECK 1] File Size     → PASS (demo mode: threshold=100)
    [CHECK 2] Column Count  → PASS (10 >= 7)
    [CHECK 3] Required Cols → PASS (all 9 present)
    [CHECK 4] Row Count     → FAIL (3 < 10)  ← REJECT
    Status: REJECTED | Email sent

07  Processing file_04_high_nulls.csv...
    [CHECK 1-3]             → PASS
    [CHECK 4] Row Count     → PASS (150 >= 10)
    [CHECK 5] Null AMOUNT   → FAIL (60.0% > 30.0%)  ← REJECT
    [CHECK 5] Null CUST_ID  → FAIL (40.0% > 30.0%)
    Status: REJECTED | Email sent

08  Processing file_05_duplicate_pk.csv...
    [CHECK 1-5]             → PASS
    [CHECK 6] Data Types    → PASS
    [CHECK 7] PK Uniqueness → FAIL (15 duplicate TRANSACTION_IDs)  ← REJECT
    Status: REJECTED | Email sent

09  Processing file_06_bad_datatypes.csv...
    [CHECK 1-5]             → PASS
    [CHECK 6] Data Types    → FAIL (AMOUNT: 20 non-castable rows)  ← REJECT
    Status: REJECTED | Email sent

10  Processing file_01_happy_path.csv...
    [CHECK 1]  File Size        → PASS
    [CHECK 2]  Column Count     → PASS (10 >= 7)
    [CHECK 3]  Required Cols    → PASS
    [CHECK 4]  Row Count        → PASS (200 >= 10)
    [CHECK 5]  Null Check       → PASS (all columns 0% null)
    [CHECK 6]  Data Types       → PASS
    [CHECK 7]  PK Uniqueness    → PASS (200 distinct IDs)
    [CHECK 8]  FK Constraints   → PASS
    [CHECK 9]  Duplicate Rows   → PASS (0% dupes)
    [CHECK 10] Date Range       → PASS
    [CHECK 11] Numeric Range    → PASS
    [CHECK 12] Allowed Values   → PASS
    → COPY INTO RAW.TRANSACTION (200 rows loaded)
    → File moved to /processed/
    Status: PASSED | 200 rows loaded

11  Pipeline Run Complete
    Files processed : 7
    Passed          : 1
    Rejected        : 6
    Total rows loaded: 200
    Run ID          : a3f81c2e-7b9d-4c3e-91f2-...
    Summary email sent.
```

---

## 11. Expected Results per File

| File | Check That Triggers Rejection | Action |
|---|---|---|
| `file_01_happy_path.csv` | None | Loaded to RAW.TRANSACTION (200 rows) |
| `file_02_low_row_count.csv` | Check 4 — Row count = 3 < 10 | Quarantined + Email |
| `file_03_missing_columns.csv` | Check 2 — Column count = 5 < 7 | Quarantined + Email |
| `file_04_high_nulls.csv` | Check 5 — AMOUNT 60% null > 30% | Quarantined + Email |
| `file_05_duplicate_pk.csv` | Check 7 — 15 duplicate PKs | Quarantined + Email |
| `file_06_bad_datatypes.csv` | Check 6 — AMOUNT not numeric | Quarantined + Email |
| `file_07_small_file.csv` | Check 1 — 229 bytes < 1 MB | Quarantined + Email |

### Audit Query After Run

```sql
-- Summary of all files in last run
SELECT
    FILE_NAME,
    FILE_SIZE_BYTES,
    ROW_COUNT,
    COLUMN_COUNT,
    PROCESSING_STATUS,
    REJECTION_REASONS,
    ROWS_LOADED,
    PROCESSED_AT
FROM ANALYTICS_DB.DQ_MONITORING.FILE_PROCESSING_LOG
WHERE PIPELINE_RUN_ID = '<your-run-id>'
ORDER BY PROCESSED_AT;

-- Drill into a specific file's checks
SELECT
    CHECK_NUMBER,
    CHECK_NAME,
    CHECK_CATEGORY,
    CHECK_STATUS,
    COLUMN_NAME,
    THRESHOLD_VALUE,
    ACTUAL_VALUE,
    SEVERITY,
    NOTES
FROM ANALYTICS_DB.DQ_MONITORING.DQ_METRICS_LOG
WHERE FILE_NAME = 'file_04_high_nulls.csv'
ORDER BY CHECK_NUMBER, COLUMN_NAME;
```

---

## 12. Deployment Guide

### Prerequisites

```bash
# Python 3.8+
pip install snowflake-snowpark-python
pip install pandas boto3
```

### AWS IAM Role Setup

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket",
        "s3:PutObject",     
        "s3:DeleteObject"   
      ],
      "Resource": [
        "arn:aws:iam::123456789012:role/snowflake-s3-role",
        "arn:aws:iam::123456789012:role/snowflake-s3-role/*"
      ]
    }
  ]
}
```

### Trust Policy (add Snowflake IAM user from DESC INTEGRATION output)

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "AWS": "arn:aws:iam::SNOWFLAKE_ACCOUNT_ID:user/SNOWFLAKE_USER"
    },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": {
        "sts:ExternalId": "SNOWFLAKE_EXTERNAL_ID"
      }
    }
  }]
}
```

### Running the Pipeline

```bash
# Set credentials via environment variables (never hardcode)
export SNOWFLAKE_PASSWORD="your_password"
export SNOWFLAKE_ACCOUNT="your_account"

# Run
python main.py

# Or run with a custom config
python main.py --config /path/to/team_specific_config.py
```

### Scheduling (Snowflake Task)

```sql
CREATE TASK DQ_PIPELINE_DAILY_TASK
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = 'USING CRON 0 6 * * * UTC'   -- 6 AM UTC daily
AS
    CALL DQ_PIPELINE_STORED_PROC();
```

---

## 13. Troubleshooting & FAQ

### Q: All files fail file size check in local testing
**A:** Set `min_file_size_bytes` to `100` in config for local testing. Restore to `1048576` for production.

### Q: FK checks fail even for file_01
**A:** Ensure DIM.CUSTOMERS and DIM.PRODUCTS are seeded with IDs matching the CSV (CUST-0001 to CUST-0050, PROD-0001 to PROD-0030). Run the seed INSERT statements in DDL Step 6.

### Q: Email not sending
**A:** Verify your Snowflake edition supports SYSTEM$SEND_EMAIL (Enterprise or Business Critical required). Check that EMAIL_NOTIFICATION_INTEGRATION is ENABLED. The sender email must be verified in your Snowflake account.

### Q: COPY INTO fails with parsing errors
**A:** Check FILE FORMAT settings. Ensure SKIP_HEADER=1 and NULL_IF includes all null representations present in your files.

### Q: How to add a new team
**A:** Copy config.py, update all parameters (database, schema, S3 bucket, thresholds, team_name, recipients), and run. Each team gets its own isolated config. All monitoring tables can be shared or separated by team_name filter.

### Q: How to add a new DQ check
**A:** Create a new file in dq_checks/, return a List[DQResult], import and call it in main.py's check sequence. Add the check to DQ_METRICS_LOG. No other changes needed.

---

*End of Documentation *
