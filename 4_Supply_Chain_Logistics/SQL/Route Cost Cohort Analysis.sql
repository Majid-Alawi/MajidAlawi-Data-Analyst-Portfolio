-- ---- 02_route_cost_cohort_analysis.sql ----
-- Source tables: orderlist (fact), freightrates (dimension)
-- The schema has no distance column, so contracted transit days stand in for distance cohorts
-- Transit cutoffs (2 and 4 days) are assumptions; check SELECT MIN(tpt_day_cnt), MAX(tpt_day_cnt) FROM freightrates; and adjust
-- INNER JOIN keeps only orders that match a rate card row, so unpriced orders are excluded from cost metrics

USE supply_chain_logistics;

WITH rate_card AS (
    -- One rate per carrier, lane, service level and weight bracket, so the order join cannot duplicate rows
    SELECT
        fr.carrier,
        fr.orig_port_cd,
        fr.dest_port_cd,
        fr.svc_cd,
        fr.minm_wgh_qty,
        fr.max_wgh_qty,
        AVG(fr.rate)         AS rate_per_kg,
        MIN(fr.minimum_cost) AS minimum_cost,
        AVG(fr.tpt_day_cnt)  AS contract_transit_days
    FROM freightrates AS fr
    GROUP BY
        fr.carrier,
        fr.orig_port_cd,
        fr.dest_port_cd,
        fr.svc_cd,
        fr.minm_wgh_qty,
        fr.max_wgh_qty
),

priced_orders AS (
    -- Estimated freight cost is the higher of the minimum charge and rate times weight
    SELECT
        o.order_id,
        o.origin_port,
        o.destination_port,
        o.weight,
        rc.rate_per_kg,
        rc.contract_transit_days,
        GREATEST(rc.minimum_cost, rc.rate_per_kg * o.weight) AS est_freight_cost
    FROM orderlist AS o
    INNER JOIN rate_card AS rc
        ON  o.carrier          = rc.carrier
        AND o.origin_port      = rc.orig_port_cd
        AND o.destination_port = rc.dest_port_cd
        AND o.service_level    = rc.svc_cd
        AND o.weight BETWEEN rc.minm_wgh_qty AND rc.max_wgh_qty
    WHERE o.weight > 0
),

order_cohorts AS (
    -- Data-driven quartiles and terciles keep cohorts balanced without hard-coded cutoffs
    SELECT
        po.order_id,
        po.origin_port,
        po.destination_port,
        po.weight,
        po.est_freight_cost,
        CONCAT('W', NTILE(4) OVER (ORDER BY po.weight))            AS weight_bracket,
        CONCAT('P', NTILE(3) OVER (ORDER BY po.rate_per_kg))       AS rate_tier,
        CASE
            WHEN po.contract_transit_days <= 2 THEN 'SHORT'
            WHEN po.contract_transit_days <= 4 THEN 'MEDIUM'
            ELSE 'LONG'
        END                                                         AS distance_cohort
    FROM priced_orders AS po
),

cohort_cost AS (
    -- Cost per kg for every weight, price and distance combination
    SELECT
        oc.weight_bracket,
        oc.rate_tier,
        oc.distance_cohort,
        COUNT(*)                                                    AS orders,
        COUNT(DISTINCT CONCAT(oc.origin_port, '>', oc.destination_port)) AS lanes,
        ROUND(SUM(oc.weight), 2)                                    AS total_weight_kg,
        ROUND(SUM(oc.est_freight_cost), 2)                          AS total_cost,
        SUM(oc.est_freight_cost) / NULLIF(SUM(oc.weight), 0)        AS cost_per_kg
    FROM order_cohorts AS oc
    GROUP BY
        oc.weight_bracket,
        oc.rate_tier,
        oc.distance_cohort
),

cohort_benchmark AS (
    -- Weighted benchmark per weight bracket, share of total spend and inefficiency rank
    SELECT
        cc.weight_bracket,
        cc.rate_tier,
        cc.distance_cohort,
        cc.orders,
        cc.lanes,
        cc.total_weight_kg,
        cc.total_cost,
        ROUND(cc.cost_per_kg, 4)                                    AS cost_per_kg,
        ROUND(SUM(cc.total_cost) OVER (PARTITION BY cc.weight_bracket)
              / NULLIF(SUM(cc.total_weight_kg) OVER (PARTITION BY cc.weight_bracket), 0), 4) AS bracket_cost_per_kg,
        ROUND(100.0 * cc.total_cost / SUM(cc.total_cost) OVER (), 2) AS spend_share_pct,
        RANK() OVER (
            PARTITION BY cc.weight_bracket
            ORDER BY cc.cost_per_kg DESC
        )                                                           AS inefficiency_rank
    FROM cohort_cost AS cc
)

SELECT
    cb.weight_bracket,
    cb.rate_tier,
    cb.distance_cohort,
    cb.orders,
    cb.lanes,
    cb.total_weight_kg,
    cb.total_cost,
    cb.cost_per_kg,
    cb.bracket_cost_per_kg,
    ROUND(100.0 * (cb.cost_per_kg - cb.bracket_cost_per_kg) / NULLIF(cb.bracket_cost_per_kg, 0), 2) AS cost_vs_bracket_pct,
    cb.spend_share_pct,
    cb.inefficiency_rank,
    CASE
        WHEN cb.cost_per_kg > 1.25 * cb.bracket_cost_per_kg THEN 'COST INEFFICIENT'
        WHEN cb.cost_per_kg < 0.75 * cb.bracket_cost_per_kg THEN 'COST EFFICIENT'
        ELSE 'IN LINE'
    END                                                             AS efficiency_flag
FROM cohort_benchmark AS cb
ORDER BY
    cb.weight_bracket,
    cb.inefficiency_rank;