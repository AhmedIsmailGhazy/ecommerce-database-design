-- E-Commerce Database Design | PostgreSQL 17
-- 02_sample_data.sql
-- Run on ecommerce_db AFTER database/01_schema.sql.
-- DEMO DATA ONLY. The placeholder password_hash is NOT a valid password hash.
-- Do not use these records for authentication, and never use real credentials in seeds.
-- Designed to be safe to rerun: existing seed records are left in place.

BEGIN;

-- 1) Customers
INSERT INTO public.customers (first_name, last_name, email, password_hash)
VALUES
    ('Demo', 'Ahmed', 'demo.ahmed@example.invalid', 'DEMO_ONLY_NOT_FOR_AUTHENTICATION'),
    ('Demo', 'Sara',  'demo.sara@example.invalid',  'DEMO_ONLY_NOT_FOR_AUTHENTICATION')
ON CONFLICT (email) DO NOTHING;

-- 2) Categories
INSERT INTO public.categories (name, description)
VALUES
    ('Demo Electronics', 'Demo electronic products'),
    ('Demo Accessories', 'Demo accessories')
ON CONFLICT (name) DO NOTHING;

-- 3) Products, using category IDs resolved from their unique names
INSERT INTO public.products (category_id, sku, name, description, price)
VALUES
    ((SELECT category_id FROM public.categories WHERE name = 'Demo Electronics'),
     'DEMO-LAPTOP-001', 'Demo Laptop', 'Laptop for SQL exercises', 4200.00),
    ((SELECT category_id FROM public.categories WHERE name = 'Demo Accessories'),
     'DEMO-MOUSE-001', 'Demo Mouse', 'Wireless mouse', 120.00),
    ((SELECT category_id FROM public.categories WHERE name = 'Demo Electronics'),
     'DEMO-MONITOR-001', 'Demo Monitor', '27-inch monitor', 900.00)
ON CONFLICT (sku) DO NOTHING;

-- 4) Initial stock; does not overwrite existing stock on reruns
INSERT INTO public.inventory (product_id, quantity_available)
SELECT p.product_id, seed.quantity
FROM (VALUES
    ('DEMO-LAPTOP-001', 15),
    ('DEMO-MOUSE-001', 50),
    ('DEMO-MONITOR-001', 20)
) AS seed(sku, quantity)
JOIN public.products p ON p.sku = seed.sku
ON CONFLICT (product_id) DO NOTHING;

-- 5) Sample orders. PENDING does not imply stock reservation or recognized revenue.
INSERT INTO public.orders (customer_id, order_number, status)
VALUES
    ((SELECT customer_id FROM public.customers WHERE email = 'demo.ahmed@example.invalid'),
      'DEMO-ORD-001', 'PENDING'),
    ((SELECT customer_id FROM public.customers WHERE email = 'demo.sara@example.invalid'),
      'DEMO-ORD-002', 'PENDING')
ON CONFLICT (order_number) DO NOTHING;

-- 6) Order items with unit_price snapshots at purchase time
INSERT INTO public.order_items (order_id, product_id, quantity, unit_price)
SELECT o.order_id, p.product_id, seed.quantity, seed.unit_price
FROM (VALUES
    ('DEMO-ORD-001', 'DEMO-LAPTOP-001', 1, 4200.00::numeric),
    ('DEMO-ORD-001', 'DEMO-MOUSE-001',  2, 120.00::numeric),
    ('DEMO-ORD-002', 'DEMO-MONITOR-001',1, 900.00::numeric)
) AS seed(order_number, sku, quantity, unit_price)
JOIN public.orders o ON o.order_number = seed.order_number
JOIN public.products p ON p.sku = seed.sku
ON CONFLICT (order_id, product_id) DO NOTHING;

-- 7) Maintain totals for these demo orders in this seed transaction.
-- In a real checkout flow this logic must be enforced for EVERY order-item change.
UPDATE public.orders o
SET total_amount = amounts.total
FROM (
    SELECT oi.order_id, SUM(oi.quantity * oi.unit_price) AS total
    FROM public.order_items oi
    JOIN public.orders ord ON ord.order_id = oi.order_id
    WHERE ord.order_number IN ('DEMO-ORD-001', 'DEMO-ORD-002')
    GROUP BY oi.order_id
) AS amounts
WHERE o.order_id = amounts.order_id;

COMMIT;

-- 8) Verification / display
SELECT o.order_number,
       c.email AS customer_email,
       o.status,
       o.total_amount,
       COUNT(oi.order_item_id) AS line_count,
       SUM(oi.quantity * oi.unit_price) AS calculated_total
FROM public.orders o
JOIN public.customers c ON c.customer_id = o.customer_id
JOIN public.order_items oi ON oi.order_id = o.order_id
WHERE o.order_number IN ('DEMO-ORD-001', 'DEMO-ORD-002')
GROUP BY o.order_id, o.order_number, c.email, o.status, o.total_amount
ORDER BY o.order_number;
