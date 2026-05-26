-- ============================================================
-- ENVIRONMENT SETUP: Database, Schemas, Warehouse, Roles
-- Run as: ACCOUNTADMIN
-- ============================================================

USE ROLE ACCOUNTADMIN;

-- Create dedicated training database
CREATE OR REPLACE DATABASE TRAINING_SNOWFLAKE_TABLES
    COMMENT = 'Snowflake Table Types Training';

-- Create schemas for organized lab work
CREATE OR REPLACE SCHEMA TRAINING_SNOWFLAKE_TABLES.RAW_ZONE
    COMMENT = 'Raw data landing zone for staged files';

CREATE OR REPLACE SCHEMA TRAINING_SNOWFLAKE_TABLES.STAGING_ZONE
    COMMENT = 'Staging area for data transformations';

CREATE OR REPLACE SCHEMA TRAINING_SNOWFLAKE_TABLES.ANALYTICS_ZONE
    COMMENT = 'Clean data for analytics and reporting';

CREATE OR REPLACE SCHEMA TRAINING_SNOWFLAKE_TABLES.LAB_ZONE
    COMMENT = 'Sandbox for hands-on lab exercises';

-- Create training warehouse
CREATE OR REPLACE WAREHOUSE TRAINING_WH
    WAREHOUSE_SIZE = 'X-SMALL'
    AUTO_SUSPEND = 120
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Training warehouse - auto-suspends after 2 min';

-- Set context
USE WAREHOUSE TRAINING_WH;
USE DATABASE TRAINING_SNOWFLAKE_TABLES;
USE SCHEMA RAW_ZONE;

-- Validate setup
SELECT CURRENT_DATABASE(), CURRENT_SCHEMA(), CURRENT_WAREHOUSE();

-- ============================================================
-- INTERNAL STAGE & FILE FORMAT SETUP
-- ============================================================

USE SCHEMA RAW_ZONE;

-- Create CSV file format with enterprise settings
CREATE OR REPLACE FILE FORMAT FF_CSV_TRAINING
    TYPE = CSV
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    TRIM_SPACE = TRUE
    NULL_IF = ('', 'NULL', 'null', 'N/A', 'n/a')
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
    DATE_FORMAT = 'YYYY-MM-DD'
    TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS'
    COMMENT = 'Standard CSV format for training data';

-- Create internal named stage
CREATE OR REPLACE STAGE STG_TRAINING_DATA
    FILE_FORMAT = FF_CSV_TRAINING
    COMMENT = 'Internal stage for training CSV uploads';

-- Validate stage exists
SHOW STAGES IN SCHEMA RAW_ZONE;
DESCRIBE STAGE STG_TRAINING_DATA;

-- ============================================================
-- VERIFY STAGED FILES
-- ============================================================

LIST @STG_TRAINING_DATA;
-- Expected: ecommerce_orders_20k.csv, ~5 MB, status UPLOADED

-- Preview file contents before loading
SELECT $1, $2, $3, $4, $5
FROM @STG_TRAINING_DATA/ecommerce_orders.csv
(FILE_FORMAT => FF_CSV_TRAINING)
LIMIT 10;

-- ============================================================
-- CREATE PERMANENT TABLE FOR RAW DATA
-- ============================================================

