-- E-Commerce Database Design | PostgreSQL 17
-- Report 05: Customers with more than SAR 300 in orders during the past month
-- Assumption: all order monetary values are denominated in SAR.
-- Metric: value of non-cancelled orders, including PENDING; NOT collected payments.
-- Period: rolling one-month interval ending at query execution time.
-- Threshold: strictly greater than SAR 300 (not >= 300).

SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    COUNT(o.order_id) AS total_orders,
    SUM(o.total_amount) AS total_order_value_sar
FROM public.customers AS c
JOIN public.orders AS o
    ON o.customer_id = c.customer_id
WHERE o.placed_at >= CURRENT_TIMESTAMP - INTERVAL '1 month'
  AND o.placed_at < CURRENT_TIMESTAMP
  AND o.status <> 'CANCELLED'
GROUP BY
    c.customer_id,
    c.first_name,
    c.last_name
HAVING SUM(o.total_amount) > 300.00
ORDER BY total_order_value_sar DESC, c.customer_id;
