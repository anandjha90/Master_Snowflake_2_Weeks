-- ================================================================
-- STEP 1: SETUP ROLE AND DATABASE CONTEXT
-- ================================================================
USE ROLE ACCOUNTADMIN;
CREATE DATABASE IF NOT EXISTS GITHUB_DB;
USE DATABASE GITHUB_DB;
CREATE SCHEMA IF NOT EXISTS GITHUB;
USE SCHEMA GITHUB;

-- ================================================================
-- STEP 2: CREATE SECRET (replace with your actual credentials)
-- ================================================================
CREATE OR REPLACE SECRET GITHUB_DB.GITHUB.GIT_SECRET
  TYPE     = PASSWORD
  USERNAME = '<YOUR_USERNAME'
  PASSWORD = '<YOUR_GITHUB_PAT>';


-- ================================================================
-- STEP 3: CREATE API INTEGRATION
-- ================================================================
CREATE OR REPLACE API INTEGRATION GIT_INT
  API_PROVIDER                  = GIT_HTTPS_API
  API_ALLOWED_PREFIXES          = ('https://github.com/anandjha90/')
  ENABLED                       = TRUE
  ALLOWED_AUTHENTICATION_SECRETS = (GITHUB_DB.GITHUB.GIT_SECRET);

-- ================================================================
-- STEP 4: CREATE GIT REPOSITORY OBJECT
-- ================================================================
CREATE OR REPLACE GIT REPOSITORY GITHUB_DB.GITHUB.SNOWFLAKE_AWA
  API_INTEGRATION = GIT_INT
  GIT_CREDENTIALS = GITHUB_DB.GITHUB.GIT_SECRET
  ORIGIN          = 'https://github.com/anandjha90/ANALYTICSWITHANAND.git';

-- ================================================================
-- STEP 5: FETCH LATEST FROM GITHUB
-- ================================================================
ALTER GIT REPOSITORY GITHUB_DB.GITHUB.SNOWFLAKE_AWA FETCH;

-- ================================================================
-- STEP 6: VERIFY BRANCHES AND FILES
-- ================================================================
SHOW GIT BRANCHES IN GIT REPOSITORY GITHUB_DB.GITHUB.SNOWFLAKE_AWA;
SHOW GIT TAGS    IN GIT REPOSITORY GITHUB_DB.GITHUB.SNOWFLAKE_AWA;

-- ================================================================
-- STEP 7: SET BRANCH VARIABLES
-- Change GIT_BRANCH value to switch between branches anytime
-- ================================================================
SET GIT_REPO   = '@GITHUB_DB.GITHUB.SNOWFLAKE_AWA';

-- ---- SNOWFLAKE BRANCH ----
SET GIT_BRANCH = 'SNOWFLAKE';
SET GIT_BASE   = $GIT_REPO || '/branches/' || $GIT_BRANCH;

-- ---- PYTHON BRANCH ---- (uncomment to switch)
-- SET GIT_BRANCH = 'PYTHON';
-- SET GIT_BASE   = $GIT_REPO || '/branches/' || $GIT_BRANCH;

-- ---- MAIN BRANCH ---- (uncomment to switch)
-- SET GIT_BRANCH = 'main';
-- SET GIT_BASE   = $GIT_REPO || '/branches/' || $GIT_BRANCH;

-- ================================================================
-- STEP 8: LIST FILES IN CURRENT BRANCH
-- ================================================================

-- List everything in current branch
LIST '@GITHUB_DB.GITHUB.SNOWFLAKE_AWA/branches/SNOWFLAKE/';

-- List only SQL files
LIST '@GITHUB_DB.GITHUB.SNOWFLAKE_AWA/branches/SNOWFLAKE/' PATTERN='.*\.sql';

-- List only Python files
LIST '@GITHUB_DB.GITHUB.SNOWFLAKE_AWA/branches/SNOWFLAKE/' PATTERN='.*\.py';

