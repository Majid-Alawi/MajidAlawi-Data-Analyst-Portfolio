-- 3. Logistics Efficiency: Avg Delivery Days by Region (longest delays first)
SELECT 
    region,
    ROUND(AVG(delivery_days), 2) AS avg_delivery_days
FROM fact_sales
GROUP BY region
ORDER BY avg_delivery_days DESC;