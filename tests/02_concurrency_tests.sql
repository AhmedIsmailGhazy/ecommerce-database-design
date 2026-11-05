-- PostgreSQL 17 | E-Commerce Database Design
-- File: tests/02_concurrency_tests.sql
-- Purpose: Reproducible MANUAL two-session checkout concurrency test.
-- Tested locally on 2026-11-05: row-lock timeout (55P03), then insufficient
-- stock (P0001) following Session A COMMIT; final stock = 5, one order only.
-- IMPORTANT: This is NOT a single-click automated test.
-- Run ONLY on a disposable development/test database.
-- Execute each section separately in the specified pgAdmin Query Tool session.
-- DO NOT execute this whole file with F5: session order and open transactions matter.
-- NOTE: Use the demo customer emails provided by database/02_sample_data.sql.
-- PREREQUISITE: database/05_checkout_function.sql is installed.
-- The fixture UPSERT resets the test product stock to 15. Do not execute
-- against production or a test product whose stock/orders must be preserved.
-- To rerun, remove any previous test orders only in a disposable database,
-- using the cleanup block below, then run the fixture again.
--
-- Expected:
-- Session A purchase 10 units => total 1000.00; keep transaction open.
-- Session B purchase 10 units => 55P03 lock timeout after 5s.
-- Session A COMMIT; Session B ROLLBACK and retry => P0001 insufficient stock.
-- Final: remaining_stock 5, successful_orders 1, rejected_orders 0,
--        purchased_quantity 10.
--
-- 0) OPTIONAL CLEANUP BEFORE RERUN (DISPOSABLE TEST DATABASE ONLY):
-- Run ONLY when no concurrent test transactions are open.
-- Uncomment all lines and run as a separate statement if you need a rerun.
-- BEGIN;
-- DELETE FROM public.order_items
-- WHERE order_id IN (
--   SELECT order_id FROM public.orders
--   WHERE order_number IN ('CONCURRENCY-A-001', 'CONCURRENCY-B-001')
-- );
-- DELETE FROM public.orders
-- WHERE order_number IN ('CONCURRENCY-A-001', 'CONCURRENCY-B-001');
-- COMMIT;
--
-- 1) FIXTURE SETUP (setup session; run once; separate from Session A/B).
-- Uncomment and execute the whole block below on a test database.
-- BEGIN;
-- WITH test_category AS (
--     INSERT INTO public.categories (name, description)
--     VALUES ('Concurrency Testing', 'Category for concurrency testing')
--     ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
--     RETURNING category_id
-- ), test_product AS (
--     INSERT INTO public.products (category_id, sku, name, price, is_active)
--     SELECT category_id, 'CONCURRENCY-TEST-001',
--            'Concurrency Test Product', 100.00, TRUE
--     FROM test_category
--     ON CONFLICT (sku) DO UPDATE
--     SET price = EXCLUDED.price, is_active = TRUE
--     RETURNING product_id
-- )
-- INSERT INTO public.inventory (product_id, quantity_available)
-- SELECT product_id, 15 FROM test_product
-- ON CONFLICT (product_id) DO UPDATE
-- SET quantity_available = 15, updated_at = CURRENT_TIMESTAMP;
-- COMMIT;
--
-- Verify fixture:
-- SELECT p.product_id, p.sku, p.price, i.quantity_available
-- FROM public.products p JOIN public.inventory i USING (product_id)
-- WHERE p.sku = 'CONCURRENCY-TEST-001';
--
-- 2) SESSION A: run in a FIRST Query Tool connection.
--    IMPORTANT: Do NOT COMMIT/ROLLBACK or close this session yet.
-- BEGIN;
-- SELECT * FROM public.create_checkout_order(
--     (SELECT customer_id FROM public.customers
--      WHERE email = 'demo.ahmed@example.invalid'),
--     (SELECT product_id FROM public.products
--      WHERE sku = 'CONCURRENCY-TEST-001'),
--     10,
--     'CONCURRENCY-A-001'
-- );
--
-- 3) SESSION B: open a SECOND, SEPARATE Query Tool connection.
--    Execute while Session A's transaction remains OPEN.
--    EXPECTED ERROR: SQLSTATE 55P03 (lock timeout).
-- BEGIN;
-- SET LOCAL lock_timeout = '5s';
-- SELECT * FROM public.create_checkout_order(
--     (SELECT customer_id FROM public.customers
--      WHERE email = 'demo.sara@example.invalid'),
--     (SELECT product_id FROM public.products
--      WHERE sku = 'CONCURRENCY-TEST-001'),
--     10,
--     'CONCURRENCY-B-001'
-- );
--
-- 4) SESSION A: after receiving B's lock-timeout error, run ONLY:
-- COMMIT;
--
-- 5) SESSION B: the previous lock_timeout aborts the transaction.
--    First execute ROLLBACK as a separate statement.
-- ROLLBACK;
--    Then execute this retry (expected ERROR SQLSTATE P0001):
-- SELECT * FROM public.create_checkout_order(
--     (SELECT customer_id FROM public.customers
--      WHERE email = 'demo.sara@example.invalid'),
--     (SELECT product_id FROM public.products
--      WHERE sku = 'CONCURRENCY-TEST-001'),
--     10,
--     'CONCURRENCY-B-001'
-- );
--
-- 6) FINAL VERIFICATION: run in a fresh Query Tool connection.
--    This is the only executable statement in this file by default.
--    Expected for a completed fresh test: 5 | 1 | 0 | 10.
SELECT
    p.product_id,
    p.sku,
    i.quantity_available AS remaining_stock,
    (SELECT COUNT(*) FROM public.orders o
     WHERE o.order_number = 'CONCURRENCY-A-001') AS successful_orders,
    (SELECT COUNT(*) FROM public.orders o
     WHERE o.order_number = 'CONCURRENCY-B-001') AS rejected_orders,
    (SELECT COALESCE(SUM(oi.quantity), 0)
     FROM public.order_items oi
     JOIN public.orders o ON o.order_id = oi.order_id
     WHERE o.order_number = 'CONCURRENCY-A-001') AS purchased_quantity
FROM public.products p
JOIN public.inventory i ON i.product_id = p.product_id
WHERE p.sku = 'CONCURRENCY-TEST-001';
