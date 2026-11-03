USE hr_attrition_analytics;

# ---- Tab 3: Department-Level Attrition Drilldown ----
SELECT
    department,
    COUNT(*) AS total_headcount,  # All employees in the business unit
    SUM(CASE WHEN attrition = 'Yes' THEN 1 ELSE 0 END) AS departed_headcount,  # Leavers in the business unit
    ROUND(
        100.0 * SUM(CASE WHEN attrition = 'Yes' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0),  # Safe division per department
        2
    ) AS department_attrition_rate_pct
FROM hr_attrition_master
GROUP BY department  # One row per business unit
ORDER BY department_attrition_rate_pct DESC;  # Highest-risk departments first