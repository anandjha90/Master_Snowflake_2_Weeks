# 5. Business KPIs (20)

All SQL runs against the `MARTS` schema (`fact_admissions`, `fact_treatments`,
`fact_claims`, and the dims). Replace `HC_DB.MARTS` if your schema differs.

### 1. Total Admissions
*Volume of hospital admissions.*
```sql
SELECT COUNT(*) AS total_admissions FROM HC_DB.MARTS.FACT_ADMISSIONS;
```

### 2. Average Length of Stay (ALOS)
*Mean days per admission — efficiency & capacity signal.*
```sql
SELECT ROUND(AVG(length_of_stay),2) AS alos_days FROM HC_DB.MARTS.FACT_ADMISSIONS;
```

### 3. 30-Day Readmission Rate
*Share of admissions flagged as readmissions — quality-of-care signal.*
```sql
SELECT ROUND(100.0*SUM(CASE WHEN is_readmission THEN 1 ELSE 0 END)/COUNT(*),2) AS readmission_rate_pct
FROM HC_DB.MARTS.FACT_ADMISSIONS;
```

### 4. Bed Occupancy Proxy (patient-days by hospital)
*Total patient-days each hospital absorbed.*
```sql
SELECT h.hospital_name, SUM(f.length_of_stay) AS patient_days
FROM HC_DB.MARTS.FACT_ADMISSIONS f
JOIN HC_DB.MARTS.DIM_HOSPITAL h ON f.hospital_key=h.hospital_key
GROUP BY 1 ORDER BY 2 DESC;
```

### 5. Admissions by Type
*Emergency vs Urgent vs Elective mix.*
```sql
SELECT admission_type, COUNT(*) AS n,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER(),1) AS pct
FROM HC_DB.MARTS.FACT_ADMISSIONS GROUP BY 1 ORDER BY 2 DESC;
```

### 6. Top Diagnoses
*Most frequent diagnosis codes.*
```sql
SELECT diagnosis_code, COUNT(*) AS n
FROM HC_DB.MARTS.FACT_ADMISSIONS GROUP BY 1 ORDER BY 2 DESC LIMIT 10;
```

### 7. Treatment Success Rate
*Share of treatments with a Success outcome.*
```sql
SELECT ROUND(100.0*SUM(is_success)/COUNT(*),2) AS success_rate_pct
FROM HC_DB.MARTS.FACT_TREATMENTS;
```

### 8. Treatment Success Rate by Doctor
*Ranks clinicians by outcome (min volume 50).*
```sql
SELECT d.doctor_name, COUNT(*) AS treatments,
       ROUND(100.0*SUM(t.is_success)/COUNT(*),1) AS success_pct
FROM HC_DB.MARTS.FACT_TREATMENTS t
JOIN HC_DB.MARTS.DIM_DOCTOR d ON t.doctor_key=d.doctor_key
GROUP BY 1 HAVING COUNT(*)>=50 ORDER BY success_pct DESC LIMIT 10;
```

### 9. Average Treatment Cost
```sql
SELECT ROUND(AVG(cost),2) AS avg_cost FROM HC_DB.MARTS.FACT_TREATMENTS;
```

### 10. Revenue per Admission (approved claim $)
```sql
SELECT ROUND(AVG(total_approved),2) AS revenue_per_admission
FROM HC_DB.MARTS.FACT_ADMISSIONS;
```

### 11. Total Claimed vs Approved (recovery rate)
```sql
SELECT SUM(claim_amount) AS claimed, SUM(approved_amount) AS approved,
       ROUND(100.0*SUM(approved_amount)/NULLIF(SUM(claim_amount),0),1) AS recovery_pct
FROM HC_DB.MARTS.FACT_CLAIMS;
```

### 12. Insurance Approval Rate
```sql
SELECT ROUND(100.0*SUM(CASE WHEN claim_status='Approved' THEN 1 END)/COUNT(*),2) AS approval_rate_pct
FROM HC_DB.MARTS.FACT_CLAIMS;
```

### 13. Claim Rejection Rate
```sql
SELECT ROUND(100.0*SUM(CASE WHEN claim_status='Rejected' THEN 1 END)/COUNT(*),2) AS rejection_rate_pct
FROM HC_DB.MARTS.FACT_CLAIMS;
```

### 14. Pending Claims Backlog
```sql
SELECT COUNT(*) AS pending_claims, SUM(claim_amount) AS pending_value
FROM HC_DB.MARTS.FACT_CLAIMS WHERE claim_status='Pending';
```

### 15. Average Days to Settle
```sql
SELECT ROUND(AVG(days_to_settle),1) AS avg_settle_days
FROM HC_DB.MARTS.FACT_CLAIMS WHERE settle_date IS NOT NULL;
```

### 16. Denied Amount by Insurer
```sql
SELECT i.insurer_name, SUM(c.denied_amount) AS total_denied
FROM HC_DB.MARTS.FACT_CLAIMS c
JOIN HC_DB.MARTS.DIM_INSURANCE i ON c.insurance_key=i.insurance_key
GROUP BY 1 ORDER BY 2 DESC;
```

### 17. Revenue by Department
```sql
SELECT department, SUM(total_approved) AS revenue
FROM HC_DB.MARTS.FACT_ADMISSIONS GROUP BY 1 ORDER BY 2 DESC;
```

### 18. Monthly Admissions Trend
```sql
SELECT DATE_TRUNC('month', admit_date) AS mth, COUNT(*) AS admissions
FROM HC_DB.MARTS.FACT_ADMISSIONS GROUP BY 1 ORDER BY 1;
```

### 19. High-Value Patients (lifetime approved $)
```sql
SELECT patient_key, SUM(total_approved) AS lifetime_revenue
FROM HC_DB.MARTS.FACT_ADMISSIONS GROUP BY 1 ORDER BY 2 DESC LIMIT 20;
```

### 20. Cost-to-Revenue Ratio by Hospital
*Treatment cost vs approved claim revenue.*
```sql
SELECT h.hospital_name,
       ROUND(SUM(f.total_treatment_cost),0) AS cost,
       ROUND(SUM(f.total_approved),0)        AS revenue,
       ROUND(SUM(f.total_treatment_cost)/NULLIF(SUM(f.total_approved),0),2) AS cost_to_revenue
FROM HC_DB.MARTS.FACT_ADMISSIONS f
JOIN HC_DB.MARTS.DIM_HOSPITAL h ON f.hospital_key=h.hospital_key
GROUP BY 1 ORDER BY cost_to_revenue DESC;
```
