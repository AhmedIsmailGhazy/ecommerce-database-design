
-- ============================================================
-- PostgreSQL 17 | E-Commerce Database Design
-- Flyway Migration: V3__create_customer_summary_view.sql
--
-- Purpose:
-- Create a customer order summary view.
--
-- Prerequisite:
-- V1__create_schema.sql
--
-- Notes:
-- - Excludes cancelled orders.
-- - Includes PENDING orders.
-- - Total order value is NOT recognized revenue.
-- - No data modifications.
-- ============================================================

CREATE VIEW public.v_customer_order_summary AS
SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    c.email,
    COUNT(o.order_id) AS total_orders,
    COALESCE(
        SUM(o.total_amount),
        0
    )::NUMERIC(12,2) AS total_order_value
FROM public.customers AS c
LEFT JOIN public.orders AS o
    ON o.customer_id = c.customer_id
   AND o.status <> 'CANCELLED'
GROUP BY
    c.customer_id,
    c.first_name,
    c.last_name,
    c.email;
