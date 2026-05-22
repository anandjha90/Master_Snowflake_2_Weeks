-- ============================================================
-- DAY 5 TRAINING: ENVIRONMENT SETUP
-- ============================================================

-- Step 1: Create or use the warehouse
USE ROLE SYSADMIN;
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WITH WAREHOUSE_SIZE = 'MEDIUM'
  AUTO_SUSPEND = 300
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

-- ALTER WAREHOUSE COMPUTE_WH
-- SET WAREHOUSE_SIZE = 'MEDIUM';


-- Step 2: Create the training database and schema
CREATE DATABASE IF NOT EXISTS DAY5_TRAINING_DB;
USE DATABASE DAY5_TRAINING_DB;
CREATE SCHEMA IF NOT EXISTS DAY5_DEMO;
USE SCHEMA DAY5_DEMO;
USE WAREHOUSE COMPUTE_WH;

-- Step 3: Create a CSV file format
CREATE OR REPLACE FILE FORMAT DAY5_CSV_FORMAT
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  RECORD_DELIMITER = '\n'
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('NULL', 'null', '')
  EMPTY_FIELD_AS_NULL = TRUE
  COMPRESSION = 'AUTO';

-- Step 4: Create a named internal stage
CREATE OR REPLACE STAGE DAY5_INTERNAL_STAGE
  FILE_FORMAT = DAY5_CSV_FORMAT
  COMMENT = 'Internal stage for Day 5 training data';

-- Step 5: Create the main orders table (no clustering key yet)
CREATE OR REPLACE TABLE ORDERS_RAW (
  ORDER_ID         NUMBER(10,0),
  ORDER_DATE       DATE,
  CUSTOMER_ID      NUMBER(10,0),
  CUSTOMER_NAME    VARCHAR(100),
  REGION           VARCHAR(50),
  COUNTRY          VARCHAR(50),
  CITY             VARCHAR(50),
  DEPARTMENT       VARCHAR(50),
  PRODUCT_CATEGORY VARCHAR(50),
  PRODUCT_NAME     VARCHAR(100),
  QUANTITY         NUMBER(10,0),
  UNIT_PRICE       NUMBER(12,2),
  TOTAL_AMOUNT     NUMBER(15,2),
  PAYMENT_METHOD   VARCHAR(50),
  ORDER_STATUS     VARCHAR(20),
  SALES_CHANNEL    VARCHAR(50),
  FISCAL_YEAR      NUMBER(4,0),
  FISCAL_QUARTER   VARCHAR(5)
);

-- Open Command Prompt / Terminal and run:
-- snowsql -a <account_identifier> -u <username>
-- It will ask for password.
-- You can find your account identifier from:
-- SELECT CURRENT_ACCOUNT();

-- Set Context in SnowSQL:
-- After login:
-- USE ROLE SYSADMIN;
-- USE WAREHOUSE COMPUTE_WH;
-- USE DATABASE DAY5_TRAINING_DB;
-- USE SCHEMA DAY5_DEMO;

-- Upload CSV File Using PUT Command

-- PUT file://C:/Users/YourName/Downloads/day5_training_dataset.csv
-- @DAY5_INTERNAL_STAGE
-- AUTO_COMPRESS=TRUE
-- PARALLEL=4;
-- Use forward slashes /
-- No spaces in file path unless quoted
-- File must exist locally

-- AUTO_COMPRESS=TRUE => Snowflake automatically compresses the file before storing it.
-- Your CSV:
-- day5_training_dataset.csv => becomes => day5_training_dataset.csv.gz

-- Benefits:
-- Faster upload
-- Less storage
-- Faster loading
-- Usually keep this as TRUE.

-- PARALLEL=4 => Controls how many threads SnowSQL uses for uploading.
-- means: Use 4 parallel upload threads
-- Useful for large files Higher value, Faster upload, More CPU/network usage
-- Typical values: 4, 8, 16

-- Step 6b: Verify the file is staged
LIST @DAY5_INTERNAL_STAGE;

-- Step 7: Bulk load data using COPY INTO
COPY INTO ORDERS_RAW
  FROM @DAY5_INTERNAL_STAGE
  FILE_FORMAT = DAY5_CSV_FORMAT
  ON_ERROR = 'CONTINUE'
  PURGE = FALSE;

-- Step 8: Validate the load
SELECT COUNT(*) AS total_records FROM ORDERS_RAW;   -- 5M records
-- Expected output: 5,000,000

SELECT * FROM ORDERS_RAW LIMIT 10;

