-- =====================================================================
-- 04_raw_tables_ddl.sql  |  Run as ACCOUNTADMIN (or SYSADMIN)
-- Landing/RAW tables. Types mirror the CSV columns 1:1.
-- =====================================================================

USE DATABASE HC_DB;
USE SCHEMA   RAW;

CREATE OR REPLACE TABLE RAW.PATIENT_ADMISSIONS (
  admission_id     NUMBER(10,0),   -- PK
  patient_id       NUMBER(10,0),
  doctor_id        VARCHAR(5),     -- FK -> seed_doctors
  hospital_id      VARCHAR(5),     -- FK -> seed_hospitals
  admit_date       DATE,
  department       VARCHAR(10),
  admission_type   VARCHAR(3),     -- EMG / URG / ELC
  diagnosis_code   VARCHAR(10),    -- ICD-10 style
  length_of_stay   NUMBER(4,0),    -- days
  readmission_flag NUMBER(1,0)     -- 0/1
);

CREATE OR REPLACE TABLE RAW.TREATMENT_RECORDS (
  treatment_id     NUMBER(10,0),   -- PK
  admission_id     NUMBER(10,0),   -- FK -> PATIENT_ADMISSIONS
  doctor_id        VARCHAR(5),
  procedure_code   VARCHAR(10),
  treatment_date   DATE,
  cost             NUMBER(12,2),
  outcome          VARCHAR(1)      -- S / P / F
);

CREATE OR REPLACE TABLE RAW.INSURANCE_CLAIMS (
  claim_id         NUMBER(10,0),   -- PK
  admission_id     NUMBER(10,0),   -- FK -> PATIENT_ADMISSIONS
  insurance_id     VARCHAR(5),     -- FK -> seed_insurers
  claim_amount     NUMBER(12,2),
  approved_amount  NUMBER(12,2),
  claim_status     VARCHAR(1),     -- A / R / P
  claim_date       DATE,
  settle_date      DATE            -- NULL while pending
);
