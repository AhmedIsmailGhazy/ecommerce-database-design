-- E-Commerce Database Design | PostgreSQL 17
-- Report: Daily Sales (UTC)
-- Revenue policy for this demo: only DELIVERED orders count as recognized revenue.
-- PENDING, CONFIRMED, SHIPPED, and CANCELLED are excluded from recognized revenue.
-- Reporting by order PLACEMENT date, not delivery date (delivery timestamp is not stored).
-- Read-only query: no data is modified.

SELECT
    (o.placed_at AT TIME ZONE 'UTC')::date AS sales_date,
    COUNT(*) AS total_orders,
    COUNT(*) FILTER (WHERE o.status = 'PENDING') AS pending_orders,
    COUNT(*) FILTER (WHERE o.status = 'DELIVERED') AS delivered_orders,
    COUNT(*) FILTER (WHERE o.status = 'CANCELLED') AS cancelled_orders,
    COALESCE(SUM(o.total_amount), 0)::numeric(18,2) AS total_order_value,
    COALESCE(
        SUM(o.total_amount) FILTER (WHERE o.status = 'DELIVERED'),
        0
    )::numeric(18,2) AS recognized_revenue
FROM public.orders AS o
GROUP BY (o.placed_at AT TIME ZONE 'UTC')::date
ORDER BY sales_date DESC;