-- ============================================================
-- LAB 1A: BASELINE QUERIES (BEFORE CLUSTERING)
-- ============================================================
USE DATABASE DAY5_TRAINING_DB;
USE SCHEMA DAY5_DEMO;
USE WAREHOUSE COMPUTE_WH;

-- IMPORTANT: Disable result cache so we get real execution times
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- Check current clustering information (no key defined yet)
SELECT SYSTEM$CLUSTERING_INFORMATION('ORDERS_RAW', '(ORDER_DATE)');
-- Expected: cluster_depth will be high (poor clustering)

SELECT SYSTEM$CLUSTERING_DEPTH('ORDERS_RAW', '(ORDER_DATE)');
-- Expected: High value (e.g., 50+) indicating significant overlap

-- ── Baseline Query 1: Filter by specific date ──
-- Tag the query so we can find it in QUERY_HISTORY later
ALTER SESSION SET QUERY_TAG = 'BEFORE_CLUSTERING_Q1';

SELECT COUNT(*) AS order_count, SUM(TOTAL_AMOUNT) AS total_revenue
FROM ORDERS_RAW
WHERE ORDER_DATE = '2024-06-15';

-- Capture Query 1 timing immediately via LAST_QUERY_ID()
SET BEFORE_Q1_ID = LAST_QUERY_ID();
SELECT $BEFORE_Q1_ID AS before_q1_query_id;

-- ── Baseline Query 2: Filter by date range ──
ALTER SESSION SET QUERY_TAG = 'BEFORE_CLUSTERING_Q2';

SELECT REGION, COUNT(*) AS order_count, SUM(TOTAL_AMOUNT) AS revenue
FROM ORDERS_RAW
WHERE ORDER_DATE BETWEEN '2024-01-01' AND '2024-03-31'
GROUP BY REGION
ORDER BY revenue DESC;

SET BEFORE_Q2_ID = LAST_QUERY_ID();
SELECT $BEFORE_Q2_ID AS before_q2_query_id;

-- ── Baseline Query 3: Filter by region + date ──
ALTER SESSION SET QUERY_TAG = 'BEFORE_CLUSTERING_Q3';

SELECT PRODUCT_CATEGORY, COUNT(*) AS cnt, AVG(TOTAL_AMOUNT) AS avg_order
FROM ORDERS_RAW
WHERE REGION = 'Asia Pacific'
  AND ORDER_DATE BETWEEN '2024-06-01' AND '2024-06-30'
GROUP BY PRODUCT_CATEGORY
ORDER BY cnt DESC;

SET BEFORE_Q3_ID = LAST_QUERY_ID();
SELECT $BEFORE_Q3_ID AS before_q3_query_id;

-- Reset query tag
ALTER SESSION SET QUERY_TAG = '';

-- ── Quick-look: Pull timing for all 3 baseline queries ──
-- Note: INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION() does not expose
--       PARTITIONS_SCANNED/PARTITIONS_TOTAL. Use query profile in Snowsight
--       to inspect partition pruning, or wait ~45 min and query
--       SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY instead.
SELECT
  QUERY_TAG,
  QUERY_ID,
  TOTAL_ELAPSED_TIME / 1000          AS elapsed_sec,
  EXECUTION_TIME / 1000              AS exec_sec,
  COMPILATION_TIME / 1000            AS compile_sec,
  BYTES_SCANNED / POWER(1024,2)      AS mb_scanned,
  ROWS_PRODUCED
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION())
WHERE QUERY_TAG LIKE 'BEFORE_CLUSTERING%'
ORDER BY START_TIME;
-- Expected: All partitions scanned (pct_partitions_scanned ~ 100%)


-- ============================================================
-- LAB 1B: APPLY CLUSTERING KEY
-- ============================================================

-- Ensure cache is still disabled
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- Create a clustered copy of the table
CREATE OR REPLACE TABLE ORDERS_CLUSTERED
  CLUSTER BY (ORDER_DATE, REGION)
AS
  SELECT * FROM ORDERS_RAW
  ORDER BY ORDER_DATE, REGION;

-- Verify clustering key is set
SHOW TABLES LIKE 'ORDERS_CLUSTERED';
-- Look for the 'cluster_by' column in the output

-- Check clustering information AFTER clustering
SELECT SYSTEM$CLUSTERING_INFORMATION('ORDERS_CLUSTERED', '(ORDER_DATE)');
-- Expected: cluster_depth close to 1.0 (well-clustered!)

SELECT SYSTEM$CLUSTERING_DEPTH('ORDERS_CLUSTERED', '(ORDER_DATE)');
-- Expected: Low value (e.g., 1-3)

