-- ---- 01_carrier_delay_velocity.sql ----
-- Source tables: orderlist (fact), freightrates (dimension); the specified fact_orders / dim_freight_rates do not exist in the schema
-- Column names follow the Phase 1 snake_case output; confirm with DESCRIBE orderlist; and DESCRIBE freightrates;
-- If order_date holds only one distinct value, the trailing and LAG columns have a single row per carrier; read delay_rate and delay_rank instead

USE supply_chain_logistics;

WITH lane_benchmark AS (
    -- One contracted transit time per carrier lane and service level, so the join below cannot duplicate orders
    SELECT
        fr.carrier,
        fr.orig_port_cd,
        fr.dest_port_cd,
        fr.svc_cd,
        AVG(fr.tpt_day_cnt) AS contract_transit_days
    FROM freightrates AS fr
    GROUP BY
        fr.carrier,
        fr.orig_port_cd,
        fr.dest_port_cd,
        fr.svc_cd
),

order_delay AS (
    -- Delay days = the larger of late-shipment days and transit days beyond contract, never below zero
    SELECT
        o.order_id,
        DATE(o.order_date) AS order_day,
        o.carrier,
        o.tpt AS actual_transit_days,
        lb.contract_transit_days,
        GREATEST(
            COALESCE(o.ship_late_day_count, 0),
            COALESCE(o.tpt - lb.contract_transit_days, 0),
            0
        ) AS delay_days
    FROM orderlist AS o
    LEFT JOIN lane_benchmark AS lb
        ON  o.carrier          = lb.carrier
        AND o.origin_port      = lb.orig_port_cd
        AND o.destination_port = lb.dest_port_cd
        AND o.service_level    = lb.svc_cd
),

carrier_daily AS (
    -- Frequency and duration of delays per carrier per day
    SELECT
        od.carrier,
        od.order_day,
        COUNT(*)                                                    AS total_orders,
        SUM(CASE WHEN od.delay_days > 0 THEN 1 ELSE 0 END)          AS delayed_orders,
        ROUND(100.0 * SUM(CASE WHEN od.delay_days > 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS delay_rate_pct,
        ROUND(AVG(CASE WHEN od.delay_days > 0 THEN od.delay_days END), 2)               AS avg_delay_days
    FROM order_delay AS od
    GROUP BY
        od.carrier,
        od.order_day
),

carrier_velocity AS (
    -- Trailing trend, day-over-day change and daily ranking across the carrier network
    SELECT
        cd.carrier,
        cd.order_day,
        cd.total_orders,
        cd.delayed_orders,
        cd.delay_rate_pct,
        cd.avg_delay_days,
        ROUND(AVG(cd.delay_rate_pct) OVER (
            PARTITION BY cd.carrier
            ORDER BY cd.order_day
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 2)                                                       AS trailing_7d_delay_rate_pct,
        ROUND(cd.delay_rate_pct - LAG(cd.delay_rate_pct) OVER (
            PARTITION BY cd.carrier
            ORDER BY cd.order_day
        ), 2)                                                       AS delay_rate_change_pct,
        DENSE_RANK() OVER (
            PARTITION BY cd.order_day
            ORDER BY cd.delay_rate_pct DESC
        )                                                           AS delay_rank
    FROM carrier_daily AS cd
)

SELECT
    cv.carrier,
    cv.order_day,
    cv.total_orders,
    cv.delayed_orders,
    cv.delay_rate_pct,
    cv.avg_delay_days,
    cv.trailing_7d_delay_rate_pct,
    cv.delay_rate_change_pct,
    cv.delay_rank,
    CASE
        WHEN cv.delay_rate_change_pct > 0
         AND cv.delay_rate_pct > cv.trailing_7d_delay_rate_pct THEN 'DETERIORATING'
        WHEN cv.delay_rate_change_pct < 0 THEN 'IMPROVING'
        ELSE 'STABLE'
    END                                                             AS delay_trend_flag
FROM carrier_velocity AS cv
ORDER BY
    cv.order_day,
    cv.delay_rank,
    cv.carrier;