CREATE OR REPLACE TABLE RAW_ZONE.ECOMMERCE_ORDERS (
    ORDER_ID            VARCHAR(20),
    CUSTOMER_ID         VARCHAR(20),
    CUSTOMER_NAME       VARCHAR(100),
    CUSTOMER_EMAIL      VARCHAR(150),
    ORDER_DATE          DATE,
    ORDER_TIMESTAMP     TIMESTAMP_NTZ,
    PRODUCT_ID          VARCHAR(20),
    PRODUCT_NAME        VARCHAR(200),
    CATEGORY            VARCHAR(50),
    SUB_CATEGORY        VARCHAR(50),
    QUANTITY            INTEGER,
    UNIT_PRICE          FLOAT,
    DISCOUNT_PCT        INTEGER,
    GROSS_AMOUNT        FLOAT,
    DISCOUNT_AMOUNT     FLOAT,
    TAX_RATE            INTEGER,
    TAX_AMOUNT          FLOAT,
    NET_AMOUNT          FLOAT,
    SHIPPING_COST       FLOAT,
    PAYMENT_METHOD      VARCHAR(30),
    ORDER_STATUS        VARCHAR(20),
    SALES_CHANNEL       VARCHAR(30),
    REGION              VARCHAR(20),
    COUNTRY             VARCHAR(30),
    WAREHOUSE_CODE      VARCHAR(20),
    CUSTOMER_TIER       VARCHAR(20),
    IS_PRIME_MEMBER     VARCHAR(5),
    DELIVERY_DATE       DATE,
    -- Metadata columns
    LOAD_TIMESTAMP      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    SOURCE_FILE         VARCHAR(200) DEFAULT 'ecommerce_orders.csv'
)
DATA_RETENTION_TIME_IN_DAYS = 30
COMMENT = 'Raw e-commerce orders - permanent table with 30-day Time Travel';

-- ============================================================
-- VALIDATION MODE: Dry-Run Before Actual Load
-- ============================================================

COPY INTO RAW_ZONE.ECOMMERCE_ORDERS
FROM @STG_TRAINING_DATA/ecommerce_orders.csv
FILE_FORMAT = (FORMAT_NAME = FF_CSV_TRAINING)
VALIDATION_MODE = 'RETURN_ERRORS';
-- If no errors returned: safe to proceed

-- ============================================================
-- ACTUAL DATA LOAD WITH ERROR HANDLING
-- ============================================================

COPY INTO RAW_ZONE.ECOMMERCE_ORDERS (
    ORDER_ID, CUSTOMER_ID, CUSTOMER_NAME, CUSTOMER_EMAIL,
    ORDER_DATE, ORDER_TIMESTAMP,
    PRODUCT_ID, PRODUCT_NAME, CATEGORY, SUB_CATEGORY,
    QUANTITY, UNIT_PRICE, DISCOUNT_PCT, GROSS_AMOUNT,
    DISCOUNT_AMOUNT, TAX_RATE, TAX_AMOUNT, NET_AMOUNT,
    SHIPPING_COST, PAYMENT_METHOD, ORDER_STATUS,
    SALES_CHANNEL, REGION, COUNTRY, WAREHOUSE_CODE,
    CUSTOMER_TIER, IS_PRIME_MEMBER, DELIVERY_DATE
)
FROM @STG_TRAINING_DATA/ecommerce_orders.csv
FILE_FORMAT = (FORMAT_NAME = FF_CSV_TRAINING)
ON_ERROR = 'CONTINUE'
PURGE = FALSE;

-- ============================================================
-- POST-LOAD VALIDATION
-- ============================================================

-- Record count
SELECT COUNT(*) AS TOTAL_RECORDS FROM RAW_ZONE.ECOMMERCE_ORDERS;
-- Expected: ~20,500 rows

-- Sample records
SELECT * FROM RAW_ZONE.ECOMMERCE_ORDERS LIMIT 10;

-- Data quality checks
SELECT
    COUNT(*) AS TOTAL_ROWS,
    COUNT(DISTINCT ORDER_ID) AS UNIQUE_ORDERS,
    COUNT(*) - COUNT(DISTINCT ORDER_ID) AS DUPLICATE_ORDER_IDS,
    COUNT(*) - COUNT(CUSTOMER_EMAIL) AS NULL_EMAILS,
    COUNT(*) - COUNT(NET_AMOUNT) AS NULL_NET_AMOUNTS,
    SUM(CASE WHEN UNIT_PRICE < 0 THEN 1 ELSE 0 END) AS NEGATIVE_PRICES,
    MIN(ORDER_DATE) AS EARLIEST_ORDER,
    MAX(ORDER_DATE) AS LATEST_ORDER
FROM RAW_ZONE.ECOMMERCE_ORDERS;