-- ── After-Clustering Query 1: Same filter by specific date ──
ALTER SESSION SET QUERY_TAG = 'AFTER_CLUSTERING_Q1';

SELECT COUNT(*) AS order_count, SUM(TOTAL_AMOUNT) AS total_revenue
FROM ORDERS_CLUSTERED
WHERE ORDER_DATE = '2024-06-15';

SET AFTER_Q1_ID = LAST_QUERY_ID();

-- ── After-Clustering Query 2: Same date range filter ──
ALTER SESSION SET QUERY_TAG = 'AFTER_CLUSTERING_Q2';

SELECT REGION, COUNT(*) AS order_count, SUM(TOTAL_AMOUNT) AS revenue
FROM ORDERS_CLUSTERED
WHERE ORDER_DATE BETWEEN '2024-01-01' AND '2024-03-31'
GROUP BY REGION
ORDER BY revenue DESC;

SET AFTER_Q2_ID = LAST_QUERY_ID();

-- ── After-Clustering Query 3: Same region + date filter ──
ALTER SESSION SET QUERY_TAG = 'AFTER_CLUSTERING_Q3';

SELECT PRODUCT_CATEGORY, COUNT(*) AS cnt, AVG(TOTAL_AMOUNT) AS avg_order
FROM ORDERS_CLUSTERED
WHERE REGION = 'Asia Pacific'
  AND ORDER_DATE BETWEEN '2024-06-01' AND '2024-06-30'
GROUP BY PRODUCT_CATEGORY
ORDER BY cnt DESC;

SET AFTER_Q3_ID = LAST_QUERY_ID();

-- Reset query tag
ALTER SESSION SET QUERY_TAG = '';

-- ── Quick-look: Pull timing for all 3 after-clustering queries ──
-- Note: PARTITIONS_SCANNED/PARTITIONS_TOTAL not available in
--       INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(). Use query profile
--       or SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY (45 min latency).
SELECT
  QUERY_TAG,
  QUERY_ID,
  TOTAL_ELAPSED_TIME / 1000          AS elapsed_sec,
  EXECUTION_TIME / 1000              AS exec_sec,
  BYTES_SCANNED / POWER(1024,2)      AS mb_scanned,
  ROWS_PRODUCED
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION())
WHERE QUERY_TAG LIKE 'AFTER_CLUSTERING%'
ORDER BY START_TIME;
-- Expected: pct_partitions_scanned drops to ~5-15% !

-- ============================================================
-- LAB 1B-2: BEFORE vs AFTER TIMING COMPARISON
-- ============================================================

-- Method 1: Using QUERY_TAG (recommended for training demos)
-- This pulls both BEFORE and AFTER results into one comparison

WITH before_stats AS (
  SELECT
    REPLACE(QUERY_TAG, 'BEFORE_CLUSTERING_', '') AS query_label,
    TOTAL_ELAPSED_TIME        AS elapsed_ms,
    EXECUTION_TIME             AS exec_ms,
    BYTES_SCANNED              AS bytes_scanned,
    ROWS_PRODUCED
  FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION())
  WHERE QUERY_TAG LIKE 'BEFORE_CLUSTERING_Q%'
),
after_stats AS (
  SELECT
    REPLACE(QUERY_TAG, 'AFTER_CLUSTERING_', '') AS query_label,
    TOTAL_ELAPSED_TIME        AS elapsed_ms,
    EXECUTION_TIME             AS exec_ms,
    BYTES_SCANNED              AS bytes_scanned,
    ROWS_PRODUCED
  FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION())
  WHERE QUERY_TAG LIKE 'AFTER_CLUSTERING_Q%'
)
SELECT
  b.query_label,
  '--- TIME (ms) ---'         AS "_",
  b.elapsed_ms                 AS before_elapsed_ms,
  a.elapsed_ms                 AS after_elapsed_ms,
  ROUND((b.elapsed_ms - a.elapsed_ms)
        / NULLIF(b.elapsed_ms, 0) * 100, 1)
                               AS time_improvement_pct,
  '--- BYTES ---'             AS "__",
  ROUND(b.bytes_scanned / POWER(1024,2), 1)
                               AS before_mb_scanned,
  ROUND(a.bytes_scanned / POWER(1024,2), 1)
                               AS after_mb_scanned,
  ROUND((b.bytes_scanned - a.bytes_scanned)
        / NULLIF(b.bytes_scanned, 0) * 100, 1)
                               AS bytes_reduction_pct
FROM before_stats b
JOIN after_stats a ON b.query_label = a.query_label
ORDER BY b.query_label;

