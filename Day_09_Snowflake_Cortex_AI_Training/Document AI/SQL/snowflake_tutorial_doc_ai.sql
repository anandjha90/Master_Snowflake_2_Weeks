-- ============================================================

-- Document AI Setup Script (Updated for AI_EXTRACT)

-- The !PREDICT method was decommissioned March 16, 2026.

-- This script uses the replacement AI_EXTRACT function.

-- ============================================================
 
-- Create a database and schema in which to work:

CREATE DATABASE IF NOT EXISTS doc_ai_db;

CREATE SCHEMA IF NOT EXISTS doc_ai_db.doc_ai_schema;
 
-- Create custom role doc_ai_role:

USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS doc_ai_role;
 
-- Grant the required Snowflake database roles:

GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE doc_ai_role;

GRANT DATABASE ROLE SNOWFLAKE.ML_USER TO ROLE doc_ai_role;
 
-- Grant warehouse usage and operating privileges:

GRANT USAGE, OPERATE ON WAREHOUSE CORTEX_WH TO ROLE doc_ai_role;
 
-- Grant the privileges to use the database and schema:

GRANT USAGE ON DATABASE doc_ai_db TO ROLE doc_ai_role;

GRANT USAGE ON SCHEMA doc_ai_db.doc_ai_schema TO ROLE doc_ai_role;
 
-- Grant the create stage privilege:

GRANT CREATE STAGE ON SCHEMA doc_ai_db.doc_ai_schema TO ROLE doc_ai_role;
 
-- Grant privileges for pipeline objects:

GRANT CREATE STREAM, CREATE TABLE, CREATE TASK, CREATE VIEW ON SCHEMA doc_ai_db.doc_ai_schema TO ROLE doc_ai_role;

GRANT EXECUTE TASK ON ACCOUNT TO ROLE doc_ai_role;
 
-- Grant the doc_ai_role to your user:

GRANT ROLE doc_ai_role TO USER RAKESHB;
 
-- Switch to the doc_ai_role:

USE ROLE doc_ai_role;

USE DATABASE doc_ai_db;

USE SCHEMA doc_ai_schema;

USE WAREHOUSE CORTEX_WH;
 
-- ============================================================

-- Stage & Stream

-- ============================================================
 
-- Create an internal stage to store the PDF documents:

CREATE OR REPLACE STAGE my_pdf_stage

  DIRECTORY = (ENABLE = TRUE)

  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');
 
-- Create a stream on the stage to detect new files:

CREATE OR REPLACE STREAM my_pdf_stream ON STAGE my_pdf_stage;
 
-- Refresh the directory metadata (run after uploading files):

ALTER STAGE my_pdf_stage REFRESH;
 
-- Check uploaded files:

LIST @my_pdf_stage;
 
-- ============================================================

-- Table to store extracted data

-- ============================================================
 
CREATE OR REPLACE TABLE pdf_reviews (

  file_name VARCHAR,

  file_size VARIANT,

  last_modified VARCHAR,

  snowflake_file_url VARCHAR,

  json_content VARIANT

);
 
-- ============================================================

-- Task: auto-process new files using AI_EXTRACT

-- ============================================================
 
CREATE OR REPLACE TASK load_new_file_data

  WAREHOUSE = CORTEX_WH

  SCHEDULE = '1 MINUTE'

  COMMENT = 'Process new PDF files and extract data using AI_EXTRACT.'

WHEN SYSTEM$STREAM_HAS_DATA('my_pdf_stream')

AS

INSERT INTO pdf_reviews

  SELECT

    RELATIVE_PATH AS file_name,

    SIZE AS file_size,

    LAST_MODIFIED,

    FILE_URL AS snowflake_file_url,

    AI_EXTRACT(

      TO_FILE('@my_pdf_stage', RELATIVE_PATH),

      OBJECT_CONSTRUCT(

        'inspection_date', 'the date of the inspection',

        'inspection_grade', 'the overall inspection grade or result',

        'inspector', 'the name of the inspector',

        'list_of_units', 'list of all units or components that were inspected'

      )

    ) AS json_content

  FROM my_pdf_stream

  WHERE METADATA$ACTION = 'INSERT';
 
-- Start the task:

ALTER TASK load_new_file_data RESUME;
 
-- Check tasks:

SHOW TASKS;
 
-- ============================================================

-- View extracted data

-- ============================================================
 
SELECT * FROM pdf_reviews;
 
-- ============================================================

-- Parsed table with extracted fields in separate columns

-- ============================================================
 
CREATE OR REPLACE TABLE doc_ai_db.doc_ai_schema.pdf_reviews_2 AS

WITH temp AS (

  SELECT

    RELATIVE_PATH AS file_name,

    SIZE AS file_size,

    LAST_MODIFIED,

    FILE_URL AS snowflake_file_url,

    AI_EXTRACT(

      TO_FILE('@my_pdf_stage', RELATIVE_PATH),

      OBJECT_CONSTRUCT(

        'inspection_date', 'the date of the inspection',

        'inspection_grade', 'the overall inspection grade or result',

        'inspector', 'the name of the inspector',

        'list_of_units', 'list of all units or components that were inspected'

      )

    ) AS json_content

  FROM DIRECTORY(@my_pdf_stage)

)

SELECT

  file_name,

  file_size,

  last_modified,

  snowflake_file_url,

  json_content:response:inspection_date::STRING AS inspection_date,

  json_content:response:inspection_grade::STRING AS inspection_grade,

  json_content:response:inspector::STRING AS inspector,

  ARRAY_TO_STRING(json_content:response:list_of_units, ', ') AS list_of_units

FROM temp;
 
SELECT * FROM pdf_reviews_2;

 