-- COPY history audit
SELECT *
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
    TABLE_NAME => 'ECOMMERCE_ORDERS',
    START_TIME => DATEADD(HOURS, -1, CURRENT_TIMESTAMP())
));


-- ============================================================
-- LAB: PERMANENT TABLE OPERATIONS
-- ============================================================
USE SCHEMA LAB_ZONE;

-- Create a permanent analytics table from raw data
CREATE OR REPLACE TABLE LAB_ZONE.ORDERS_PERMANENT AS
SELECT
    ORDER_ID,
    CUSTOMER_ID,
    CUSTOMER_NAME,
    ORDER_DATE,
    CATEGORY,
    QUANTITY,
    UNIT_PRICE,
    NET_AMOUNT,
    ORDER_STATUS,
    COUNTRY,
    CUSTOMER_TIER
FROM RAW_ZONE.ECOMMERCE_ORDERS
WHERE UNIT_PRICE > 0 AND NET_AMOUNT IS NOT NULL;

-- Verify
SELECT COUNT(*) FROM LAB_ZONE.ORDERS_PERMANENT;

-- Check table metadata
SHOW TABLES LIKE 'ORDERS_PERMANENT' IN SCHEMA LAB_ZONE;

-- Check retention & Fail-Safe settings
SELECT TABLE_NAME, TABLE_TYPE, RETENTION_TIME,
       ROW_COUNT, BYTES, AUTO_CLUSTERING_ON
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'LAB_ZONE'
  AND TABLE_NAME = 'ORDERS_PERMANENT';

-- Modify Time Travel retention
ALTER TABLE LAB_ZONE.ORDERS_PERMANENT
SET DATA_RETENTION_TIME_IN_DAYS = 14;

-- Verify change
SHOW TABLES LIKE 'ORDERS_PERMANENT' IN SCHEMA LAB_ZONE;


-- ============================================================
-- LAB: TEMPORARY TABLE OPERATIONS
-- ============================================================
USE SCHEMA LAB_ZONE;

-- Create a temporary table for session-specific analysis
CREATE OR REPLACE TEMPORARY TABLE LAB_ZONE.TEMP_HIGH_VALUE_ORDERS AS
SELECT *
FROM RAW_ZONE.ECOMMERCE_ORDERS
WHERE NET_AMOUNT > 1000
  AND ORDER_STATUS = 'Delivered';

-- Verify record count
SELECT COUNT(*) AS HIGH_VALUE_COUNT FROM TEMP_HIGH_VALUE_ORDERS;

-- Check table type in INFORMATION_SCHEMA
SELECT TABLE_NAME, TABLE_TYPE, RETENTION_TIME, IS_TRANSIENT
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'LAB_ZONE'
  AND TABLE_NAME = 'TEMP_HIGH_VALUE_ORDERS';
-- Note: TABLE_TYPE = 'LOCAL TEMPORARY'

-- Demonstrate shadowing behavior
CREATE OR REPLACE TABLE LAB_ZONE.SHADOW_DEMO (ID INT, VAL VARCHAR);
INSERT INTO LAB_ZONE.SHADOW_DEMO VALUES (1, 'PERMANENT');

CREATE OR REPLACE TEMPORARY TABLE LAB_ZONE.SHADOW_DEMO (ID INT, VAL VARCHAR);
INSERT INTO LAB_ZONE.SHADOW_DEMO VALUES (2, 'TEMPORARY');

-- Which value do you see?
SELECT * FROM LAB_ZONE.SHADOW_DEMO;
-- Result: ID=2, VAL='TEMPORARY' (temp shadows permanent)

-- Drop the temporary table
DROP TABLE LAB_ZONE.SHADOW_DEMO;

-- Now query again
SELECT * FROM LAB_ZONE.SHADOW_DEMO;
-- Result: ID=1, VAL='PERMANENT' (permanent is back)

-- Cleanup
DROP TABLE IF EXISTS LAB_ZONE.SHADOW_DEMO;

