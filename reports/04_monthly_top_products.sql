-- E-Commerce Database Design | PostgreSQL 17
-- Report: Monthly Top Ordered Products
-- File: reports/04_monthly_top_products.sql
-- Purpose: Rank products by ordered quantity in the current UTC calendar month.
-- Status rule: Exclude CANCELLED; PENDING/CONFIRMED/SHIPPED/DELIVERED are included.
-- Thus total_order_value is order line value, NOT recognized revenue.
-- For delivered-only sales, replace o.status <> 'CANCELLED' with o.status = 'DELIVERED'.

SELECT
    p.product_id,
    p.sku,
    p.name AS product_name,
    SUM(oi.quantity) AS total_quantity,
    SUM(oi.quantity * oi.unit_price) AS total_order_value,
    COUNT(DISTINCT o.order_id) AS total_orders
FROM public.products AS p
JOIN public.order_items AS oi
    ON oi.product_id = p.product_id
JOIN public.orders AS o
    ON o.order_id = oi.order_id
WHERE o.placed_at >= (
    DATE_TRUNC('month', CURRENT_TIMESTAMP AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'
)
AND o.placed_at < (
    (DATE_TRUNC('month', CURRENT_TIMESTAMP AT TIME ZONE 'UTC') + INTERVAL '1 month')
    AT TIME ZONE 'UTC'
)
AND o.status <> 'CANCELLED'
GROUP BY p.product_id, p.sku, p.name
ORDER BY total_quantity DESC, total_order_value DESC, p.product_id;
