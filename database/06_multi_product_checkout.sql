-- PostgreSQL 17 | E-Commerce Database Design
-- File: database/06_multi_product_checkout.sql
-- Multi-product, all-or-nothing checkout demonstration.
-- Run only in development first. Requires database/01_schema.sql.
-- Input example: '[{"product_id": 1, "quantity": 2}, {"product_id": 2, "quantity": 1}]'::jsonb
-- This is not an idempotent checkout API; external direct table writes may bypass safeguards.
-- Calling SELECT runs inside the caller's transaction. No COMMIT is issued here.

CREATE OR REPLACE FUNCTION public.create_multi_product_checkout(
    p_customer_id BIGINT,
    p_order_number VARCHAR(50),
    p_items JSONB
)
RETURNS TABLE (
    created_order_id BIGINT,
    created_order_number VARCHAR(50),
    created_total NUMERIC(12,2),
    created_item_count INTEGER
)
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_item RECORD;
    v_price NUMERIC(12,2);
    v_order_id BIGINT;
    v_total NUMERIC(12,2) := 0;
    v_item_count INTEGER := 0;
    v_expected_count INTEGER;
    v_distinct_count INTEGER;
BEGIN
    IF p_customer_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.customers WHERE customer_id = p_customer_id
    ) THEN
        RAISE EXCEPTION 'Customer not found';
    END IF;

    IF p_order_number IS NULL OR btrim(p_order_number) = '' THEN
        RAISE EXCEPTION 'Order number is required';
    END IF;

    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array'
       OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Items must be a non-empty JSON array';
    END IF;

    -- Treat any malformed item as an error rather than silently dropping it.
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_items) AS x(item)
        WHERE jsonb_typeof(x.item) <> 'object'
           OR NOT (x.item ? 'product_id' AND x.item ? 'quantity')
    ) THEN
        RAISE EXCEPTION 'Each item must have product_id and quantity';
    END IF;

    -- jsonb_to_recordset enforces BIGINT/INTEGER casts; malformed values fail.
    SELECT count(*), count(DISTINCT product_id)
      INTO v_expected_count, v_distinct_count
      FROM jsonb_to_recordset(p_items) AS x(product_id BIGINT, quantity INTEGER);

    IF EXISTS (
        SELECT 1 FROM jsonb_to_recordset(p_items) AS x(product_id BIGINT, quantity INTEGER)
        WHERE product_id IS NULL OR quantity IS NULL OR quantity <= 0
    ) THEN
        RAISE EXCEPTION 'Every item requires a product ID and positive quantity';
    END IF;

    IF v_expected_count <> v_distinct_count THEN
        RAISE EXCEPTION 'Duplicate product_id in checkout items';
    END IF;

    -- Locks are acquired in ascending product ID order, reducing deadlock risk.
    -- Each lock protects price/active status; conditional UPDATE protects stock.
    FOR v_item IN
        SELECT product_id, quantity
        FROM jsonb_to_recordset(p_items) AS x(product_id BIGINT, quantity INTEGER)
        ORDER BY product_id
    LOOP
        SELECT p.price INTO v_price
        FROM public.products p
        WHERE p.product_id = v_item.product_id AND p.is_active = TRUE
        FOR SHARE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product % not found or inactive', v_item.product_id;
        END IF;

        UPDATE public.inventory
        SET quantity_available = quantity_available - v_item.quantity,
            updated_at = CURRENT_TIMESTAMP
        WHERE product_id = v_item.product_id
          AND quantity_available >= v_item.quantity;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Insufficient stock for product %', v_item.product_id;
        END IF;

        -- Create the order only after stock updates have passed so far.
        IF v_order_id IS NULL THEN
            INSERT INTO public.orders(customer_id, order_number, status)
            VALUES (p_customer_id, p_order_number, 'PENDING')
            RETURNING order_id INTO v_order_id;
        END IF;

        INSERT INTO public.order_items(order_id, product_id, quantity, unit_price)
        VALUES (v_order_id, v_item.product_id, v_item.quantity, v_price);

        v_total := v_total + (v_item.quantity * v_price);
        v_item_count := v_item_count + 1;
    END LOOP;

    UPDATE public.orders SET total_amount = v_total WHERE order_id = v_order_id;
    RETURN QUERY SELECT v_order_id, p_order_number, v_total, v_item_count;
END;
$function$;

SELECT to_regprocedure(
    'public.create_multi_product_checkout(bigint,character varying,jsonb)'
) AS multi_product_checkout_function;