-- ============================================================
-- LAB: TRANSIENT TABLE OPERATIONS
-- ============================================================
USE SCHEMA STAGING_ZONE;

-- Create a transient staging table
CREATE OR REPLACE TRANSIENT TABLE STAGING_ZONE.STG_ORDERS_CLEAN (
    ORDER_ID            VARCHAR(20),
    CUSTOMER_ID         VARCHAR(20),
    ORDER_DATE          DATE,
    CATEGORY            VARCHAR(50),
    QUANTITY            INTEGER,
    UNIT_PRICE          FLOAT,
    NET_AMOUNT          FLOAT,
    ORDER_STATUS        VARCHAR(20),
    COUNTRY             VARCHAR(30),
    PROCESSED_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
DATA_RETENTION_TIME_IN_DAYS = 1
COMMENT = 'Transient staging - no Fail-Safe, 1-day TT only';

-- Load cleaned data into transient staging
INSERT INTO STAGING_ZONE.STG_ORDERS_CLEAN
    (ORDER_ID, CUSTOMER_ID, ORDER_DATE, CATEGORY, QUANTITY,
     UNIT_PRICE, NET_AMOUNT, ORDER_STATUS, COUNTRY)
SELECT ORDER_ID, CUSTOMER_ID, ORDER_DATE, CATEGORY, QUANTITY,
       UNIT_PRICE, NET_AMOUNT, ORDER_STATUS, COUNTRY
FROM RAW_ZONE.ECOMMERCE_ORDERS
WHERE UNIT_PRICE > 0 AND NET_AMOUNT IS NOT NULL;

-- Verify
SELECT COUNT(*) FROM STAGING_ZONE.STG_ORDERS_CLEAN;

-- Check table type
SELECT TABLE_NAME, TABLE_TYPE, IS_TRANSIENT, RETENTION_TIME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'STAGING_ZONE'
  AND TABLE_NAME = 'STG_ORDERS_CLEAN';
-- Note: IS_TRANSIENT = 'YES'


-- ============================================================
-- LAB: ZERO-COPY CLONING
-- ============================================================
USE SCHEMA LAB_ZONE;

-- Clone the permanent orders table
CREATE OR REPLACE TABLE LAB_ZONE.ORDERS_CLONE
    CLONE LAB_ZONE.ORDERS_PERMANENT;

-- Verify same row count (instant, no data copied)
SELECT 'SOURCE' AS TABLE_LABEL, COUNT(*) AS ROW_COUNT
FROM LAB_ZONE.ORDERS_PERMANENT
UNION ALL
SELECT 'CLONE', COUNT(*)
FROM LAB_ZONE.ORDERS_CLONE;

-- Modify the clone (this creates new micro-partitions)
DELETE FROM LAB_ZONE.ORDERS_CLONE WHERE ORDER_STATUS = 'Cancelled';

-- Verify divergence
SELECT 'SOURCE' AS TABLE_LABEL, COUNT(*) AS ROW_COUNT
FROM LAB_ZONE.ORDERS_PERMANENT
UNION ALL
SELECT 'CLONE', COUNT(*)
FROM LAB_ZONE.ORDERS_CLONE;

-- Clone with Time Travel (clone table as it was 5 minutes ago)
CREATE OR REPLACE TABLE LAB_ZONE.ORDERS_CLONE_HISTORICAL
    CLONE LAB_ZONE.ORDERS_PERMANENT AT(OFFSET => -300);

-- Clone at database level (clones everything)
-- CREATE DATABASE TRAINING_CLONE CLONE TRAINING_SNOWFLAKE_TABLES;
-- (Commented: use only if you want to demo full DB clone)

-- ============================================================
-- LAB: EXTERNAL TABLE (Conceptual - Requires Cloud Storage)
-- ============================================================

-- Step 1: Create storage integration (ACCOUNTADMIN)
-- CREATE OR REPLACE STORAGE INTEGRATION S3_TRAINING_INT
--     TYPE = EXTERNAL_STAGE
--     STORAGE_PROVIDER = 'S3'
--     ENABLED = TRUE
--     STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::role/snowflake-access'
--     STORAGE_ALLOWED_LOCATIONS = ('s3://your-bucket/training/');

-- Step 2: Create external stage
-- CREATE OR REPLACE STAGE STG_EXTERNAL_DATA
--     STORAGE_INTEGRATION = S3_TRAINING_INT
--     URL = 's3://your-bucket/training/'
--     FILE_FORMAT = FF_CSV_TRAINING;

-- Step 3: Create external table with partitioning
-- CREATE OR REPLACE EXTERNAL TABLE RAW_ZONE.EXT_ORDERS (
--     ORDER_ID VARCHAR AS (VALUE:c1::VARCHAR),
--     ORDER_DATE DATE AS (VALUE:c5::DATE),
--     CATEGORY VARCHAR AS (VALUE:c9::VARCHAR),
--     NET_AMOUNT FLOAT AS (VALUE:c18::FLOAT),
--     -- Partition column derived from file path
--     YEAR_PARTITION VARCHAR AS
--       (SPLIT_PART(METADATA$FILENAME, '/', 2))
-- )
-- PARTITION BY (YEAR_PARTITION)
-- LOCATION = @STG_EXTERNAL_DATA
-- AUTO_REFRESH = TRUE
-- FILE_FORMAT = (TYPE = CSV);

-- Step 4: Refresh and query
-- ALTER EXTERNAL TABLE RAW_ZONE.EXT_ORDERS REFRESH;
-- SELECT * FROM RAW_ZONE.EXT_ORDERS LIMIT 100;

-- ============================================================
-- LAB: DYNAMIC TABLES - Declarative Pipeline
-- ============================================================
USE SCHEMA STAGING_ZONE;

-- Step 1: Create a dynamic table that cleans raw data
CREATE OR REPLACE DYNAMIC TABLE STAGING_ZONE.DT_ORDERS_CLEAN
    TARGET_LAG = '5 minutes'
    WAREHOUSE = TRAINING_WH
AS
SELECT
    ORDER_ID,
    CUSTOMER_ID,
    CUSTOMER_NAME,
    ORDER_DATE,
    CATEGORY,
    SUB_CATEGORY,
    QUANTITY,
    ABS(UNIT_PRICE) AS UNIT_PRICE,  -- Fix negative prices
    COALESCE(NET_AMOUNT, ABS(UNIT_PRICE) * QUANTITY) AS NET_AMOUNT,
    ORDER_STATUS,
    COUNTRY,
    CUSTOMER_TIER
FROM RAW_ZONE.ECOMMERCE_ORDERS
WHERE UNIT_PRICE IS NOT NULL;

-- Step 2: Create a downstream dynamic table for daily summary
USE SCHEMA ANALYTICS_ZONE;

CREATE OR REPLACE DYNAMIC TABLE ANALYTICS_ZONE.DT_DAILY_REVENUE
    TARGET_LAG = '1 hour'
    WAREHOUSE = TRAINING_WH
AS
SELECT
    ORDER_DATE,
    CATEGORY,
    COUNTRY,
    COUNT(*) AS ORDER_COUNT,
    SUM(NET_AMOUNT) AS TOTAL_REVENUE,
    AVG(NET_AMOUNT) AS AVG_ORDER_VALUE,
    SUM(QUANTITY) AS TOTAL_UNITS_SOLD
FROM STAGING_ZONE.DT_ORDERS_CLEAN
GROUP BY ORDER_DATE, CATEGORY, COUNTRY;

-- Step 3: Monitor dynamic table status
SELECT NAME, STATE, STATE_MESSAGE,
       DATA_TIMESTAMP, TARGET_LAG_SEC
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
    NAME_PREFIX => 'TRAINING_SNOWFLAKE_TABLES.STAGING_ZONE.DT_'));

