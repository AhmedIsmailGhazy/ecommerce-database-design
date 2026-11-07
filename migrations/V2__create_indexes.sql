
-- ============================================================
-- PostgreSQL 17 | E-Commerce Database Design
-- Flyway Migration: V2__create_indexes.sql
-- Purpose: Create indexes supporting common access patterns.
-- Prerequisite: V1__create_schema.sql
--
-- PostgreSQL automatically creates indexes for primary keys
-- and unique constraints defined in V1.
-- ============================================================

-- Filter products by category
CREATE INDEX idx_products_category_id
    ON public.products (category_id);

-- Retrieve orders for a customer
CREATE INDEX idx_orders_customer_id
    ON public.orders (customer_id);

-- Filter and sort orders by placement date
CREATE INDEX idx_orders_placed_at
    ON public.orders (placed_at);

-- Find order items belonging to a product
CREATE INDEX idx_order_items_product_id
    ON public.order_items (product_id);
