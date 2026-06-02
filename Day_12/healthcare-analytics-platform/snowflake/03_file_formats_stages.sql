-- =====================================================================
-- 03_file_formats_stages.sql  |  Run as ACCOUNTADMIN (or SYSADMIN)
-- Defines how CSVs are parsed and creates the external stage on S3.
-- =====================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE HC_DB;
USE SCHEMA   RAW;

-- File format: header row, comma-delimited, treat '' as NULL
CREATE FILE FORMAT IF NOT EXISTS HC_DB.RAW.HC_CSV
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL')
  EMPTY_FIELD_AS_NULL = TRUE
  TRIM_SPACE = TRUE
  ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE;

-- External stage pointing at the S3 folder via the integration
CREATE STAGE IF NOT EXISTS HC_DB.RAW.HC_S3_STAGE
  STORAGE_INTEGRATION = HC_S3_INT
  URL = 's3://<YOUR_BUCKET>/healthcare/'
  FILE_FORMAT = HC_DB.RAW.HC_CSV;

-- Verify Snowflake can see the files in the bucket
LIST @HC_DB.RAW.HC_S3_STAGE;