-- Step 4: Query the dynamic table
SELECT * FROM ANALYTICS_ZONE.DT_DAILY_REVENUE
ORDER BY TOTAL_REVENUE DESC LIMIT 20;

-- Step 5: Manually refresh (optional)
ALTER DYNAMIC TABLE STAGING_ZONE.DT_ORDERS_CLEAN REFRESH;

-- ============================================================
-- LAB: HYBRID TABLE (Conceptual)
-- ============================================================

-- Create a hybrid table for customer master data
-- CREATE OR REPLACE HYBRID TABLE LAB_ZONE.CUSTOMERS_HYBRID (
--     CUSTOMER_ID VARCHAR(20) PRIMARY KEY,
--     CUSTOMER_NAME VARCHAR(100) NOT NULL,
--     CUSTOMER_EMAIL VARCHAR(150),
--     CUSTOMER_TIER VARCHAR(20) DEFAULT 'Bronze',
--     IS_ACTIVE BOOLEAN DEFAULT TRUE,
--     CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
--     UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
-- );

-- Fast point lookup (uses row-oriented index)
-- SELECT * FROM LAB_ZONE.CUSTOMERS_HYBRID
-- WHERE CUSTOMER_ID = 'CUST-000001';

-- Analytical query (uses columnar storage)
-- SELECT CUSTOMER_TIER, COUNT(*) AS CUSTOMER_COUNT
-- FROM LAB_ZONE.CUSTOMERS_HYBRID
-- GROUP BY CUSTOMER_TIER;

