# ==============================================================
# HR Analytics: Employee Attrition & Performance | Phase 2: MySQL Warehousing
# NOTE: if you re-ran Cell 2 with the CamelCase patch, rename jobrole, monthlyincome and overtime to job_role, monthly_income and over_time.
# ==============================================================
USE hr_attrition_analytics;  # Every query below runs against the project database


# ---- Tab 1: Database Verification Script ----
SELECT COUNT(*) AS total_employee_records  # Must match the 1,470 clean rows exported from Jupyter
FROM hr_attrition_master;