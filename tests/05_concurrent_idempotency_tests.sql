
-- ============================================================
-- PostgreSQL 17 | E-Commerce Database Design
-- File: tests/05_concurrent_idempotency_tests.sql
--
-- MANUAL TWO-SESSION CONCURRENCY TEST
--
-- Purpose:
-- Verify transaction-level advisory locks protect checkout
-- operations that share the same order_number.
--
-- Requirements:
--   database/06_multi_product_checkout.sql
--   database/07_idempotent_checkout.sql
--   Two independent pgAdmin Query Tool connections
--   Seeded demo data
--
-- IMPORTANT:
-- Execute each step individually in the specified session.
-- Do NOT execute all steps as a single SQL script.
-- Run against a DEVELOPMENT database only.
--
-- This test uses ROLLBACK in both sessions so that no
-- permanent orders or stock deductions remain.
-- ============================================================


-- ============================================================
-- STEP 1: Verify test environment
-- Run in either Session A or Session B.
-- ============================================================

SELECT
    current_database() AS database_name,
    pg_backend_pid() AS backend_pid,
    to_regprocedure(
        'public.create_idempotent_checkout(bigint,character varying,jsonb)'
    ) AS checkout_function;


-- ============================================================
-- STEP 2: SESSION A - Create first checkout
--
-- Execute only the SQL between START and END.
-- Keep transaction OPEN after the SELECT.
-- Do NOT COMMIT or ROLLBACK yet.
-- ============================================================

/*
-- SESSION A START

BEGIN;

SELECT *
FROM public.create_idempotent_checkout(
    (
        SELECT customer_id
        FROM public.customers
        WHERE email = 'demo.ahmed@example.invalid'
    ),
    'IDEMPOTENCY-CONCURRENT-TEST-001',
    jsonb_build_array(
        jsonb_build_object(
            'product_id',
            (
                SELECT product_id
                FROM public.products
                WHERE sku = 'DEMO-LAPTOP-001'
            ),
            'quantity', 1
        ),
        jsonb_build_object(
            'product_id',
            (
                SELECT product_id
                FROM public.products
                WHERE sku = 'DEMO-MOUSE-001'
            ),
            'quantity', 2
        )
    )
);

-- SESSION A END

-- Expected:
-- created_total      = 4440.00
-- created_item_count = 2
-- Transaction remains OPEN.
*/


-- ============================================================
-- STEP 3: SESSION B - Concurrent retry
--
-- Execute while Session A transaction is still OPEN.
-- The retry uses exactly the same order_number and items.
-- ============================================================

/*
-- SESSION B START

BEGIN;

SET LOCAL lock_timeout = '5s';

SELECT *
FROM public.create_idempotent_checkout(
    (
        SELECT customer_id
        FROM public.customers
        WHERE email = 'demo.ahmed@example.invalid'
    ),
    'IDEMPOTENCY-CONCURRENT-TEST-001',
    jsonb_build_array(
        jsonb_build_object(
            'product_id',
            (
                SELECT product_id
                FROM public.products
                WHERE sku = 'DEMO-LAPTOP-001'
            ),
            'quantity', 1
        ),
        jsonb_build_object(
            'product_id',
            (
                SELECT product_id
                FROM public.products
                WHERE sku = 'DEMO-MOUSE-001'
            ),
            'quantity', 2
        )
    )
);

-- SESSION B END

-- Expected:
-- ERROR: canceling statement due to lock timeout
-- SQLSTATE: 55P03
--
-- This demonstrates that Session B waits for Session A's
-- transaction-level advisory lock.
*/


-- ============================================================
-- STEP 4: SESSION B - Clear failed transaction
-- ============================================================

/*
ROLLBACK;

-- Expected: ROLLBACK
*/


-- ============================================================
-- STEP 5: SESSION A - Undo test checkout
--
-- The transaction-level advisory lock is released.
-- The test order and inventory changes are rolled back.
-- ============================================================

/*
ROLLBACK;

-- Expected: ROLLBACK
*/


-- ============================================================
-- STEP 6: FINAL VERIFICATION
--
-- After both sessions have rolled back, execute this query.
-- Expected: no test orders or order items remain.
-- ============================================================

SELECT
    (
        SELECT COUNT(*)
        FROM public.orders
        WHERE order_number =
            'IDEMPOTENCY-CONCURRENT-TEST-001'
    ) AS remaining_test_orders,

    (
        SELECT quantity_available
        FROM public.inventory
        WHERE product_id = (
            SELECT product_id
            FROM public.products
            WHERE sku = 'DEMO-LAPTOP-001'
        )
    ) AS laptop_stock,

    (
        SELECT quantity_available
        FROM public.inventory
        WHERE product_id = (
            SELECT product_id
            FROM public.products
            WHERE sku = 'DEMO-MOUSE-001'
        )
    ) AS mouse_stock;


-- ============================================================
-- PASS CRITERIA
--
-- [PASS] Session A creates a two-item order.
-- [PASS] Session B receives SQLSTATE 55P03 while A holds lock.
-- [PASS] Session B can roll back its failed transaction.
-- [PASS] Session A rolls back its test order.
-- [PASS] No test order remains afterward.
-- [PASS] Inventory is unchanged from the initial baseline.
--
-- Additional committed-retry test:
--
-- A separate manual integration run also verified that:
--
-- 1. Session A committed an order.
-- 2. Session B retried the identical request.
-- 3. The existing order ID was returned.
-- 4. Only one order existed for the order_number.
-- 5. The committed test order was subsequently cleaned up.
--
-- Concurrent successful retries without a timeout should
-- be tested separately using two sessions and controlled
-- transaction completion.
-- ============================================================