/*
  EXPECTED OUTPUT (approximate):
  ┌───────┬──────────────┬─────────────┬────────────┬───────────┬...
  │ LABEL │ BEFORE_MS    │ AFTER_MS    │ TIME_IMP % │ PRUNE %  │
  ├───────┼──────────────┼─────────────┼────────────┼───────────┤
  │ Q1    │ 4500 - 8000  │ 300 - 800   │  80 - 93%  │ 85 - 97% │
  │ Q2    │ 5000 - 9000  │ 800 - 2000  │  70 - 85%  │ 70 - 85% │
  │ Q3    │ 4000 - 7000  │ 200 - 600   │  85 - 95%  │ 90 - 98% │
  └───────┴──────────────┴─────────────┴────────────┴───────────┘
  Exact numbers depend on warehouse size and Snowflake load.
*/

-- Method 2: Using stored QUERY_ID variables for individual lookup
-- Useful when you want to compare a single query pair
SELECT
  'BEFORE' AS phase, QUERY_ID,
  TOTAL_ELAPSED_TIME / 1000 AS elapsed_sec,
  BYTES_SCANNED / POWER(1024,2) AS mb_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE QUERY_ID = $BEFORE_Q1_ID
UNION ALL
SELECT
  'AFTER' AS phase, QUERY_ID,
  TOTAL_ELAPSED_TIME / 1000 AS elapsed_sec,
  BYTES_SCANNED / POWER(1024,2) AS mb_scanned
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
WHERE QUERY_ID = $AFTER_Q1_ID;

-- Method 3: Cluster depth comparison (summary view)
SELECT
  'BEFORE (ORDERS_RAW)' AS table_label,
  PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION(
    'ORDERS_RAW','(ORDER_DATE)')):
    average_depth::FLOAT AS avg_depth,
  PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION(
    'ORDERS_RAW','(ORDER_DATE)')):
    average_overlaps::FLOAT AS avg_overlaps
UNION ALL
SELECT
  'AFTER (ORDERS_CLUSTERED)' AS table_label,
  PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION(
    'ORDERS_CLUSTERED','(ORDER_DATE)')):
    average_depth::FLOAT AS avg_depth,
  PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION(
    'ORDERS_CLUSTERED','(ORDER_DATE)')):
    average_overlaps::FLOAT AS avg_overlaps;

/*
  EXPECTED OUTPUT:
  ┌────────────────────────────┬───────────┬──────────────┐
  │ TABLE_LABEL                │ AVG_DEPTH │ AVG_OVERLAPS │
  ├────────────────────────────┼───────────┼──────────────┤
  │ BEFORE (ORDERS_RAW)        │  45 - 60  │  40 - 55     │
  │ AFTER  (ORDERS_CLUSTERED)  │  1 - 3    │  0.5 - 2     │
  └────────────────────────────┴───────────┴──────────────┘
*/

-- Re-enable result cache for normal operations
ALTER SESSION SET USE_CACHED_RESULT = TRUE;

-- ============================================================
-- LAB 1C: MANUAL RECLUSTERING
-- ============================================================

-- Simulate DML drift by inserting new random data
INSERT INTO ORDERS_CLUSTERED
SELECT
  ORDER_ID + 5000000,
  DATEADD(day, UNIFORM(0, 1460, RANDOM()), '2022-01-01'::DATE),
  CUSTOMER_ID, CUSTOMER_NAME, REGION, COUNTRY, CITY,
  DEPARTMENT, PRODUCT_CATEGORY, PRODUCT_NAME,
  QUANTITY, UNIT_PRICE, TOTAL_AMOUNT,
  PAYMENT_METHOD, ORDER_STATUS, SALES_CHANNEL,
  FISCAL_YEAR, FISCAL_QUARTER
FROM ORDERS_RAW
LIMIT 500000;

-- Check clustering depth after new inserts
SELECT SYSTEM$CLUSTERING_DEPTH('ORDERS_CLUSTERED', '(ORDER_DATE)');
-- Expected: Cluster depth has increased (degraded)

-- Manual recluster (Enterprise Edition feature)
-- ALTER TABLE ORDERS_CLUSTERED RECLUSTER;
-- Note: RECLUSTER is deprecated in favor of Automatic Clustering
-- Shown here for conceptual understanding only

-- Alternative: Recreate the table with ordering
CREATE OR REPLACE TABLE ORDERS_CLUSTERED
  CLUSTER BY (ORDER_DATE, REGION)
AS
  SELECT * FROM ORDERS_CLUSTERED
  ORDER BY ORDER_DATE, REGION;

