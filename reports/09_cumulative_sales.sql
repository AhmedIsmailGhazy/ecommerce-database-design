-- E-Commerce Database Design | PostgreSQL 17
-- Report 09: Cumulative Sales (Order Value)
-- Aggregate non-cancelled orders by UTC placement date and calculate
-- running totals using SUM() OVER.
-- This is order value, NOT recognized revenue; PENDING orders are included.
-- Only days containing at least one non-cancelled order are shown.

WITH daily_sales AS (
    SELECT
        (o.placed_at AT TIME ZONE 'UTC')::DATE AS order_date,
        COUNT(*) AS total_orders,
        SUM(o.total_amount) AS daily_order_value
    FROM public.orders o
    WHERE o.status <> 'CANCELLED'
    GROUP BY (o.placed_at AT TIME ZONE 'UTC')::DATE
)
SELECT
    order_date,
    total_orders,
    daily_order_value,
    SUM(total_orders) OVER (
        ORDER BY order_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_orders,
    SUM(daily_order_value) OVER (
        ORDER BY order_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_order_value
FROM daily_sales
ORDER BY order_date;
