-- =====================================================================
-- 06_validation.sql  |  Confirm the load worked and data is sane.
-- =====================================================================
USE DATABASE HC_DB; USE SCHEMA RAW;

-- Row counts (expect 50,000 each)
SELECT 'admissions' AS tbl, COUNT(*) FROM RAW.PATIENT_ADMISSIONS
UNION ALL SELECT 'treatments', COUNT(*) FROM RAW.TREATMENT_RECORDS
UNION ALL SELECT 'claims',     COUNT(*) FROM RAW.INSURANCE_CLAIMS;

-- No orphan foreign keys (expect 0 rows)
SELECT t.treatment_id
FROM RAW.TREATMENT_RECORDS t
LEFT JOIN RAW.PATIENT_ADMISSIONS a ON t.admission_id = a.admission_id
WHERE a.admission_id IS NULL;

-- Claim status distribution
SELECT claim_status, COUNT(*) AS n,
       ROUND(100*COUNT(*)/SUM(COUNT(*)) OVER (),1) AS pct
FROM RAW.INSURANCE_CLAIMS GROUP BY 1 ORDER BY 2 DESC;

-- Peek
SELECT * FROM RAW.PATIENT_ADMISSIONS LIMIT 5;
