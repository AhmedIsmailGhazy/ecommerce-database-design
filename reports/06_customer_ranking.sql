-- E-Commerce Database Design | PostgreSQL 17
-- Report 06: Customer ranking by non-cancelled order value.
-- PENDING orders are included: order value is NOT recognized revenue.
-- Zero-order customers are included with a value of 0.
-- Ties share RANK and DENSE_RANK; ROW_NUMBER remains unique.

WITH customer_spending AS (
    SELECT
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
        c.email,
        COUNT(o.order_id) AS total_orders,
        COALESCE(SUM(o.total_amount), 0)::NUMERIC(14,2) AS total_order_value
    FROM public.customers AS c
    LEFT JOIN public.orders AS o
        ON o.customer_id = c.customer_id
       AND o.status <> 'CANCELLED'
    GROUP BY c.customer_id, c.first_name, c.last_name, c.email
)
SELECT
    customer_id,
    customer_name,
    email,
    total_orders,
    total_order_value,
    ROW_NUMBER() OVER (
        ORDER BY total_order_value DESC, customer_id ASC
    ) AS row_number,
    RANK() OVER (
        ORDER BY total_order_value DESC
    ) AS customer_rank,
    DENSE_RANK() OVER (
        ORDER BY total_order_value DESC
    ) AS dense_rank
FROM customer_spending
ORDER BY total_order_value DESC, customer_id ASC;
