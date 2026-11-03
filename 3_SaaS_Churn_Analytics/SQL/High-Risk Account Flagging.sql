-- TAB 3: High-Risk Account Flagging | 3_high_risk_accounts.sql
USE saas_churn_analytics;

-- Step 1: full risk logic saved as a reusable view (also usable directly from Power BI)
CREATE OR REPLACE VIEW vw_account_risk AS
WITH params AS (
    -- Tunable thresholds; windows are anchored to the latest usage event, not today's date
    -- Widen INTERVAL 30/60 DAY to 90/180 DAY if 30-day windows look too thin
    SELECT
        MAX(u.event_date) AS anchor_date,
        DATE_SUB(MAX(u.event_date), INTERVAL 30 DAY) AS recent_start,
        DATE_SUB(MAX(u.event_date), INTERVAL 60 DAY) AS prior_start,
        0.75 AS baseline_factor
    FROM fact_usage AS u
),
active_accounts AS (
    -- Active accounts with at least 60 days of tenure, so both comparison windows apply
    SELECT
        s.subscription_id,
        s.customer_id,
        s.plan_id,
        CAST(DATE_FORMAT(s.start_date, '%Y-%m-01') AS DATE) AS cohort_month
    FROM fact_subscriptions AS s
    CROSS JOIN params AS p
    WHERE s.status = 'active'
      AND s.end_date IS NULL
      AND s.start_date <= p.prior_start
),
usage_windows AS (
    -- Login and feature activity per customer: last 30 days vs. the 30 days before
    SELECT
        u.customer_id,
        SUM(CASE WHEN u.event_date > p.recent_start
                 THEN u.login_count ELSE 0 END) AS recent_logins,
        SUM(CASE WHEN u.event_date > p.prior_start
                  AND u.event_date <= p.recent_start
                 THEN u.login_count ELSE 0 END) AS prior_logins,
        COUNT(DISTINCT CASE WHEN u.event_date > p.recent_start
                            THEN u.feature_name END) AS recent_features
    FROM fact_usage AS u
    CROSS JOIN params AS p
    GROUP BY u.customer_id
),
latest_paid AS (
    -- Most recent successful payment per subscription, used as revenue at stake
    SELECT
        r.subscription_id,
        r.amount AS monthly_value
    FROM (
        SELECT
            p.subscription_id,
            p.amount,
            ROW_NUMBER() OVER (PARTITION BY p.subscription_id ORDER BY p.payment_date DESC) AS rn
        FROM fact_payments AS p
        WHERE p.payment_status = 'paid'
    ) AS r
    WHERE r.rn = 1
),
account_activity AS (
    -- LEFT JOINs keep silent accounts in the data with zeros instead of dropping them
    SELECT
        a.subscription_id,
        a.customer_id,
        a.plan_id,
        a.cohort_month,
        COALESCE(w.recent_logins, 0) AS recent_logins,
        COALESCE(w.prior_logins, 0) AS prior_logins,
        COALESCE(w.recent_features, 0) AS recent_features,
        COALESCE(lp.monthly_value, 0) AS monthly_value
    FROM active_accounts AS a
    LEFT JOIN usage_windows AS w
        ON w.customer_id = a.customer_id
    LEFT JOIN latest_paid AS lp
        ON lp.subscription_id = a.subscription_id
),
cohort_baselines AS (
    -- Window averages give every account its own cohort's baseline without collapsing rows
    SELECT
        ac.*,
        AVG(ac.recent_logins) OVER (PARTITION BY ac.cohort_month) AS cohort_avg_logins,
        AVG(ac.recent_features) OVER (PARTITION BY ac.cohort_month) AS cohort_avg_features,
        COUNT(*) OVER (PARTITION BY ac.cohort_month) AS cohort_accounts
    FROM account_activity AS ac
),
risk_tiers AS (
    SELECT
        cb.*,
        (cb.recent_logins < cb.cohort_avg_logins * p.baseline_factor)
        + (cb.recent_features < cb.cohort_avg_features * p.baseline_factor)
        + (cb.recent_logins < cb.prior_logins) AS risk_score
    FROM cohort_baselines AS cb
    CROSS JOIN params AS p
)
SELECT
    rt.subscription_id,
    rt.customer_id,
    rt.plan_id,
    rt.cohort_month,
    rt.cohort_accounts,
    rt.recent_logins,
    rt.prior_logins,
    rt.recent_logins - rt.prior_logins AS login_velocity,
    ROUND(rt.cohort_avg_logins, 2) AS cohort_avg_logins,
    ROUND(rt.recent_logins / NULLIF(rt.cohort_avg_logins, 0) * 100, 1) AS pct_of_cohort_baseline,
    rt.recent_features,
    ROUND(rt.cohort_avg_features, 2) AS cohort_avg_features,
    rt.monthly_value,
    rt.risk_score,
    CASE
        WHEN rt.risk_score = 3 THEN 'CRITICAL'
        WHEN rt.risk_score = 2 THEN 'HIGH'
        WHEN rt.risk_score = 1 THEN 'WATCH'
        ELSE 'HEALTHY'
    END AS risk_tier
FROM risk_tiers AS rt;

-- Step 2: executive summary, one row per tier
SELECT
    v.risk_tier,
    COUNT(*) AS accounts,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 1) AS pct_of_active_accounts,
    SUM(v.monthly_value) AS monthly_value_at_risk
FROM vw_account_risk AS v
GROUP BY v.risk_tier
ORDER BY FIELD(v.risk_tier, 'CRITICAL', 'HIGH', 'WATCH', 'HEALTHY');

-- Step 3: call list, top 25 CRITICAL accounts ranked by revenue at risk
SELECT
    v.subscription_id,
    v.customer_id,
    v.plan_id,
    v.cohort_month,
    v.recent_logins,
    v.prior_logins,
    v.login_velocity,
    v.pct_of_cohort_baseline,
    v.recent_features,
    v.monthly_value,
    v.risk_tier
FROM vw_account_risk AS v
WHERE v.risk_tier = 'CRITICAL'
ORDER BY v.monthly_value DESC, v.login_velocity ASC
LIMIT 25;