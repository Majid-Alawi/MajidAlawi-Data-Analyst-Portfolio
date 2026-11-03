-- 2. Channel Insights: Top Sales Channels by Net Sales
SELECT 
    sales_channel,
    ROUND(SUM(net_sales), 2) AS total_net_sales
FROM fact_sales
GROUP BY sales_channel
ORDER BY total_net_sales DESC;