-- Verify depth is improved again
SELECT SYSTEM$CLUSTERING_DEPTH('ORDERS_CLUSTERED', '(ORDER_DATE)');

-- ============================================================
-- LAB 1D: CLUSTERING SYSTEM FUNCTIONS
-- ============================================================

-- SYSTEM$CLUSTERING_INFORMATION returns JSON with detailed metrics
SELECT SYSTEM$CLUSTERING_INFORMATION('ORDERS_CLUSTERED', '(ORDER_DATE)');
/*
  Expected JSON output includes:
  - cluster_by_keys: The defined clustering columns
  - total_partition_count: Total micro-partitions
  - total_constant_partition_count: Partitions with single value
  - average_overlaps: Average overlap (lower = better)
  - average_depth: Average cluster depth (lower = better)
  - partition_depth_histogram: Distribution of depths
*/

-- Parse the JSON for a cleaner view
SELECT
  PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION(
    'ORDERS_CLUSTERED', '(ORDER_DATE)')):
    average_depth::FLOAT AS avg_depth,
  PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION(
    'ORDERS_CLUSTERED', '(ORDER_DATE)')):
    average_overlaps::FLOAT AS avg_overlaps,
  PARSE_JSON(SYSTEM$CLUSTERING_INFORMATION(
    'ORDERS_CLUSTERED', '(ORDER_DATE)')):
    total_partition_count::INT AS total_partitions;

-- Compare clustering on different columns
SELECT SYSTEM$CLUSTERING_INFORMATION('ORDERS_CLUSTERED', '(REGION)');
SELECT SYSTEM$CLUSTERING_INFORMATION('ORDERS_CLUSTERED', '(PRODUCT_CATEGORY)');
SELECT SYSTEM$CLUSTERING_INFORMATION('ORDERS_CLUSTERED', '(ORDER_DATE, REGION)');

-- ============================================================
-- LAB 2: AUTOMATIC CLUSTERING
-- ============================================================

-- Step 1: Create a table WITH a clustering key
-- (Automatic clustering activates when a clustering key is defined)
CREATE OR REPLACE TABLE ORDERS_AUTO_CLUSTERED
  CLUSTER BY (ORDER_DATE, REGION)
AS
  SELECT * FROM ORDERS_RAW;

-- Note: Data was loaded randomly, so clustering is initially poor
-- Automatic clustering will begin working in the background

-- Step 2: Check current clustering state
SELECT SYSTEM$CLUSTERING_INFORMATION(
  'ORDERS_AUTO_CLUSTERED', '(ORDER_DATE, REGION)');

-- Step 3: Verify clustering key is defined
SHOW TABLES LIKE 'ORDERS_AUTO_CLUSTERED';

-- Step 4: Suspend automatic clustering (if needed for cost control)
ALTER TABLE ORDERS_AUTO_CLUSTERED SUSPEND RECLUSTER;

-- Step 5: Resume automatic clustering
ALTER TABLE ORDERS_AUTO_CLUSTERED RESUME RECLUSTER;

-- Step 6: Drop a clustering key entirely
-- ALTER TABLE ORDERS_AUTO_CLUSTERED DROP CLUSTERING KEY;

-- Step 7: Change the clustering key
ALTER TABLE ORDERS_AUTO_CLUSTERED
  CLUSTER BY (ORDER_DATE, PRODUCT_CATEGORY);

-- ============================================================
-- LAB 2B: MONITORING AUTOMATIC CLUSTERING
-- ============================================================

-- Query the AUTOMATIC_CLUSTERING_HISTORY view
-- (Requires ACCOUNTADMIN or MONITOR privilege)
USE ROLE ACCOUNTADMIN;

SELECT *
FROM SNOWFLAKE.ACCOUNT_USAGE.AUTOMATIC_CLUSTERING_HISTORY
WHERE TABLE_NAME = 'ORDERS_AUTO_CLUSTERED'
  AND START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC;

-- Check credit consumption for automatic clustering
SELECT
  TO_DATE(START_TIME) AS cluster_date,
  TABLE_NAME,
  SUM(CREDITS_USED) AS total_credits,
  SUM(NUM_BYTES_RECLUSTERED) / POWER(1024,3) AS gb_reclustered,
  SUM(NUM_ROWS_RECLUSTERED) AS rows_reclustered
FROM SNOWFLAKE.ACCOUNT_USAGE.AUTOMATIC_CLUSTERING_HISTORY
WHERE START_TIME >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY cluster_date DESC;