-- ============================================================
-- LAB: ICEBERG TABLE (Conceptual - Requires External Volume)
-- ============================================================

-- Step 1: Create external volume (ACCOUNTADMIN)
-- CREATE OR REPLACE EXTERNAL VOLUME ICEBERG_VOL
--     STORAGE_LOCATIONS = (
--         (
--             NAME = 'iceberg-s3'
--             STORAGE_BASE_URL = 's3://your-bucket/iceberg/'
--             STORAGE_PROVIDER = 'S3'
--             STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::role/sf-iceberg'
--         )
--     );

-- Step 2: Create Iceberg table
-- CREATE OR REPLACE ICEBERG TABLE LAB_ZONE.ORDERS_ICEBERG (
--     ORDER_ID VARCHAR,
--     ORDER_DATE DATE,
--     CATEGORY VARCHAR,
--     NET_AMOUNT FLOAT
-- )
-- CATALOG = 'SNOWFLAKE'
-- EXTERNAL_VOLUME = 'ICEBERG_VOL'
-- BASE_LOCATION = 'orders/';

-- Step 3: Insert data
-- INSERT INTO LAB_ZONE.ORDERS_ICEBERG
-- SELECT ORDER_ID, ORDER_DATE, CATEGORY, NET_AMOUNT
-- FROM RAW_ZONE.ECOMMERCE_ORDERS LIMIT 1000;

-- ============================================================
-- LAB: EVENT TABLE
-- ============================================================
USE SCHEMA LAB_ZONE;

-- Create an event table
CREATE OR REPLACE EVENT TABLE LAB_ZONE.APP_EVENTS
    DATA_RETENTION_TIME_IN_DAYS = 1
    COMMENT = 'Event table for application telemetry';

-- Set account-level event table (requires ACCOUNTADMIN)
-- ALTER ACCOUNT SET EVENT_TABLE = 'TRAINING_SNOWFLAKE_TABLES.LAB_ZONE.APP_EVENTS';

-- View event table structure
DESCRIBE TABLE LAB_ZONE.APP_EVENTS;

-- Query events (after enabling logging in UDFs/procedures)
-- SELECT TIMESTAMP, RESOURCE_ATTRIBUTES, RECORD_ATTRIBUTES
-- FROM LAB_ZONE.APP_EVENTS
-- ORDER BY TIMESTAMP DESC LIMIT 50;

-- ============================================================
-- LAB: TIME TRAVEL RECOVERY
-- ============================================================
USE SCHEMA LAB_ZONE;

-- Record the current count
SELECT COUNT(*) FROM LAB_ZONE.ORDERS_PERMANENT;
-- Store this number mentally as the 'BEFORE count'

