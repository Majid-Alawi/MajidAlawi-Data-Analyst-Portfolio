-- 4. Segment Value: Avg Customer Rating and Customer Age by Segment
SELECT 
    customer_segment,
    ROUND(AVG(customer_rating), 2) AS avg_customer_rating,
    ROUND(AVG(customer_age), 1)    AS avg_customer_age
FROM fact_sales
GROUP BY customer_segment
ORDER BY avg_customer_rating DESC;