-- Information Schema alternative (real-time, last 14 days)
SELECT *
FROM TABLE(INFORMATION_SCHEMA.AUTOMATIC_CLUSTERING_HISTORY(
  DATE_RANGE_START => DATEADD(day, -14, CURRENT_TIMESTAMP()),
  DATE_RANGE_END => CURRENT_TIMESTAMP()
));

-- ============================================================
-- LAB 3A: ROW-LEVEL SECURITY SETUP
-- ============================================================
USE ROLE SECURITYADMIN;

-- Step 1: Create regional analyst roles
CREATE ROLE IF NOT EXISTS INDIA_ANALYST;
CREATE ROLE IF NOT EXISTS US_ANALYST;
CREATE ROLE IF NOT EXISTS EUROPE_ANALYST;
CREATE ROLE IF NOT EXISTS GLOBAL_ANALYST;
CREATE ROLE IF NOT EXISTS RLS_ADMIN;

-- Step 2: Grant roles to SYSADMIN for hierarchy
GRANT ROLE INDIA_ANALYST TO ROLE SYSADMIN;
GRANT ROLE US_ANALYST TO ROLE SYSADMIN;
GRANT ROLE EUROPE_ANALYST TO ROLE SYSADMIN;
GRANT ROLE GLOBAL_ANALYST TO ROLE SYSADMIN;
GRANT ROLE RLS_ADMIN TO ROLE SYSADMIN;

-- Step 3: Grant necessary privileges
USE ROLE SYSADMIN;
GRANT USAGE ON DATABASE DAY5_TRAINING_DB TO ROLE INDIA_ANALYST;
GRANT USAGE ON DATABASE DAY5_TRAINING_DB TO ROLE US_ANALYST;
GRANT USAGE ON DATABASE DAY5_TRAINING_DB TO ROLE EUROPE_ANALYST;
GRANT USAGE ON DATABASE DAY5_TRAINING_DB TO ROLE GLOBAL_ANALYST;
GRANT USAGE ON DATABASE DAY5_TRAINING_DB TO ROLE RLS_ADMIN;

GRANT USAGE ON SCHEMA DAY5_TRAINING_DB.DAY5_DEMO TO ROLE INDIA_ANALYST;
GRANT USAGE ON SCHEMA DAY5_TRAINING_DB.DAY5_DEMO TO ROLE US_ANALYST;
GRANT USAGE ON SCHEMA DAY5_TRAINING_DB.DAY5_DEMO TO ROLE EUROPE_ANALYST;
GRANT USAGE ON SCHEMA DAY5_TRAINING_DB.DAY5_DEMO TO ROLE GLOBAL_ANALYST;
GRANT USAGE ON SCHEMA DAY5_TRAINING_DB.DAY5_DEMO TO ROLE RLS_ADMIN;

GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE INDIA_ANALYST;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE US_ANALYST;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE EUROPE_ANALYST;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE GLOBAL_ANALYST;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE RLS_ADMIN;

-- ============================================================
-- LAB 3B: MAPPING TABLE FOR RLS
-- ============================================================
USE ROLE SYSADMIN;
USE DATABASE DAY5_TRAINING_DB;
USE SCHEMA DAY5_DEMO;

-- Create a mapping table that links roles to allowed countries
CREATE OR REPLACE TABLE ROLE_COUNTRY_MAPPING (
  ROLE_NAME   VARCHAR(50),
  COUNTRY     VARCHAR(50)
);

-- Insert mappings
INSERT INTO ROLE_COUNTRY_MAPPING VALUES
  ('INDIA_ANALYST', 'India'),
  ('US_ANALYST', 'USA'),
  ('US_ANALYST', 'Canada'),
  ('US_ANALYST', 'Mexico'),
  ('EUROPE_ANALYST', 'UK'),
  ('EUROPE_ANALYST', 'Germany'),
  ('EUROPE_ANALYST', 'France'),
  ('EUROPE_ANALYST', 'Netherlands'),
  ('EUROPE_ANALYST', 'Spain');
-- GLOBAL_ANALYST is NOT mapped => will get full access via policy logic

-- Verify
SELECT * FROM ROLE_COUNTRY_MAPPING ORDER BY ROLE_NAME;

-- Grant SELECT on mapping table to all roles
GRANT SELECT ON TABLE ROLE_COUNTRY_MAPPING TO ROLE INDIA_ANALYST;
GRANT SELECT ON TABLE ROLE_COUNTRY_MAPPING TO ROLE US_ANALYST;
GRANT SELECT ON TABLE ROLE_COUNTRY_MAPPING TO ROLE EUROPE_ANALYST;
GRANT SELECT ON TABLE ROLE_COUNTRY_MAPPING TO ROLE GLOBAL_ANALYST;
GRANT SELECT ON TABLE ROLE_COUNTRY_MAPPING TO ROLE RLS_ADMIN;

