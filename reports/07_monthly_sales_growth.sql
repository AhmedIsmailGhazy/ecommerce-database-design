-- E-Commerce Database Design | PostgreSQL 17
-- File: reports/07_monthly_sales_growth.sql
-- Monthly order-value trends using CTEs and LAG().
-- UTC month boundaries; includes non-cancelled orders, including PENDING.
-- Values are order amounts, NOT recognized revenue.
-- Read-only report. Months with no orders are included between first and last order month.

WITH month_bounds AS (
    SELECT
        date_trunc('month', MIN(placed_at AT TIME ZONE 'UTC'))::date AS first_month,
        date_trunc('month', MAX(placed_at AT TIME ZONE 'UTC'))::date AS last_month
    FROM public.orders
),
calendar_months AS (
    SELECT gs.month_start::date AS month_start
    FROM month_bounds b
    CROSS JOIN LATERAL generate_series(
        b.first_month::timestamp,
        b.last_month::timestamp,
        interval '1 month'
    ) AS gs(month_start)
),
monthly_orders AS (
    SELECT
        date_trunc('month', placed_at AT TIME ZONE 'UTC')::date AS month_start,
        COUNT(*) FILTER (WHERE status <> 'CANCELLED') AS order_count,
        COALESCE(SUM(total_amount) FILTER (WHERE status <> 'CANCELLED'), 0)::numeric(14,2)
            AS order_value,
        COALESCE(SUM(total_amount) FILTER (WHERE status = 'DELIVERED'), 0)::numeric(14,2)
            AS delivered_order_value
    FROM public.orders
    GROUP BY 1
),
monthly_summary AS (
    SELECT
        c.month_start,
        COALESCE(m.order_count, 0) AS order_count,
        COALESCE(m.order_value, 0)::numeric(14,2) AS order_value,
        COALESCE(m.delivered_order_value, 0)::numeric(14,2) AS delivered_order_value
    FROM calendar_months c
    LEFT JOIN monthly_orders m USING (month_start)
),
with_previous AS (
    SELECT
        *,
        LAG(order_value) OVER (ORDER BY month_start) AS previous_month_value
    FROM monthly_summary
)
SELECT
    month_start,
    order_count,
    order_value,
    delivered_order_value,
    previous_month_value,
    (order_value - previous_month_value)::numeric(14,2) AS month_over_month_change,
    CASE
        WHEN previous_month_value IS NULL OR previous_month_value = 0 THEN NULL
        ELSE ROUND(100.0 * (order_value - previous_month_value) / previous_month_value, 2)
    END AS growth_percent
FROM with_previous
ORDER BY month_start;
