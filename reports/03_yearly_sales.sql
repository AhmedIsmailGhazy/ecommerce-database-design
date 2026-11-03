-- E-Commerce Database Design | PostgreSQL 17
-- Report: Yearly Sales (UTC)
-- Revenue policy: count only DELIVERED orders as recognized revenue.
-- Revenue is assigned to the year of order placement, not year of delivery.
-- Read-only query: no data is modified.

SELECT
    EXTRACT(YEAR FROM o.placed_at AT TIME ZONE 'UTC')::integer AS sales_year,
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
GROUP BY EXTRACT(YEAR FROM o.placed_at AT TIME ZONE 'UTC')::integer
ORDER BY sales_year DESC;
