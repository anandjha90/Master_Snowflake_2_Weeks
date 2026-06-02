-- =====================================================================
-- 05_copy_into.sql  |  Load the three CSVs from S3 into RAW tables.
-- =====================================================================

USE DATABASE HC_DB;
USE SCHEMA   RAW;

COPY INTO RAW.PATIENT_ADMISSIONS
  FROM @RAW.HC_S3_STAGE/patient_admissions.csv
  FILE_FORMAT = (FORMAT_NAME = RAW.HC_CSV)
  ON_ERROR = 'ABORT_STATEMENT';

COPY INTO RAW.TREATMENT_RECORDS
  FROM @RAW.HC_S3_STAGE/treatment_records.csv
  FILE_FORMAT = (FORMAT_NAME = RAW.HC_CSV)
  ON_ERROR = 'ABORT_STATEMENT';

COPY INTO RAW.INSURANCE_CLAIMS
  FROM @RAW.HC_S3_STAGE/insurance_claims.csv
  FILE_FORMAT = (FORMAT_NAME = RAW.HC_CSV)
  ON_ERROR = 'ABORT_STATEMENT';

-- Re-running? COPY INTO skips files already loaded (load metadata).
-- Force a reload with:  COPY INTO ... FORCE = TRUE;
