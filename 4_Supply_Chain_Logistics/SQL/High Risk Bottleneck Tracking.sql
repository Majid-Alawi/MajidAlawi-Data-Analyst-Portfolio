-- ---- 03_high_risk_bottleneck_tracking.sql ----
-- Source tables: orderlist (fact), whcapacities and whcosts (dimensions)
-- Join keys: orderlist.plant_code = whcapacities.plant_id = whcosts.wh
-- Volume is measured in orders: daily_capacity (e.g. 1,013) is on the order scale, while summed unit_quantity (e.g. 28.6M) is not comparable
-- Assumes daily_capacity and cost_unit are per order; confirm against the source sheet
-- If order_date holds one distinct value, breach_days_trailing_7d and utilization_change_pct stay at one row per plant

USE supply_chain_logistics;

WITH daily_node_volume AS (
    -- Orders processed per warehouse node per day; units kept for reference only
    SELECT
        o.plant_code,
        DATE(o.order_date)   AS order_day,
        COUNT(*)             AS orders,
        SUM(o.unit_quantity) AS units_processed
    FROM orderlist AS o
    GROUP BY
        o.plant_code,
        DATE(o.order_date)
),

node_capacity AS (
    -- LEFT JOIN keeps nodes with no capacity record visible instead of dropping them
    SELECT
        dv.plant_code,
        dv.order_day,
        dv.orders,
        dv.units_processed,
        wc.daily_capacity,
        wco.cost_unit
    FROM daily_node_volume AS dv
    LEFT JOIN whcapacities AS wc
        ON dv.plant_code = wc.plant_id
    LEFT JOIN whcosts AS wco
        ON dv.plant_code = wco.wh
),

node_utilization AS (
    -- Utilization, overflow orders and overflow cost per node per day
    SELECT
        nc.plant_code,
        nc.order_day,
        nc.orders,
        nc.units_processed,
        nc.daily_capacity,
        nc.cost_unit,
        ROUND(100.0 * nc.orders / NULLIF(nc.daily_capacity, 0), 2)           AS utilization_pct,
        GREATEST(nc.orders - nc.daily_capacity, 0)                           AS overflow_orders,
        ROUND(GREATEST(nc.orders - nc.daily_capacity, 0) * nc.cost_unit, 2)  AS overflow_cost
    FROM node_capacity AS nc
),

node_risk AS (
    -- Trailing breach frequency, day-over-day change, backlog and daily node ranking
    SELECT
        nu.plant_code,
        nu.order_day,
        nu.orders,
        nu.units_processed,
        nu.daily_capacity,
        nu.utilization_pct,
        nu.overflow_orders,
        nu.overflow_cost,
        SUM(CASE WHEN nu.utilization_pct > 100 THEN 1 ELSE 0 END) OVER (
            PARTITION BY nu.plant_code
            ORDER BY nu.order_day
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        )                                                           AS breach_days_trailing_7d,
        ROUND(nu.utilization_pct - LAG(nu.utilization_pct) OVER (
            PARTITION BY nu.plant_code
            ORDER BY nu.order_day
        ), 2)                                                       AS utilization_change_pct,
        SUM(nu.overflow_orders) OVER (
            PARTITION BY nu.plant_code
            ORDER BY nu.order_day
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )                                                           AS cumulative_overflow_orders,
        RANK() OVER (
            PARTITION BY nu.order_day
            ORDER BY nu.utilization_pct DESC
        )                                                           AS utilization_rank
    FROM node_utilization AS nu
)

SELECT
    nr.plant_code,
    nr.order_day,
    nr.orders,
    nr.units_processed,
    nr.daily_capacity,
    nr.utilization_pct,
    nr.utilization_change_pct,
    nr.overflow_orders,
    nr.overflow_cost,
    nr.breach_days_trailing_7d,
    nr.cumulative_overflow_orders,
    nr.utilization_rank,
    CASE
        WHEN nr.daily_capacity IS NULL THEN 'NO CAPACITY RECORD'
        WHEN nr.utilization_pct > 100  THEN 'BREACH'
        WHEN nr.utilization_pct >= 85  THEN 'HIGH RISK'
        WHEN nr.utilization_pct >= 70  THEN 'WATCH'
        ELSE 'NORMAL'
    END                                                             AS bottleneck_risk_tier
FROM node_risk AS nr
ORDER BY
    nr.order_day,
    nr.utilization_rank,
    nr.plant_code;