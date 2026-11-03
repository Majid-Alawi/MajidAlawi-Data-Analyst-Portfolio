# ==============================================================
# HR Analytics: Employee Attrition & Performance | Phase 3: BI View Layer
# ==============================================================
USE hr_attrition_analytics;  # All views live beside the source table


# ---- View 1: Employee Detail (row-level feed for Power BI / Tableau) ----
CREATE OR REPLACE VIEW vw_employee_detail AS
SELECT
    employeenumber,
    age,
    gender,
    maritalstatus,
    department,
    jobrole,
    joblevel,
    overtime,
    monthlyincome,
    yearsatcompany,
    jobsatisfaction,
    worklifebalance,
    attrition,
    CASE WHEN attrition = 'Yes' THEN 1 ELSE 0 END AS attrition_flag,  # 1/0 flag turns attrition rate into a simple AVG or SUM in BI tools
    CASE
        WHEN age < 30 THEN 'Under 30'
        WHEN age BETWEEN 30 AND 39 THEN '30-39'
        WHEN age BETWEEN 40 AND 49 THEN '40-49'
        ELSE '50 and Over'
    END AS age_group,  # Bands make age readable on a chart axis
    CASE
        WHEN monthlyincome < 3000 THEN 'Under 3,000'
        WHEN monthlyincome BETWEEN 3000 AND 5999 THEN '3,000-5,999'
        WHEN monthlyincome BETWEEN 6000 AND 9999 THEN '6,000-9,999'
        ELSE '10,000 and Over'
    END AS income_band,  # Bands expose the low-pay risk pattern from Tab 4
    CASE
        WHEN yearsatcompany <= 2 THEN '0-2 Years'
        WHEN yearsatcompany BETWEEN 3 AND 5 THEN '3-5 Years'
        WHEN yearsatcompany BETWEEN 6 AND 10 THEN '6-10 Years'
        ELSE '11+ Years'
    END AS tenure_band  # Shows whether leavers cluster early in tenure
FROM hr_attrition_master;


# ---- View 2: Core Attrition KPIs ----
CREATE OR REPLACE VIEW vw_core_attrition_kpis AS
SELECT
    COUNT(*) AS total_employees,
    SUM(CASE WHEN attrition = 'No' THEN 1 ELSE 0 END) AS active_employees,
    SUM(CASE WHEN attrition = 'Yes' THEN 1 ELSE 0 END) AS departed_employees,
    ROUND(
        100.0 * SUM(CASE WHEN attrition = 'Yes' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0),  # Safe division for the headline KPI card
        2
    ) AS company_attrition_rate_pct
FROM hr_attrition_master;


# ---- View 3: Department Attrition ----
CREATE OR REPLACE VIEW vw_department_attrition AS
SELECT
    department,
    COUNT(*) AS total_headcount,
    SUM(CASE WHEN attrition = 'Yes' THEN 1 ELSE 0 END) AS departed_headcount,
    ROUND(
        100.0 * SUM(CASE WHEN attrition = 'Yes' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0),
        2
    ) AS department_attrition_rate_pct
FROM hr_attrition_master
GROUP BY department;  # Sorting is left to the BI tool, since views should not carry ORDER BY


# ---- View 4: Overtime and Salary Risk Matrix ----
CREATE OR REPLACE VIEW vw_overtime_salary_risk AS
WITH role_overtime_summary AS (
    SELECT
        jobrole,
        overtime,
        COUNT(*) AS total_headcount,
        SUM(CASE WHEN attrition = 'Yes' THEN 1 ELSE 0 END) AS departed_headcount,
        ROUND(AVG(monthlyincome), 2) AS average_monthly_income
    FROM hr_attrition_master
    GROUP BY jobrole, overtime
)
SELECT
    jobrole,
    overtime,
    total_headcount,
    average_monthly_income,
    departed_headcount,
    ROUND(
        100.0 * departed_headcount
        / NULLIF(total_headcount, 0),
        2
    ) AS attrition_rate_pct
FROM role_overtime_summary;


# ---- View Verification ----
SELECT 'vw_employee_detail' AS view_name, COUNT(*) AS row_count FROM vw_employee_detail  # Must equal 1470
UNION ALL
SELECT 'vw_core_attrition_kpis', COUNT(*) FROM vw_core_attrition_kpis  # Must equal 1
UNION ALL
SELECT 'vw_department_attrition', COUNT(*) FROM vw_department_attrition  # Must equal 3
UNION ALL
SELECT 'vw_overtime_salary_risk', COUNT(*) FROM vw_overtime_salary_risk;  # Must equal 18