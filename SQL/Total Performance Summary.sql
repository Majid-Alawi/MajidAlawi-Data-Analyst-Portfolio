-- 1. Total Performance Summary: Revenue, Profit, Margin %, Order Volume
SELECT 
    ROUND(SUM(net_sales), 2)                                  AS total_revenue,
    ROUND(SUM(profit), 2)                                     AS total_profit,
    ROUND((SUM(profit) / NULLIF(SUM(net_sales), 0)) * 100, 2) AS profit_margin_pct,
    COUNT(DISTINCT order_id)                                  AS total_orders
FROM fact_sales;