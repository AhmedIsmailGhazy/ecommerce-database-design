
-- PostgreSQL 17 | DEVELOPMENT/TEST DATABASE ONLY
-- File: tests/04_idempotent_checkout_tests.sql
-- Dependencies:
-- database/06_multi_product_checkout.sql
-- database/07_idempotent_checkout.sql
-- Seeded demo data.
-- Expected: PASS 1/4 .. PASS 4/4, then ROLLBACK.

BEGIN;

DO $tests$
DECLARE
    v_customer BIGINT;
    v_laptop BIGINT;
    v_mouse BIGINT;
    v_laptop_before INTEGER;
    v_mouse_before INTEGER;

    v_first RECORD;
    v_retry RECORD;
    v_conflict BOOLEAN;

    v_order_number VARCHAR(50)
        := 'IDEMPOTENCY-REGRESSION-001';

BEGIN

    SELECT customer_id
    INTO v_customer
    FROM public.customers
    WHERE email = 'demo.ahmed@example.invalid';

    SELECT product_id
    INTO v_laptop
    FROM public.products
    WHERE sku = 'DEMO-LAPTOP-001';

    SELECT product_id
    INTO v_mouse
    FROM public.products
    WHERE sku = 'DEMO-MOUSE-001';

    SELECT quantity_available
    INTO v_laptop_before
    FROM public.inventory
    WHERE product_id = v_laptop;

    SELECT quantity_available
    INTO v_mouse_before
    FROM public.inventory
    WHERE product_id = v_mouse;

    IF v_customer IS NULL
       OR v_laptop IS NULL
       OR v_mouse IS NULL
       OR v_laptop_before IS NULL
       OR v_mouse_before IS NULL
       OR v_laptop_before < 1
       OR v_mouse_before < 2
    THEN
        RAISE EXCEPTION
            'Missing demo fixtures or insufficient test stock';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.orders
        WHERE order_number = v_order_number
    ) THEN
        RAISE EXCEPTION
            'Test order already exists; use clean test fixtures';
    END IF;

    -- TEST 1: Successful initial checkout

    SELECT *
    INTO v_first
    FROM public.create_idempotent_checkout(
        v_customer,
        v_order_number,
        jsonb_build_array(
            jsonb_build_object(
                'product_id', v_laptop,
                'quantity', 1
            ),
            jsonb_build_object(
                'product_id', v_mouse,
                'quantity', 2
            )
        )
    );

    IF v_first.created_total <> 4440.00
       OR v_first.created_item_count <> 2
    THEN
        RAISE EXCEPTION
            'First checkout totals incorrect';
    END IF;

    RAISE NOTICE
        'PASS 1/4: First checkout created two-item order';

    -- TEST 2: Retry the identical checkout.
    -- Reverse item order to verify semantic equality.

    SELECT *
    INTO v_retry
    FROM public.create_idempotent_checkout(
        v_customer,
        v_order_number,
        jsonb_build_array(
            jsonb_build_object(
                'product_id', v_mouse,
                'quantity', 2
            ),
            jsonb_build_object(
                'product_id', v_laptop,
                'quantity', 1
            )
        )
    );

    IF v_retry.created_order_id
            IS DISTINCT FROM v_first.created_order_id
       OR v_retry.created_total
            IS DISTINCT FROM v_first.created_total
       OR v_retry.created_item_count
            IS DISTINCT FROM v_first.created_item_count
       OR (
           SELECT count(*)
           FROM public.orders
           WHERE order_number = v_order_number
       ) <> 1
       OR (
           SELECT quantity_available
           FROM public.inventory
           WHERE product_id = v_laptop
       ) <> v_laptop_before - 1
       OR (
           SELECT quantity_available
           FROM public.inventory
           WHERE product_id = v_mouse
       ) <> v_mouse_before - 2
    THEN
        RAISE EXCEPTION
            'Retry created extra order or changed inventory';
    END IF;

    RAISE NOTICE
        'PASS 2/4: Exact retry returned same order without stock deduction';

    -- TEST 3: Same order number with different items.

    v_conflict := FALSE;

    BEGIN

        PERFORM *
        FROM public.create_idempotent_checkout(
            v_customer,
            v_order_number,
            jsonb_build_array(
                jsonb_build_object(
                    'product_id', v_laptop,
                    'quantity', 2
                )
            )
        );

    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN

            IF SQLERRM NOT LIKE 'Idempotency conflict:%' THEN
                RAISE;
            END IF;

            v_conflict := TRUE;
    END;

    IF NOT v_conflict THEN
        RAISE EXCEPTION
            'Changed payload was not rejected';
    END IF;

    RAISE NOTICE
        'PASS 3/4: Changed payload rejected';

    -- TEST 4: Ensure conflict did not change stock or order.

    IF (
        SELECT count(*)
        FROM public.orders
        WHERE order_number = v_order_number
    ) <> 1

    OR (
        SELECT count(*)
        FROM public.order_items
        WHERE order_id = v_first.created_order_id
    ) <> 2

    OR (
        SELECT quantity_available
        FROM public.inventory
        WHERE product_id = v_laptop
    ) <> v_laptop_before - 1

    OR (
        SELECT quantity_available
        FROM public.inventory
        WHERE product_id = v_mouse
    ) <> v_mouse_before - 2

    THEN
        RAISE EXCEPTION
            'Conflict affected order or inventory';
    END IF;

    RAISE NOTICE
        'PASS 4/4: Order and inventory unchanged after conflict';

END;
$tests$;

ROLLBACK;
