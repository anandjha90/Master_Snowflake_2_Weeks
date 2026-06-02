-- =====================================================================
-- 02_storage_integration.sql  |  Run as ACCOUNTADMIN
-- Securely connects Snowflake to your AWS S3 bucket (no keys in SQL).
-- PREREQ: an AWS IAM role that trusts Snowflake (see docs/02_aws_s3_setup.md).
-- =====================================================================

USE ROLE ACCOUNTADMIN;

-- 1) Create the integration. Replace the ARN and bucket path.
CREATE STORAGE INTEGRATION IF NOT EXISTS HC_S3_INT
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:role/snowflake-hc-role'
  STORAGE_ALLOWED_LOCATIONS = ('s3://<YOUR_BUCKET>/healthcare/');

-- 2) Read back the values you must paste into the AWS IAM trust policy.
--    Copy STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID from the output.
DESC INTEGRATION HC_S3_INT;

-- 3) Let dbt's role use it (optional; loading is usually done by ACCOUNTADMIN/SYSADMIN)
GRANT USAGE ON INTEGRATION HC_S3_INT TO ROLE HC_TRANSFORMER;