-- Get the current query ID and timestamp
SELECT CURRENT_TIMESTAMP() AS BEFORE_DELETE_TS;

-- Simulate accidental DELETE
DELETE FROM LAB_ZONE.ORDERS_PERMANENT WHERE COUNTRY = 'India';

-- Verify the damage
SELECT COUNT(*) FROM LAB_ZONE.ORDERS_PERMANENT;
-- Records from India are gone!

-- RECOVERY METHOD 1: Using OFFSET (seconds ago)
SELECT COUNT(*)
FROM LAB_ZONE.ORDERS_PERMANENT AT(OFFSET => -120);
-- Shows count as it was 120 seconds ago

-- RECOVERY METHOD 2: Using TIMESTAMP
-- Replace with actual timestamp from BEFORE_DELETE_TS
-- SELECT COUNT(*)
-- FROM LAB_ZONE.ORDERS_PERMANENT AT(
--     TIMESTAMP => 'YYYY-MM-DD HH:MI:SS'::TIMESTAMP_NTZ);

-- RECOVERY METHOD 3: Restore using clone
CREATE OR REPLACE TABLE LAB_ZONE.ORDERS_PERMANENT_RESTORED
    CLONE LAB_ZONE.ORDERS_PERMANENT AT(OFFSET => -120);

-- Verify recovery
SELECT 'CURRENT' AS TABLE_STATE, COUNT(*) AS ROW_COUNT
FROM LAB_ZONE.ORDERS_PERMANENT
UNION ALL
SELECT 'RESTORED', COUNT(*)
FROM LAB_ZONE.ORDERS_PERMANENT_RESTORED;

-- Swap to restore (rename pattern)
ALTER TABLE LAB_ZONE.ORDERS_PERMANENT RENAME TO ORDERS_PERMANENT_BAD;
ALTER TABLE LAB_ZONE.ORDERS_PERMANENT_RESTORED RENAME TO ORDERS_PERMANENT;

-- UNDROP demonstration
DROP TABLE LAB_ZONE.ORDERS_PERMANENT_BAD;
UNDROP TABLE LAB_ZONE.ORDERS_PERMANENT_BAD;
-- Table is back from the dead!

-- Cleanup
DROP TABLE IF EXISTS LAB_ZONE.ORDERS_PERMANENT_BAD;

-- ============================================================
-- LAB: STREAMS AND TASKS
-- ============================================================
USE SCHEMA LAB_ZONE;

-- Create a stream on the permanent orders table
CREATE OR REPLACE STREAM LAB_ZONE.STM_ORDERS_CDC
    ON TABLE LAB_ZONE.ORDERS_PERMANENT
    SHOW_INITIAL_ROWS = FALSE
    COMMENT = 'CDC stream tracking order changes';

-- Check stream metadata
SHOW STREAMS IN SCHEMA LAB_ZONE;

-- Insert new data to generate change records
INSERT INTO LAB_ZONE.ORDERS_PERMANENT
    (ORDER_ID, CUSTOMER_ID, CUSTOMER_NAME, ORDER_DATE,
     CATEGORY, QUANTITY, UNIT_PRICE, NET_AMOUNT,
     ORDER_STATUS, COUNTRY, CUSTOMER_TIER)
VALUES
    ('ORD-9990001','CUST-000001','Test User','2025-06-01',
     'Electronics',2,999.99,1999.98,'Processing','USA','Gold');

-- Query the stream for changes
SELECT * FROM LAB_ZONE.STM_ORDERS_CDC;
-- Shows METADATA$ACTION = 'INSERT', METADATA$ISUPDATE = FALSE

-- Create a task that consumes the stream
CREATE OR REPLACE TASK LAB_ZONE.TSK_PROCESS_ORDERS
    WAREHOUSE = TRAINING_WH
    SCHEDULE = '5 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('LAB_ZONE.STM_ORDERS_CDC')
