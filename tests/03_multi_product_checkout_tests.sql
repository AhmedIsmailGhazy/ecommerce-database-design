-- PostgreSQL 17 | E-Commerce Database Design
-- File: tests/03_multi_product_checkout_tests.sql
-- Purpose: Repeatable multi-product checkout success + atomic failure verification.
-- DEVELOPMENT/TEST DATABASE ONLY. Requires seeded demo data and
-- database/06_multi_product_checkout.sql installed.
-- Expected: PASS 1/3, PASS 2/3, PASS 3/3, then ROLLBACK.
-- Tests are self-checking. No permanent orders or inventory deductions.

BEGIN;

DO $tests$
DECLARE
    v_customer BIGINT;
    v_laptop BIGINT;
    v_mouse BIGINT;
    v_laptop_stock INTEGER;
    v_mouse_stock INTEGER;
    v_success RECORD;
    v_failed BOOLEAN := FALSE;
    v_success_order VARCHAR(50) := 'MULTI-REGRESSION-SUCCESS';
    v_failure_order VARCHAR(50) := 'MULTI-REGRESSION-FAIL';
BEGIN
    SELECT customer_id INTO v_customer FROM public.customers
    WHERE email = 'demo.ahmed@example.invalid';
    SELECT product_id INTO v_laptop FROM public.products
    WHERE sku = 'DEMO-LAPTOP-001';
    SELECT product_id INTO v_mouse FROM public.products
    WHERE sku = 'DEMO-MOUSE-001';

    IF v_customer IS NULL OR v_laptop IS NULL OR v_mouse IS NULL THEN
        RAISE EXCEPTION 'Required demo customer/products missing';
    END IF;
    SELECT quantity_available INTO v_laptop_stock FROM public.inventory WHERE product_id = v_laptop;
    SELECT quantity_available INTO v_mouse_stock FROM public.inventory WHERE product_id = v_mouse;
    IF v_laptop_stock < 1 OR v_mouse_stock < 2 OR v_laptop_stock IS NULL OR v_mouse_stock IS NULL THEN
        RAISE EXCEPTION 'Not enough demo stock for success test';
    END IF;
    IF EXISTS (SELECT 1 FROM public.orders WHERE order_number IN (v_success_order, v_failure_order)) THEN
        RAISE EXCEPTION 'Test order number already exists. Use clean test fixtures';
    END IF;

    -- Successful checkout is rolled back by the enclosing test transaction.
    SELECT * INTO v_success
    FROM public.create_multi_product_checkout(
        v_customer, v_success_order,
        jsonb_build_array(
            jsonb_build_object('product_id', v_laptop, 'quantity', 1),
            jsonb_build_object('product_id', v_mouse, 'quantity', 2)
        )
    );

    IF v_success.created_order_number <> v_success_order
       OR v_success.created_total <> 4440.00
       OR v_success.created_item_count <> 2
       OR (SELECT count(*) FROM public.order_items WHERE order_id = v_success.created_order_id) <> 2
       OR (SELECT quantity_available FROM public.inventory WHERE product_id = v_laptop) <> v_laptop_stock - 1
       OR (SELECT quantity_available FROM public.inventory WHERE product_id = v_mouse) <> v_mouse_stock - 2 THEN
        RAISE EXCEPTION 'Success checkout result, items, or stock mismatch';
    END IF;
    RAISE NOTICE 'PASS 1/3: Two-product order, total, item rows, and deductions validated';

    -- Verify any successful partial steps are reversed if a later item fails.
    -- Product processing is sorted by ID; laptop is expected before mouse in demo seed.
    BEGIN
        PERFORM * FROM public.create_multi_product_checkout(
            v_customer, v_failure_order,
            jsonb_build_array(
                jsonb_build_object('product_id', v_laptop, 'quantity', 1),
                jsonb_build_object('product_id', v_mouse, 'quantity', 1000000)
            )
        );
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM NOT LIKE 'Insufficient stock%' THEN
            RAISE;
        END IF;
        v_failed := TRUE;
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'Failure case unexpectedly succeeded';
    END IF;
    RAISE NOTICE 'PASS 2/3: Insufficient-stock failure rejected';

    IF EXISTS (SELECT 1 FROM public.orders WHERE order_number = v_failure_order)
       OR (SELECT quantity_available FROM public.inventory WHERE product_id = v_laptop) <> v_laptop_stock - 1
       OR (SELECT quantity_available FROM public.inventory WHERE product_id = v_mouse) <> v_mouse_stock - 2 THEN
        RAISE EXCEPTION 'Atomic rollback failed: failed order or leaked stock deduction';
    END IF;
    RAISE NOTICE 'PASS 3/3: Failed checkout left no order and no further stock deductions';
END;
$tests$;

ROLLBACK;
