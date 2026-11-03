-- E-Commerce Database Design | PostgreSQL 17
-- File: database/01_schema.sql
-- Purpose: Initialize the six core relational tables in an EMPTY ecommerce_db database.
-- Prerequisite: Connect to the intended database before executing.
-- IMPORTANT: Run on a fresh/empty database. CREATE TABLE IF NOT EXISTS will not
-- validate or migrate an existing table's structure. Do not use it as a migration.
-- No DROP, TRUNCATE, or DELETE statements are included.

BEGIN;

-- 1. CUSTOMERS
CREATE TABLE IF NOT EXISTS public.customers (
    customer_id BIGINT GENERATED ALWAYS AS IDENTITY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_customers PRIMARY KEY (customer_id),
    CONSTRAINT uq_customers_email UNIQUE (email)
);

-- 2. CATEGORIES
CREATE TABLE IF NOT EXISTS public.categories (
    category_id BIGINT GENERATED ALWAYS AS IDENTITY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    CONSTRAINT pk_categories PRIMARY KEY (category_id),
    CONSTRAINT uq_categories_name UNIQUE (name)
);

-- 3. PRODUCTS: category must exist before product creation.
CREATE TABLE IF NOT EXISTS public.products (
    product_id BIGINT GENERATED ALWAYS AS IDENTITY,
    category_id BIGINT NOT NULL,
    sku VARCHAR(80) NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price NUMERIC(12,2) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_products PRIMARY KEY (product_id),
    CONSTRAINT uq_products_sku UNIQUE (sku),
    CONSTRAINT chk_products_price CHECK (price >= 0),
    CONSTRAINT fk_products_categories FOREIGN KEY (category_id)
        REFERENCES public.categories(category_id) ON DELETE RESTRICT
);

-- 4. INVENTORY: product_id is both primary and foreign key.
-- This guarantees at most one inventory row per product, not that every product
-- already has one. Product creation must also create its inventory row.
CREATE TABLE IF NOT EXISTS public.inventory (
    product_id BIGINT NOT NULL,
    quantity_available INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_inventory PRIMARY KEY (product_id),
    CONSTRAINT fk_inventory_products FOREIGN KEY (product_id)
        REFERENCES public.products(product_id) ON DELETE RESTRICT,
    CONSTRAINT chk_inventory_quantity CHECK (quantity_available >= 0)
);

-- 5. ORDERS: one customer may have many orders.
CREATE TABLE IF NOT EXISTS public.orders (
    order_id BIGINT GENERATED ALWAYS AS IDENTITY,
    customer_id BIGINT NOT NULL,
    order_number VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    placed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    CONSTRAINT pk_orders PRIMARY KEY (order_id),
    CONSTRAINT uq_orders_order_number UNIQUE (order_number),
    CONSTRAINT fk_orders_customers FOREIGN KEY (customer_id)
        REFERENCES public.customers(customer_id) ON DELETE RESTRICT,
    CONSTRAINT chk_orders_total_amount CHECK (total_amount >= 0),
    CONSTRAINT chk_orders_status CHECK (
        status IN ('PENDING', 'CONFIRMED', 'SHIPPED', 'DELIVERED', 'CANCELLED')
    )
);

-- 6. ORDER_ITEMS: resolves the many-to-many orders/products relationship.
CREATE TABLE IF NOT EXISTS public.order_items (
    order_item_id BIGINT GENERATED ALWAYS AS IDENTITY,
    order_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price NUMERIC(12,2) NOT NULL,
    CONSTRAINT pk_order_items PRIMARY KEY (order_item_id),
    CONSTRAINT fk_order_items_orders FOREIGN KEY (order_id)
        REFERENCES public.orders(order_id) ON DELETE RESTRICT,
    CONSTRAINT fk_order_items_products FOREIGN KEY (product_id)
        REFERENCES public.products(product_id) ON DELETE RESTRICT,
    CONSTRAINT uq_order_items_order_product UNIQUE (order_id, product_id),
    CONSTRAINT chk_order_items_quantity CHECK (quantity > 0),
    CONSTRAINT chk_order_items_unit_price CHECK (unit_price >= 0)
);

COMMIT;

-- Follow-up design work (not implemented in this schema):
-- 1. Keep orders.total_amount in sync with order_items in a transaction.
-- 2. Keep inventory.updated_at current on updates.
-- 3. Add performance indexes after analyzing expected queries.
-- 4. Enforce valid order-status transitions at the service/DB layer.