-- List specific folders
LIST '@GITHUB_DB.GITHUB.SNOWFLAKE_AWA/branches/SNOWFLAKE/DANNY_CASE_STUDIES/';
LIST '@GITHUB_DB.GITHUB.SNOWFLAKE_AWA/branches/SNOWFLAKE/MISCELLANEOUS/';
LIST '@GITHUB_DB.GITHUB.SNOWFLAKE_AWA/branches/SNOWFLAKE/LECTURE 14 : REGEX - PART4/';

-- ================================================================
-- STEP 9: EXECUTE SQL FILES FROM SNOWFLAKE BRANCH
-- ================================================================

-- Danny case studies
EXECUTE IMMEDIATE FROM '@GITHUB_DB.GITHUB.SNOWFLAKE_AWA/branches/SNOWFLAKE/DANNY_CASE_STUDIES/case_study_1_danny_diners.sql';
EXECUTE IMMEDIATE FROM '@GITHUB_DB.GITHUB.SNOWFLAKE_AWA/branches/SNOWFLAKE/DANNY_CASE_STUDIES/case_study_2_pizza_runner.sql';

-- Miscellaneous (dates.sql has a syntax error on line 88: invalid expression "YEAR(AJSHBJCASbcsasb,)")
-- EXECUTE IMMEDIATE FROM '@GITHUB_DB.GITHUB.SNOWFLAKE_AWA/branches/SNOWFLAKE/MISCELLANEOUS/dates.sql';

-- Regex lectures (folder has spaces and colons — quoted path handles it)
EXECUTE IMMEDIATE FROM '@GITHUB_DB.GITHUB.SNOWFLAKE_AWA/branches/SNOWFLAKE/LECTURE 14 : REGEX - PART4/mastering_regex.sql';
EXECUTE IMMEDIATE FROM '@GITHUB_DB.GITHUB.SNOWFLAKE_AWA/branches/SNOWFLAKE/LECTURE 14 : REGEX - PART4/regexp_intro2.sql';

-- ================================================================
-- STEP 10: SWITCH TO PYTHON BRANCH AND EXECUTE
-- ================================================================
SET GIT_BRANCH = 'PYTHON';
SET GIT_BASE   = $GIT_REPO || '/branches/' || $GIT_BRANCH;

-- Verify what Python files exist
LIST '@GITHUB_DB.GITHUB.SNOWFLAKE_AWA/branches/PYTHON/' PATTERN='.*\\.py';

-- ================================================================
-- STEP 11: CREATE STORED PROCEDURE FROM PYTHON BRANCH
-- (update folder and filename after checking LIST output above)
-- ================================================================
CREATE OR REPLACE PROCEDURE GITHUB_DB.GITHUB.RUN_RFM_FROM_GIT()
  RETURNS STRING
  LANGUAGE PYTHON
  RUNTIME_VERSION = '3.10'
  HANDLER = 'handler'
  IMPORTS = ('@GITHUB_DB.GITHUB.SNOWFLAKE_AWA/branches/PYTHON/Code Files/XML/append_fields.py')
  PACKAGES = ('snowflake-snowpark-python')
AS
$$
import append_fields

def handler(session):
    return "OK: module loaded, available function: generate_append_fields_cte"
$$;

-- Call the procedure
CALL GITHUB_DB.GITHUB.RUN_RFM_FROM_GIT();

-- ================================================================
-- STEP 12: REFRESH ANYTIME YOU PUSH NEW CODE TO GITHUB
-- ================================================================
ALTER GIT REPOSITORY GITHUB_DB.GITHUB.SNOWFLAKE_AWA FETCH;

-- Then re-run LIST to confirm new files are visible
LIST '@GITHUB_DB.GITHUB.SNOWFLAKE_AWA/branches/SNOWFLAKE/' PATTERN='.*\\.sql';
LIST '@GITHUB_DB.GITHUB.SNOWFLAKE_AWA/branches/PYTHON/' PATTERN='.*\\.py';

