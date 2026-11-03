USE hr_attrition_analytics;

# ---- Tab 4: Overtime and Salary Friction Risk Matrix ----
WITH role_overtime_summary AS (  # CTE isolates the aggregation so the final query stays readable
    SELECT
        jobrole,
        overtime,
        COUNT(*) AS total_headcount,  # Employees in each role-overtime combination
        SUM(CASE WHEN attrition = 'Yes' THEN 1 ELSE 0 END) AS departed_headcount,  # Leavers in that combination
        ROUND(AVG(monthlyincome), 2) AS average_monthly_income  # Average pay reveals whether low income compounds overtime risk
    FROM hr_attrition_master
    GROUP BY jobrole, overtime  # One row per role and overtime status
)
SELECT
    jobrole,
    overtime,
    total_headcount,
    average_monthly_income,
    departed_headcount,
    ROUND(
        100.0 * departed_headcount
        / NULLIF(total_headcount, 0),  # Safe division for the attrition rate
        2
    ) AS attrition_rate_pct
FROM role_overtime_summary
ORDER BY attrition_rate_pct DESC, average_monthly_income ASC;  # Highest attrition first, lowest pay breaks ties