-- ============================================================
-- LAB 3C: SECURE TABLE FOR RLS DEMO
-- ============================================================

-- Create a secure copy of orders for RLS testing
CREATE OR REPLACE TABLE ORDERS_SECURE AS
  SELECT * FROM ORDERS_RAW;

-- Grant SELECT to all analyst roles
GRANT SELECT ON TABLE ORDERS_SECURE TO ROLE INDIA_ANALYST;
GRANT SELECT ON TABLE ORDERS_SECURE TO ROLE US_ANALYST;
GRANT SELECT ON TABLE ORDERS_SECURE TO ROLE EUROPE_ANALYST;
GRANT SELECT ON TABLE ORDERS_SECURE TO ROLE GLOBAL_ANALYST;
GRANT SELECT ON TABLE ORDERS_SECURE TO ROLE RLS_ADMIN;

-- ============================================================
-- LAB 3D: ROW ACCESS POLICY CREATION
-- ============================================================
USE ROLE SYSADMIN;
USE DATABASE DAY5_TRAINING_DB;
USE SCHEMA DAY5_DEMO;

-- Create the Row Access Policy
CREATE OR REPLACE ROW ACCESS POLICY COUNTRY_RLS_POLICY
  AS (country_val VARCHAR) RETURNS BOOLEAN ->
    -- SYSADMIN and RLS_ADMIN see everything
    IS_ROLE_IN_SESSION('SYSADMIN')
    OR IS_ROLE_IN_SESSION('RLS_ADMIN')
    -- GLOBAL_ANALYST sees everything
    OR IS_ROLE_IN_SESSION('GLOBAL_ANALYST')
    -- Regional analysts see only their mapped countries
    OR EXISTS (
      SELECT 1 FROM DAY5_TRAINING_DB.DAY5_DEMO.ROLE_COUNTRY_MAPPING m
      WHERE IS_ROLE_IN_SESSION(m.ROLE_NAME)
        AND m.COUNTRY = country_val
    );

-- Apply the policy to the ORDERS_SECURE table
ALTER TABLE ORDERS_SECURE ADD ROW ACCESS POLICY COUNTRY_RLS_POLICY
  ON (COUNTRY);

-- Verify the policy is attached
SELECT *
FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
  REF_ENTITY_NAME => 'DAY5_TRAINING_DB.DAY5_DEMO.ORDERS_SECURE',
  REF_ENTITY_DOMAIN => 'TABLE'
));

-- ============================================================
-- LAB 3E: TESTING ROW ACCESS POLICY
-- ============================================================

-- Test 1: INDIA_ANALYST should see only India data
USE ROLE INDIA_ANALYST;
USE WAREHOUSE COMPUTE_WH;

SELECT COUNTRY, COUNT(*) AS row_count
FROM DAY5_TRAINING_DB.DAY5_DEMO.ORDERS_SECURE
GROUP BY COUNTRY
ORDER BY row_count DESC;

SELECT COUNT(*) AS total_visible FROM DAY5_TRAINING_DB.DAY5_DEMO.ORDERS_SECURE;

-- Test 2: US_ANALYST should see USA, Canada, Mexico
USE ROLE US_ANALYST;

SELECT COUNTRY, COUNT(*) AS row_count
FROM DAY5_TRAINING_DB.DAY5_DEMO.ORDERS_SECURE
GROUP BY COUNTRY
ORDER BY row_count DESC;
-- Expected: USA, Canada, Mexico

-- Test 3: EUROPE_ANALYST should see UK, Germany, France, etc.
USE ROLE EUROPE_ANALYST;

SELECT COUNTRY, COUNT(*) AS row_count
FROM DAY5_TRAINING_DB.DAY5_DEMO.ORDERS_SECURE
GROUP BY COUNTRY
ORDER BY row_count DESC;
-- Expected: UK, Germany, France, Netherlands, Spain

-- Test 4: GLOBAL_ANALYST should see ALL countries
USE ROLE GLOBAL_ANALYST;
SELECT COUNTRY, COUNT(*) AS row_count
FROM DAY5_TRAINING_DB.DAY5_DEMO.ORDERS_SECURE
GROUP BY COUNTRY
ORDER BY row_count DESC;
-- Expected: All 20+ countries visible

-- Test 5: SYSADMIN should see everything
USE ROLE SYSADMIN;
SELECT COUNT(*) AS total_rows
FROM DAY5_TRAINING_DB.DAY5_DEMO.ORDERS_SECURE;
-- Expected: 5,000,000

