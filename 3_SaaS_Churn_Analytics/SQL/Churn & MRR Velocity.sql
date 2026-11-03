-- TAB 1: Churn & MRR Velocity | 1_churn_mrr_velocity.sql
USE saas_churn_analytics;

WITH RECURSIVE params AS (
    -- Months with fewer opening subscribers than this get NULL rates, because tiny bases give meaningless percentages
    SELECT 100 AS min_base_subscribers
),
date_bounds AS (
    -- First and last month that contain any subscription activity
    SELECT
        CAST(DATE_FORMAT(MIN(s.start_date), '%Y-%m-01') AS DATE) AS first_month,
        CAST(DATE_FORMAT(GREATEST(MAX(s.start_date), MAX(s.end_date)), '%Y-%m-01') AS DATE) AS last_month
    FROM fact_subscriptions AS s
),
month_spine AS (
    -- One row per calendar month, so months with zero activity still appear
    SELECT b.first_month AS month_start
    FROM date_bounds AS b

    UNION ALL

    SELECT DATE_ADD(m.month_start, INTERVAL 1 MONTH)
    FROM month_spine AS m
    CROSS JOIN date_bounds AS b
    WHERE m.month_start < b.last_month
),
subscription_value AS (
    -- Each subscription with its plan price, so MRR comes from the price list, not from payment rows
    SELECT
        s.subscription_id,
        s.start_date,
        s.end_date,
        pl.monthly_price
    FROM fact_subscriptions AS s
    INNER JOIN dim_plans AS pl
        ON pl.plan_id = s.plan_id
),
subscriber_flow AS (
    -- Opening base, signups, churn events and the MRR attached to each, per month
    SELECT
        m.month_start,
        COUNT(CASE WHEN v.start_date < m.month_start
                    AND (v.end_date IS NULL OR v.end_date >= m.month_start)
                   THEN 1 END) AS opening_subscribers,
        COUNT(CASE WHEN v.start_date >= m.month_start
                    AND v.start_date < DATE_ADD(m.month_start, INTERVAL 1 MONTH)
                   THEN 1 END) AS new_subscribers,
        COUNT(CASE WHEN v.end_date >= m.month_start
                    AND v.end_date < DATE_ADD(m.month_start, INTERVAL 1 MONTH)
                   THEN 1 END) AS churned_subscribers,
        COUNT(CASE WHEN v.start_date < m.month_start
                    AND v.end_date >= m.month_start
                    AND v.end_date < DATE_ADD(m.month_start, INTERVAL 1 MONTH)
                   THEN 1 END) AS churned_from_opening,
        COALESCE(SUM(CASE WHEN v.start_date >= m.month_start
                           AND v.start_date < DATE_ADD(m.month_start, INTERVAL 1 MONTH)
                          THEN v.monthly_price END), 0) AS new_mrr,
        COALESCE(SUM(CASE WHEN v.end_date >= m.month_start
                           AND v.end_date < DATE_ADD(m.month_start, INTERVAL 1 MONTH)
                          THEN v.monthly_price END), 0) AS churned_mrr,
        COALESCE(SUM(CASE WHEN v.start_date < DATE_ADD(m.month_start, INTERVAL 1 MONTH)
                           AND (v.end_date IS NULL OR v.end_date >= DATE_ADD(m.month_start, INTERVAL 1 MONTH))
                          THEN v.monthly_price END), 0) AS closing_mrr
    FROM month_spine AS m
    CROSS JOIN subscription_value AS v
    GROUP BY m.month_start
),
monthly_metrics AS (
    -- Rates use the opening base, so same-month signups cannot distort retention
    SELECT
        f.month_start,
        f.opening_subscribers,
        f.new_subscribers,
        f.churned_subscribers,
        f.opening_subscribers + f.new_subscribers - f.churned_subscribers AS closing_subscribers,
        CASE WHEN f.opening_subscribers >= p.min_base_subscribers
             THEN ROUND(f.churned_from_opening / f.opening_subscribers, 4) END AS churn_rate,
        CASE WHEN f.opening_subscribers >= p.min_base_subscribers
             THEN ROUND(1 - f.churned_from_opening / f.opening_subscribers, 4) END AS retention_rate,
        f.new_mrr,
        f.churned_mrr,
        f.closing_mrr AS mrr
    FROM subscriber_flow AS f
    CROSS JOIN params AS p
),
velocity AS (
    -- All LAG/LEAD windows live here, ordered by month
    SELECT
        mm.month_start,
        mm.opening_subscribers,
        mm.new_subscribers,
        mm.churned_subscribers,
        mm.closing_subscribers,
        mm.retention_rate,
        LAG(mm.retention_rate) OVER month_order AS prev_retention_rate,
        mm.churn_rate,
        LAG(mm.churn_rate) OVER month_order AS prev_churn_rate,
        AVG(mm.churn_rate) OVER (month_order ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS churn_rate_3m_avg,
        mm.mrr,
        mm.new_mrr,
        mm.churned_mrr,
        LAG(mm.mrr) OVER month_order AS prev_mrr,
        LEAD(mm.mrr) OVER month_order AS next_mrr
    FROM monthly_metrics AS mm
    WINDOW month_order AS (ORDER BY mm.month_start)
)
SELECT
    v.month_start,
    v.opening_subscribers,
    v.new_subscribers,
    v.churned_subscribers,
    v.closing_subscribers,
    v.retention_rate,
    ROUND(v.retention_rate - v.prev_retention_rate, 4) AS retention_change_mom,
    v.churn_rate,
    ROUND(v.churn_rate - v.prev_churn_rate, 4) AS churn_velocity,
    ROUND(v.churn_rate_3m_avg, 4) AS churn_rate_3m_avg,
    v.mrr,
    v.new_mrr,
    v.churned_mrr,
    v.new_mrr - v.churned_mrr AS net_new_mrr,
    ROUND((v.mrr - v.prev_mrr) / NULLIF(v.prev_mrr, 0) * 100, 2) AS mrr_growth_pct,
    v.next_mrr - v.mrr AS next_month_mrr_change,
    CASE
        WHEN v.prev_mrr IS NULL THEN 'Baseline'
        WHEN v.mrr > v.prev_mrr THEN 'Expanding'
        WHEN v.mrr < v.prev_mrr THEN 'Contracting'
        ELSE 'Flat'
    END AS mrr_trajectory
FROM velocity AS v
ORDER BY v.month_start;

-- Reconciliation: the latest month's MRR must equal today's active subscriptions x plan price
SELECT
    COUNT(*) AS active_subscriptions,
    SUM(pl.monthly_price) AS active_mrr
FROM fact_subscriptions AS s
INNER JOIN dim_plans AS pl
    ON pl.plan_id = s.plan_id
WHERE s.end_date IS NULL;