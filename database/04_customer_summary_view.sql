-- E-Commerce Database Design | PostgreSQL 17
-- Customer order summary: a regular VIEW, not a materialized copy.
-- Non-cancelled order values include PENDING orders, so these are NOT paid/revenue figures.
-- Safe to rerun after database/01_schema.sql.

CREATE OR REPLACE VIEW public.v_customer_order_summary AS
SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    c.email,
    COUNT(o.order_id) AS total_orders,
    COALESCE(SUM(o.total_amount), 0)::NUMERIC(12, 2) AS total_order_value
FROM public.customers AS c
LEFT JOIN public.orders AS o
    ON o.customer_id = c.customer_id
   AND o.status <> 'CANCELLED'
GROUP BY c.customer_id, c.first_name, c.last_name, c.email;

-- Verification
SELECT *
FROM public.v_customer_order_summary
ORDER BY total_order_value DESC, customer_id;