-- ============================================================
-- LAB 3F: VALIDATION QUERIES
-- ============================================================
USE ROLE SYSADMIN;

-- View all row access policies in the schema
SHOW ROW ACCESS POLICIES IN SCHEMA DAY5_TRAINING_DB.DAY5_DEMO;

-- Describe the policy to see its body
DESCRIBE ROW ACCESS POLICY COUNTRY_RLS_POLICY;

-- View policy references (which tables have this policy)
SELECT *
FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
  POLICY_NAME => 'COUNTRY_RLS_POLICY'
));

-- Detach policy (if needed)
-- ALTER TABLE ORDERS_SECURE DROP ROW ACCESS POLICY COUNTRY_RLS_POLICY;

-- Modify and reattach (common pattern)
-- Step 1: Drop existing policy from table
-- ALTER TABLE ORDERS_SECURE DROP ROW ACCESS POLICY COUNTRY_RLS_POLICY;
-- Step 2: Replace the policy definition
-- CREATE OR REPLACE ROW ACCESS POLICY ... (new definition);
-- Step 3: Re-attach
-- ALTER TABLE ORDERS_SECURE ADD ROW ACCESS POLICY ... ON (COUNTRY);

-- ============================================================
-- MONITORING: QUERY HISTORY
-- ============================================================
USE ROLE ACCOUNTADMIN;

-- Find slow queries on our training tables
SELECT
  QUERY_ID, QUERY_TEXT, USER_NAME,
  EXECUTION_TIME / 1000 AS exec_seconds,
  PARTITIONS_SCANNED, PARTITIONS_TOTAL,
  BYTES_SCANNED / POWER(1024,2) AS mb_scanned,
  ROWS_PRODUCED
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE DATABASE_NAME = 'DAY5_TRAINING_DB'
  AND EXECUTION_STATUS = 'SUCCESS'
  AND START_TIME >= DATEADD(hour, -4, CURRENT_TIMESTAMP())
ORDER BY EXECUTION_TIME DESC
LIMIT 20;

-- ============================================================
-- MONITORING: ACCESS HISTORY
-- ============================================================

-- Track which roles accessed which tables
SELECT
  a.QUERY_ID, a.USER_NAME, q.ROLE_NAME,
  a.BASE_OBJECTS_ACCESSED,
  a.POLICIES_REFERENCED,
  a.QUERY_START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY a
JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY q
  ON a.QUERY_ID = q.QUERY_ID
WHERE a.QUERY_START_TIME >= DATEADD(day, -1, CURRENT_TIMESTAMP())
  AND ARRAY_SIZE(a.POLICIES_REFERENCED) > 0
ORDER BY a.QUERY_START_TIME DESC
LIMIT 20;

-- ============================================================
-- MONITORING: TABLE STORAGE METRICS
-- ============================================================

SELECT
  TABLE_NAME,
  ACTIVE_BYTES / POWER(1024,3) AS active_gb,
  TIME_TRAVEL_BYTES / POWER(1024,3) AS time_travel_gb,
  FAILSAFE_BYTES / POWER(1024,3) AS failsafe_gb,
  RETAINED_FOR_CLONE_BYTES / POWER(1024,3) AS clone_gb
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE TABLE_CATALOG = 'DAY5_TRAINING_DB'
  AND TABLE_SCHEMA = 'DAY5_DEMO'
ORDER BY ACTIVE_BYTES DESC;

-- ============================================================
-- CLEANUP: Remove all Day 5 training objects
-- ============================================================
USE ROLE SYSADMIN;

-- Drop Row Access Policies first (must detach before dropping table)


ALTER TABLE DAY5_TRAINING_DB.DAY5_DEMO.ORDERS_SECURE 
  DROP ROW ACCESS POLICY COUNTRY_RLS_POLICY;

-- Drop the database (cascades all schemas, tables, stages, etc.)
DROP DATABASE IF EXISTS DAY5_TRAINING_DB;
	
-- Drop custom roles
USE ROLE SECURITYADMIN;
DROP ROLE IF EXISTS INDIA_ANALYST;
DROP ROLE IF EXISTS US_ANALYST;
DROP ROLE IF EXISTS EUROPE_ANALYST;
DROP ROLE IF EXISTS GLOBAL_ANALYST;
DROP ROLE IF EXISTS RLS_ADMIN;

-- Optionally drop the warehouse
-- USE ROLE SYSADMIN;
-- DROP WAREHOUSE IF EXISTS COMPUTE_WH;

