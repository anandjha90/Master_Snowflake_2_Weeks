-- =====================================================================
-- 01_account_setup.sql  |  Run as ACCOUNTADMIN
-- Creates the warehouse, database, schemas, roles and grants used by
-- the Healthcare Patient Journey & Revenue Analytics Platform.
-- =====================================================================

USE ROLE ACCOUNTADMIN;

-- ---- Warehouse (compute) --------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS HC_WH
  WAREHOUSE_SIZE   = 'XSMALL'   -- start small; resize for big loads
  AUTO_SUSPEND     = 60         -- seconds idle before it pauses (saves credits)
  AUTO_RESUME      = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Compute for healthcare analytics loads + dbt runs';

-- ---- Database & layered schemas -------------------------------------
CREATE DATABASE IF NOT EXISTS HC_DB
  COMMENT = 'Healthcare analytics platform';

CREATE SCHEMA IF NOT EXISTS HC_DB.RAW      COMMENT = 'Untransformed data loaded from S3';
CREATE SCHEMA IF NOT EXISTS HC_DB.STAGING  COMMENT = 'dbt staging models (cleaned, typed)';
CREATE SCHEMA IF NOT EXISTS HC_DB.MARTS    COMMENT = 'dbt star-schema dims & facts';
CREATE SCHEMA IF NOT EXISTS HC_DB.SNAPSHOTS COMMENT = 'dbt SCD2 snapshots';

-- ---- Role for dbt to use --------------------------------------------
CREATE ROLE IF NOT EXISTS HC_TRANSFORMER COMMENT = 'Role used by dbt Cloud';

-- Grant warehouse + database usage
GRANT USAGE  ON WAREHOUSE HC_WH       TO ROLE HC_TRANSFORMER;
GRANT USAGE  ON DATABASE  HC_DB       TO ROLE HC_TRANSFORMER;
GRANT USAGE  ON ALL SCHEMAS IN DATABASE HC_DB TO ROLE HC_TRANSFORMER;
GRANT USAGE  ON FUTURE SCHEMAS IN DATABASE HC_DB TO ROLE HC_TRANSFORMER;

-- dbt needs to build objects everywhere except RAW (RAW is loaded by COPY INTO)
GRANT CREATE TABLE, CREATE VIEW ON SCHEMA HC_DB.STAGING   TO ROLE HC_TRANSFORMER;
GRANT CREATE TABLE, CREATE VIEW ON SCHEMA HC_DB.MARTS      TO ROLE HC_TRANSFORMER;
GRANT CREATE TABLE, CREATE VIEW ON SCHEMA HC_DB.SNAPSHOTS  TO ROLE HC_TRANSFORMER;

-- dbt reads from RAW
GRANT SELECT ON ALL TABLES    IN SCHEMA HC_DB.RAW TO ROLE HC_TRANSFORMER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA HC_DB.RAW TO ROLE HC_TRANSFORMER;

-- ---- Attach the role to your user (replace MY_USER) -----------------
SET my_user = CURRENT_USER();
GRANT ROLE HC_TRANSFORMER TO USER IDENTIFIER($my_user);

-- Sanity check
SHOW WAREHOUSES LIKE 'HC_WH';
SHOW SCHEMAS    IN DATABASE HC_DB;
