-- Assigning the role for the account 
USE ROLE ACCOUNTADMIN;
-- Assigning the warehouse to the account 
USE WAREHOUSE COMPUTE_WH;

-- Step 1: Create a Database
CREATE DATABASE SALES_DB
  DATA_RETENTION_TIME_IN_DAYS = 7
  COMMENT = 'Sales domain database';

-- Show databases
SHOW DATABASES LIKE 'SALES_DB';

-- Step 2: Create Schemas
CREATE SCHEMA SALES_DB.RAW        COMMENT = 'Raw ingested data';
CREATE SCHEMA SALES_DB.STAGING    COMMENT = 'Cleaned/transformed data';
CREATE SCHEMA SALES_DB.REPORTING  COMMENT = 'Business-ready analytics';

-- Show schemas
SHOW SCHEMAS IN DATABASE SALES_DB;

-- Step 3a: Create a Sequence (must exist before the table references it)
CREATE OR REPLACE SEQUENCE SALES_DB.RAW.customer_seq
  START = 1000 INCREMENT = 1 ORDER;

-- Step 3b: Create a Permanent Table
CREATE OR REPLACE TABLE SALES_DB.REPORTING.SALES_FACT (
  sale_id        NUMBER AUTOINCREMENT PRIMARY KEY,
  sale_date      DATE NOT NULL,
  customer_id    NUMBER DEFAULT SALES_DB.RAW.customer_seq.NEXTVAL NOT NULL,
  product_id     NUMBER NOT NULL,
  region         VARCHAR(50),
  quantity       NUMBER(10,0),
  unit_price     NUMBER(10,2),
  total_amount   NUMBER(12,2),
  created_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Describe table structure
DESC TABLE SALES_DB.REPORTING.SALES_FACT;

-- Show tables
SHOW TABLES IN SCHEMA SALES_DB.REPORTING;

-- Step 4: Create a Transient Table (for staging)
CREATE OR REPLACE TRANSIENT TABLE SALES_DB.STAGING.SALES_STAGE (
  raw_data VARIANT
);

-- Describe transient table
DESC TABLE SALES_DB.STAGING.SALES_STAGE;

-- Show tables in staging schema
SHOW TABLES IN SCHEMA SALES_DB.STAGING;

-- Step 5: Create an Internal Stage
CREATE OR REPLACE STAGE SALES_DB.RAW.my_stage
  FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
  );

-- Show stages
SHOW STAGES IN SCHEMA SALES_DB.RAW;


-- Step 6: Create a File Format
CREATE OR REPLACE FILE FORMAT SALES_DB.RAW.csv_format
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  NULL_IF = ('NULL', 'null', '')
  EMPTY_FIELD_AS_NULL = TRUE;

-- Show file formats
SHOW FILE FORMATS IN SCHEMA SALES_DB.RAW;

-- Step 7: Create a View
CREATE OR REPLACE VIEW SALES_DB.REPORTING.MONTHLY_REVENUE AS
  SELECT
    DATE_TRUNC('MONTH', sale_date) AS month,
    region,
    SUM(total_amount) AS revenue
  FROM SALES_DB.REPORTING.SALES_FACT
  GROUP BY 1, 2;

-- Show views
SHOW VIEWS IN SCHEMA SALES_DB.REPORTING;
-- Describe view
DESC VIEW SALES_DB.REPORTING.MONTHLY_REVENUE;

-- Step 8: Show Sequences
SHOW SEQUENCES IN SCHEMA SALES_DB.RAW;

-- Insert Sample Data to View Results
---------------------------------------------------
INSERT INTO SALES_DB.REPORTING.SALES_FACT
(
  sale_date,
  product_id,
  region,
  quantity,
  unit_price,
  total_amount
)
VALUES
('2026-05-01', 301, 'North', 2, 500, 1000),
('2026-05-02', 202, 'South', 1, 700, 700),
('2026-05-10', 203, 'East', 5, 200, 1000);

INSERT INTO SALES_DB.REPORTING.SALES_FACT
    (sale_date, product_id, region, quantity, unit_price, total_amount)
VALUES
    ('2025-01-15', 101, 'South', 2, 499.99, 999.98),
    ('2025-02-03', 115, 'North', 5, 1250.50, 6252.50),
    ('2025-03-18', 123, 'West', 3, 799.00, 2397.00),
    ('2025-04-22', 108, 'East', 7, 350.75, 2455.25),
    ('2025-05-10', 137, 'South', 4, 1899.99, 7599.96),
    ('2025-06-27', 142, 'Central', 6, 625.25, 3751.50),
    ('2025-07-14', 119, 'West', 1, 2499.00, 2499.00),
    ('2025-08-09', 127, 'North', 8, 275.50, 2204.00),
    ('2025-09-21', 149, 'South', 3, 999.95, 2999.85),
    ('2025-10-05', 133, 'East', 10, 450.00, 4500.00);

-- Query table data
SELECT * 
FROM SALES_DB.REPORTING.SALES_FACT;

-- Query view output
SELECT * 
FROM SALES_DB.REPORTING.MONTHLY_REVENUE;

DELETE FROM SALES_DB.REPORTING.SALES_FACT
WHERE SALE_ID = 13;
