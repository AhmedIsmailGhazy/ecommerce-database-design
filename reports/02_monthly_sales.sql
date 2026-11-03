-- E-Commerce Database Design | PostgreSQL 17
-- Report: Monthly Sales (UTC)
-- Revenue policy: count only DELIVERED orders as recognized revenue.
-- Revenue is assigned to the month of order placement, not month of delivery.
-- Read-only query: no data is modified.

SELECT
    DATE_TRUNC('month', o.placed_at AT TIME ZONE 'UTC')::date AS sales_month,
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
GROUP BY DATE_TRUNC('month', o.placed_at AT TIME ZONE 'UTC')::date
ORDER BY sales_month DESC;
