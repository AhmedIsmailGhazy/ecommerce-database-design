-- PostgreSQL 17 | E-Commerce Database Design
-- File: tests/01_checkout_tests.sql
-- Purpose: Repeatable smoke/regression tests for single-product checkout.
-- Run ONLY on a development/test copy of ecommerce_db.
-- Prerequisites: 01_schema.sql, 02_sample_data.sql, 05_checkout_function.sql.
-- All successful writes are rolled back. No permanent orders or stock deductions.
-- Expected: five "PASS" notices, then ROLLBACK.
-- Not a two-session/concurrency COMMIT test.

BEGIN;

DO $tests$
DECLARE
    v_customer_id BIGINT;
    v_product_id BIGINT;
    v_stock_before INTEGER;
    v_stock_after INTEGER;
    v_existing_order_number VARCHAR(50);
    v_test_order_number VARCHAR(50);
    v_created RECORD;
    v_got_expected_error BOOLEAN;
BEGIN
    SELECT customer_id INTO v_customer_id
    FROM public.customers
    WHERE email = 'demo.ahmed@example.invalid';

    SELECT product_id INTO v_product_id
    FROM public.products
    WHERE sku = 'DEMO-LAPTOP-001' AND is_active = TRUE;

    IF v_customer_id IS NULL OR v_product_id IS NULL THEN
        RAISE EXCEPTION 'Missing demo fixtures: run database/02_sample_data.sql';
    END IF;

    SELECT quantity_available INTO v_stock_before
    FROM public.inventory WHERE product_id = v_product_id;

    IF v_stock_before IS NULL OR v_stock_before < 1 THEN
        RAISE EXCEPTION 'Demo laptop must have at least one available unit';
    END IF;

    SELECT order_number INTO v_existing_order_number
    FROM public.orders
    WHERE order_number = 'DEMO-ORD-001';

    IF v_existing_order_number IS NULL THEN
        RAISE EXCEPTION 'Missing seed order DEMO-ORD-001';
    END IF;

    v_test_order_number := 'CHECKOUT-TEST-' || txid_current()::TEXT;

    -- 1) Successful checkout in a PL/pgSQL subtransaction.
    -- The deliberate error rolls back the inserted order and stock deduction.
    v_got_expected_error := FALSE;
    BEGIN
        SELECT * INTO v_created
        FROM public.create_checkout_order(
            v_customer_id, v_product_id, 1, v_test_order_number
        );

        IF v_created.created_order_id IS NULL
           OR v_created.created_order_number <> v_test_order_number
           OR v_created.created_total <> (
               SELECT price FROM public.products WHERE product_id = v_product_id
           ) THEN
            RAISE EXCEPTION 'Successful checkout returned unexpected values';
        END IF;

        IF (SELECT quantity_available FROM public.inventory
            WHERE product_id = v_product_id) <> v_stock_before - 1 THEN
            RAISE EXCEPTION 'Successful checkout did not deduct exactly one unit';
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'PZ001', MESSAGE = 'Intentional test rollback';
    EXCEPTION
        WHEN SQLSTATE 'PZ001' THEN
            v_got_expected_error := TRUE;
    END;

    IF NOT v_got_expected_error THEN
        RAISE EXCEPTION 'Expected test rollback did not occur';
    END IF;
    RAISE NOTICE 'PASS 1/5: Successful checkout returns correct values and deducts stock';

    -- 2) Verify the successful case left no permanent changes.
    SELECT quantity_available INTO v_stock_after
    FROM public.inventory WHERE product_id = v_product_id;

    IF v_stock_after <> v_stock_before
       OR EXISTS (SELECT 1 FROM public.orders WHERE order_number = v_test_order_number) THEN
        RAISE EXCEPTION 'Rollback did not restore the database';
    END IF;
    RAISE NOTICE 'PASS 2/5: Rollback restores stock and removes test order';

    -- 3) Insufficient-stock rejection.
    v_got_expected_error := FALSE;
    BEGIN
        PERFORM * FROM public.create_checkout_order(
            v_customer_id, v_product_id, v_stock_before + 1,
            'CHECKOUT-INSUFFICIENT-' || txid_current()::TEXT
        );
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM NOT LIKE 'Insufficient stock%' THEN
                RAISE;
            END IF;
            v_got_expected_error := TRUE;
    END;
    IF NOT v_got_expected_error THEN
        RAISE EXCEPTION 'Insufficient-stock test should have failed';
    END IF;
    RAISE NOTICE 'PASS 3/5: Insufficient stock is rejected';

    -- 4) Existing order_number must be rejected without reducing stock.
    v_got_expected_error := FALSE;
    BEGIN
        PERFORM * FROM public.create_checkout_order(
            v_customer_id, v_product_id, 1, v_existing_order_number
        );
    EXCEPTION
        WHEN unique_violation THEN
            v_got_expected_error := TRUE;
    END;
    IF NOT v_got_expected_error THEN
        RAISE EXCEPTION 'Duplicate order number should raise SQLSTATE 23505';
    END IF;
    RAISE NOTICE 'PASS 4/5: Duplicate order number is rejected (23505)';

    -- 5) Invalid quantity is rejected; final stock is unchanged.
    v_got_expected_error := FALSE;
    BEGIN
        PERFORM * FROM public.create_checkout_order(
            v_customer_id, v_product_id, 0,
            'CHECKOUT-INVALID-' || txid_current()::TEXT
        );
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            IF SQLERRM <> 'Quantity must be greater than zero' THEN
                RAISE;
            END IF;
            v_got_expected_error := TRUE;
    END;
    IF NOT v_got_expected_error THEN
        RAISE EXCEPTION 'Zero quantity should have been rejected';
    END IF;

    IF (SELECT quantity_available FROM public.inventory
        WHERE product_id = v_product_id) <> v_stock_before THEN
        RAISE EXCEPTION 'Stock changed unexpectedly during rejected checkouts';
    END IF;
    RAISE NOTICE 'PASS 5/5: Invalid quantity rejected and stock unchanged';
END;
$tests$;

ROLLBACK;
