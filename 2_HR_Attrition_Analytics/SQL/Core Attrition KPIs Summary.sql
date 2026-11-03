# ---- Tab 2: Core Attrition KPIs Summary ----
USE hr_attrition_analytics;

SELECT
    COUNT(*) AS total_employees,  # Every employee record in the warehouse
    SUM(CASE WHEN attrition = 'No' THEN 1 ELSE 0 END) AS active_employees,  # Employees still with the company
    SUM(CASE WHEN attrition = 'Yes' THEN 1 ELSE 0 END) AS departed_employees,  # Employees who left
    ROUND(
        100.0 * SUM(CASE WHEN attrition = 'Yes' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0),  # NULLIF prevents a divide-by-zero error on an empty table
        2
    ) AS company_attrition_rate_pct  # Departed share of total headcount, two decimals
FROM hr_attrition_master;