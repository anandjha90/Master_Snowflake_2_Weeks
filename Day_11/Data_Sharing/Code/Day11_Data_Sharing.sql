USE ROLE ACCOUNTADMIN;

CREATE WAREHOUSE IF NOT EXISTS WH_TRAIN WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
USE WAREHOUSE WH_TRAIN;
 
CREATE DATABASE IF NOT EXISTS SALES_DB;
USE DATABASE SALES_DB;
CREATE SCHEMA  IF NOT EXISTS SALES_DB.RAW;
USE SCHEMA SALES_DB.RAW;
 
CREATE OR REPLACE TABLE retail_txn (
  txn_id        NUMBER,
  cust_id       STRING,
  txn_date      DATE,
  region        STRING,
  category      STRING,
  channel       STRING,
  qty           NUMBER,
  unit_price    NUMBER(10,2),
  total_amount  NUMBER(12,2)
);

select * from retail_txn;

CREATE SCHEMA IF NOT EXISTS SALES_DB.SHARED;
 
CREATE OR REPLACE SECURE VIEW SALES_DB.SHARED.v_sales_summary AS
SELECT txn_id, txn_date, region, category, channel,
       qty, unit_price, total_amount
FROM   SALES_DB.RAW.retail_txn;   -- cust_id deliberately excluded

CREATE SHARE IF NOT EXISTS SALES_SHARE
  COMMENT = 'Internal: governed retail sales summary';
 
GRANT USAGE  ON DATABASE SALES_DB              TO SHARE SALES_SHARE;
GRANT USAGE  ON SCHEMA   SALES_DB.SHARED        TO SHARE SALES_SHARE;
GRANT SELECT ON VIEW     SALES_DB.SHARED.v_sales_summary TO SHARE SALES_SHARE;

-- Replace with the consumer account locator in the SAME region & cloud
-- You cannot share data with yourself. A share requires a different Snowflake account as the consumer. If you're learning/practicing and don't have a second account, you can:

-- Create a free Snowflake trial account to act as the consumer
-- Comment out the ALTER SHARE line and proceed with the rest of the exercise

-- ALTER SHARE SALES_SHARE ADD ACCOUNTS = CONSUMER_ACCT_LOCATOR;
 
SHOW GRANTS TO SHARE SALES_SHARE;   -- verify objects on the share
SHOW GRANTS OF SHARE SALES_SHARE;   -- verify the added account (since if have not added consumer account then it will not show any results, ignore if not added)


SHOW SHARES;

-- ============================================================
-- CONSUMER-SIDE COMMANDS (run these on the CONSUMER account, not here)
-- Replace PROVIDER_ACCT with your provider's org-qualified name,
-- e.g., ZDCSWHF.PJB23157
-- ============================================================
-- CREATE DATABASE SHARED_SALES FROM SHARE ZDCSWHF.PJB23157.SALES_SHARE;
-- GRANT IMPORTED PRIVILEGES ON DATABASE SHARED_SALES TO ROLE SYSADMIN;
--
-- USE WAREHOUSE WH_TRAIN;
-- SELECT region, SUM(total_amount) AS revenue
-- FROM   SHARED_SALES.SHARED.v_sales_summary
-- GROUP  BY region ORDER BY revenue DESC;

-- Provider: how many rows are exposed?
SELECT COUNT(*) FROM SALES_DB.SHARED.v_sales_summary;            -- 50000
-- Consumer-side test (run on CONSUMER account): prove it is read-only (should FAIL):
-- INSERT INTO SHARED_SALES.SHARED.v_sales_summary VALUES (DEFAULT);  -- error: read-only



-- ==============================================================
--                          LAB 2
-- ==============================================================

USE ROLE ACCOUNTADMIN;

CREATE MANAGED ACCOUNT partner_reader
  ADMIN_NAME = 'reader_admin'
  ADMIN_PASSWORD = 'StrongP@ssw0rd!2025'
  TYPE = READER
  COMMENT = 'Reader account for non-Snowflake partner';
 
SHOW MANAGED ACCOUNTS;   -- note the locator + login URL for the reader

CREATE SHARE IF NOT EXISTS PARTNER_SHARE;
GRANT USAGE  ON DATABASE SALES_DB               TO SHARE PARTNER_SHARE;
GRANT USAGE  ON SCHEMA   SALES_DB.SHARED         TO SHARE PARTNER_SHARE;
GRANT SELECT ON VIEW     SALES_DB.SHARED.v_sales_summary TO SHARE PARTNER_SHARE;
 
-- Use the reader account locator from SHOW MANAGED ACCOUNTS:
ALTER SHARE PARTNER_SHARE ADD ACCOUNTS = <reader_locator>;

USE ROLE ACCOUNTADMIN;   -- inside the reader account
CREATE WAREHOUSE reader_wh WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60;
GRANT USAGE ON WAREHOUSE reader_wh TO ROLE PUBLIC;
 
CREATE DATABASE PARTNER_DB FROM SHARE PROVIDER_ACCT.PARTNER_SHARE;
GRANT IMPORTED PRIVILEGES ON DATABASE PARTNER_DB TO ROLE PUBLIC;

USE WAREHOUSE reader_wh;
SELECT category, COUNT(*) AS txns, ROUND(SUM(total_amount),2) AS revenue
FROM   PARTNER_DB.SHARED.v_sales_summary
GROUP  BY category ORDER BY revenue DESC;

CREATE ROLE IF NOT EXISTS PARTNER_EU;   -- pretend external partner
GRANT ROLE PARTNER_EU TO ROLE SYSADMIN;
 
CREATE OR REPLACE SECURE VIEW SALES_DB.SHARED.v_partner_scoped AS
SELECT * FROM SALES_DB.SHARED.v_sales_summary
WHERE region = IFF(CURRENT_ROLE()='PARTNER_EU','EUW', region);
 
GRANT USAGE ON DATABASE SALES_DB TO ROLE PARTNER_EU;
GRANT USAGE ON SCHEMA SALES_DB.SHARED TO ROLE PARTNER_EU;
GRANT SELECT ON VIEW SALES_DB.SHARED.v_partner_scoped TO ROLE PARTNER_EU;
 
USE ROLE PARTNER_EU;
SELECT DISTINCT region FROM SALES_DB.SHARED.v_partner_scoped;  -- only EUW

-------------------------------------- LAB 3 --------------------------------------------------

USE WAREHOUSE WH_TRAIN;
-- Object names depend on the chosen listing; use its data dictionary.
SELECT * FROM WEATHER_DATA.PUBLIC.<table_name> LIMIT 100;

-- Enrichment pattern: join Marketplace data to your own sales
SELECT s.region, COUNT(*) AS txns
FROM   SALES_DB.SHARED.v_sales_summary s
GROUP  BY s.region;   -- then join to a demographic/weather listing by geography

---------------------------------------- LAB 4 ------------------------------------------------

USE ROLE ACCOUNTADMIN; USE SCHEMA SALES_DB.RAW;
CREATE TAG IF NOT EXISTS governance_tag ALLOWED_VALUES 'PII','INTERNAL','PUBLIC';
 
-- classify cust_id as sensitive, the rest as internal
ALTER TABLE retail_txn MODIFY COLUMN cust_id SET TAG governance_tag = 'PII';
ALTER TABLE retail_txn SET TAG governance_tag = 'INTERNAL';
 
-- automated classification suggestion (profiles columns)
SELECT SYSTEM$CLASSIFY('SALES_DB.RAW.retail_txn', {'auto_tag': false});


