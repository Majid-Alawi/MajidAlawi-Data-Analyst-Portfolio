-- TAB 2: LTV & Cohort Matrix | 2_ltv_cohort_matrix.sql
USE saas_churn_analytics;

WITH data_window AS (
    -- Last date the dataset observes, used to cap tenure and to decide which cohorts are old enough to measure
    SELECT GREATEST(MAX(s.start_date), MAX(s.end_date)) AS as_of_date
    FROM fact_subscriptions AS s
),
subscription_tenure AS (
    -- Plan is billed in advance, so the first month always counts; active subscriptions run to the as-of date
    SELECT
        s.subscription_id,
        CAST(DATE_FORMAT(s.start_date, '%Y-%m-01') AS DATE) AS cohort_month,
        pl.monthly_price,
        TIMESTAMPDIFF(MONTH, s.start_date, COALESCE(s.end_date, d.as_of_date)) AS months_survived,
        TIMESTAMPDIFF(MONTH, s.start_date, COALESCE(s.end_date, d.as_of_date)) + 1 AS months_billed
    FROM fact_subscriptions AS s
    INNER JOIN dim_plans AS pl
        ON pl.plan_id = s.plan_id
    CROSS JOIN data_window AS d
),
cohort_totals AS (
    -- Revenue inside the first 3, 6 and 12 months, and how many subscribers survived that long
    SELECT
        t.cohort_month,
        COUNT(*) AS subscribers,
        SUM(t.monthly_price * LEAST(t.months_billed, 3)) AS revenue_3m,
        SUM(t.monthly_price * LEAST(t.months_billed, 6)) AS revenue_6m,
        SUM(t.monthly_price * LEAST(t.months_billed, 12)) AS revenue_12m,
        SUM(CASE WHEN t.months_survived >= 3 THEN 1 ELSE 0 END) AS retained_3m,
        SUM(CASE WHEN t.months_survived >= 6 THEN 1 ELSE 0 END) AS retained_6m,
        SUM(CASE WHEN t.months_survived >= 12 THEN 1 ELSE 0 END) AS retained_12m
    FROM subscription_tenure AS t
    GROUP BY t.cohort_month
),
cohort_ltv AS (
    -- Report a horizon only once the whole cohort has had that long to mature; tiny cohorts are dropped
    SELECT
        c.cohort_month,
        c.subscribers,
        CASE WHEN DATE_ADD(c.cohort_month, INTERVAL 4 MONTH) <= d.as_of_date
             THEN ROUND(c.revenue_3m / c.subscribers, 2) END AS ltv_3m,
        CASE WHEN DATE_ADD(c.cohort_month, INTERVAL 7 MONTH) <= d.as_of_date
             THEN ROUND(c.revenue_6m / c.subscribers, 2) END AS ltv_6m,
        CASE WHEN DATE_ADD(c.cohort_month, INTERVAL 13 MONTH) <= d.as_of_date
             THEN ROUND(c.revenue_12m / c.subscribers, 2) END AS ltv_12m,
        CASE WHEN DATE_ADD(c.cohort_month, INTERVAL 4 MONTH) <= d.as_of_date
             THEN ROUND(c.retained_3m / c.subscribers * 100, 1) END AS retention_3m_pct,
        CASE WHEN DATE_ADD(c.cohort_month, INTERVAL 7 MONTH) <= d.as_of_date
             THEN ROUND(c.retained_6m / c.subscribers * 100, 1) END AS retention_6m_pct,
        CASE WHEN DATE_ADD(c.cohort_month, INTERVAL 13 MONTH) <= d.as_of_date
             THEN ROUND(c.retained_12m / c.subscribers * 100, 1) END AS retention_12m_pct
    FROM cohort_totals AS c
    CROSS JOIN data_window AS d
    WHERE c.subscribers >= 30
)
SELECT
    cl.cohort_month,
    cl.subscribers,
    cl.ltv_3m,
    cl.ltv_6m,
    cl.ltv_12m,
    cl.ltv_6m - cl.ltv_3m AS expansion_3m_to_6m,
    cl.ltv_12m - cl.ltv_6m AS expansion_6m_to_12m,
    ROUND(cl.ltv_12m / NULLIF(cl.ltv_3m, 0), 2) AS ltv_multiple_12m_vs_3m,
    cl.retention_3m_pct,
    cl.retention_6m_pct,
    cl.retention_12m_pct,
    ROUND(cl.ltv_3m - LAG(cl.ltv_3m) OVER (ORDER BY cl.cohort_month), 2) AS ltv_3m_vs_prior_cohort
FROM cohort_ltv AS cl
ORDER BY cl.cohort_month;