AS
INSERT INTO ANALYTICS_ZONE.DT_DAILY_REVENUE
    (ORDER_DATE, CATEGORY, COUNTRY, ORDER_COUNT,
     TOTAL_REVENUE, AVG_ORDER_VALUE, TOTAL_UNITS_SOLD)
SELECT ORDER_DATE, CATEGORY, COUNTRY, COUNT(*),
       SUM(NET_AMOUNT), AVG(NET_AMOUNT), SUM(QUANTITY)
FROM LAB_ZONE.STM_ORDERS_CDC
WHERE METADATA$ACTION = 'INSERT'
GROUP BY ORDER_DATE, CATEGORY, COUNTRY;

-- Note: Do NOT resume this task in training to avoid cost
-- ALTER TASK LAB_ZONE.TSK_PROCESS_ORDERS RESUME;

-- Check task status
SHOW TASKS IN SCHEMA LAB_ZONE;

-- ============================================================
-- LAB: CLUSTERING KEYS
-- ============================================================

-- Add clustering key on frequently filtered columns
ALTER TABLE LAB_ZONE.ORDERS_PERMANENT
    CLUSTER BY (ORDER_DATE, CATEGORY);

-- Check clustering status
SELECT SYSTEM$CLUSTERING_INFORMATION(
    'LAB_ZONE.ORDERS_PERMANENT',
    '(ORDER_DATE, CATEGORY)'
);

-- Check clustering depth
SELECT SYSTEM$CLUSTERING_DEPTH(
    'LAB_ZONE.ORDERS_PERMANENT',
    '(ORDER_DATE, CATEGORY)'
);
-- Lower values = better clustering

-- Enable search optimization (Enterprise Edition required)
ALTER TABLE LAB_ZONE.ORDERS_PERMANENT
    ADD SEARCH OPTIMIZATION ON EQUALITY(CUSTOMER_ID, ORDER_ID);

-- Verify
SHOW TABLES LIKE 'ORDERS_PERMANENT' IN SCHEMA LAB_ZONE;
-- Check SEARCH_OPTIMIZATION = ON

-- ============================================================
-- MONITORING & METADATA QUERIES
-- ============================================================

-- All tables with types and retention settings
SELECT TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME,
       TABLE_TYPE, IS_TRANSIENT, RETENTION_TIME,
       ROW_COUNT, BYTES
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'TRAINING_SNOWFLAKE_TABLES'
ORDER BY TABLE_SCHEMA, TABLE_NAME;

-- Storage breakdown by table type
SELECT TABLE_TYPE, IS_TRANSIENT,
       COUNT(*) AS TABLE_COUNT,
       SUM(BYTES) / (1024*1024) AS TOTAL_SIZE_MB,
       SUM(ROW_COUNT) AS TOTAL_ROWS
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'TRAINING_SNOWFLAKE_TABLES'
GROUP BY TABLE_TYPE, IS_TRANSIENT;

-- ACCOUNT_USAGE: Storage costs including Time Travel & Fail-Safe
-- (Requires ACCOUNTADMIN or USAGE_VIEWER role)
SELECT TABLE_NAME, TABLE_SCHEMA,
       ACTIVE_BYTES / (1024*1024*1024) AS ACTIVE_GB,
       TIME_TRAVEL_BYTES / (1024*1024*1024) AS TT_GB,
       FAILSAFE_BYTES / (1024*1024*1024) AS FS_GB,
       (ACTIVE_BYTES + TIME_TRAVEL_BYTES + FAILSAFE_BYTES)
           / (1024*1024*1024) AS TOTAL_GB
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE TABLE_CATALOG = 'TRAINING_SNOWFLAKE_TABLES'
  AND ACTIVE_BYTES > 0
ORDER BY TOTAL_GB DESC;

-- Warehouse credit usage
SELECT WAREHOUSE_NAME, SUM(CREDITS_USED) AS TOTAL_CREDITS
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME >= DATEADD(DAY, -7, CURRENT_TIMESTAMP())
GROUP BY WAREHOUSE_NAME
ORDER BY TOTAL_CREDITS DESC;



