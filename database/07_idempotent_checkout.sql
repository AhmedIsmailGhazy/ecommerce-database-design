
-- PostgreSQL 17 | E-Commerce Database Design
-- File: database/07_idempotent_checkout.sql
-- A safe retry wrapper around database/06_multi_product_checkout.sql.
-- Requires UNIQUE (order_number) on public.orders.
-- Development/test deployment first. No table or constraint changes.
-- The transaction is owned by the caller; this function never commits.
-- Idempotency identity: globally unique order_number + exact customer/items payload.
-- A retry returns the original order without changing inventory.
-- Different payload with the same order number is rejected.

CREATE OR REPLACE FUNCTION public.create_idempotent_checkout(
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
    v_existing_order RECORD;
    v_requested_count BIGINT;
    v_distinct_count BIGINT;
BEGIN
    IF p_customer_id IS NULL THEN
        RAISE EXCEPTION 'Customer ID is required';
    END IF;

    IF p_order_number IS NULL OR btrim(p_order_number) = '' THEN
        RAISE EXCEPTION 'Order number is required';
    END IF;

    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array'
       OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Items must be a non-empty JSON array';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(p_items) AS x(item)
        WHERE jsonb_typeof(x.item) <> 'object'
           OR NOT (x.item ? 'product_id' AND x.item ? 'quantity')
    ) THEN
        RAISE EXCEPTION 'Each item must have product_id and quantity';
    END IF;

    -- Conversion errors for invalid IDs and quantities propagate.
    SELECT
        count(*),
        count(DISTINCT product_id)
    INTO
        v_requested_count,
        v_distinct_count
    FROM jsonb_to_recordset(p_items)
         AS x(product_id BIGINT, quantity INTEGER);

    IF EXISTS (
        SELECT 1
        FROM jsonb_to_recordset(p_items)
             AS x(product_id BIGINT, quantity INTEGER)
        WHERE product_id IS NULL
           OR quantity IS NULL
           OR quantity <= 0
    ) THEN
        RAISE EXCEPTION
            'Every item requires a product ID and positive quantity';
    END IF;

    IF v_requested_count <> v_distinct_count THEN
        RAISE EXCEPTION 'Duplicate product_id in checkout items';
    END IF;

    -- Serialize concurrent requests using the same order number.
    PERFORM pg_advisory_xact_lock(
        hashtextextended(p_order_number::text, 0)
    );

    SELECT
        o.order_id,
        o.order_number,
        o.customer_id,
        o.total_amount
    INTO v_existing_order
    FROM public.orders AS o
    WHERE o.order_number = p_order_number;

    IF FOUND THEN

        IF v_existing_order.customer_id <> p_customer_id THEN
            RAISE EXCEPTION
                'Idempotency conflict: order number belongs to a different customer';
        END IF;

        -- Compare product IDs and quantities, not prices.
        -- Historical prices can change after the original checkout.
        IF (
            SELECT count(*)
            FROM public.order_items
            WHERE order_id = v_existing_order.order_id
        ) <> v_requested_count

        OR EXISTS (
            SELECT 1
            FROM jsonb_to_recordset(p_items)
                 AS x(product_id BIGINT, quantity INTEGER)
            WHERE NOT EXISTS (
                SELECT 1
                FROM public.order_items AS oi
                WHERE oi.order_id = v_existing_order.order_id
                  AND oi.product_id = x.product_id
                  AND oi.quantity = x.quantity
            )
        ) THEN
            RAISE EXCEPTION
                'Idempotency conflict: existing order has different items';
        END IF;

        RETURN QUERY
        SELECT
            v_existing_order.order_id::BIGINT,
            v_existing_order.order_number::VARCHAR(50),
            v_existing_order.total_amount::NUMERIC(12,2),
            v_requested_count::INTEGER;

        RETURN;
    END IF;

    -- First attempt uses existing atomic multi-product checkout.
    RETURN QUERY
    SELECT
        m.created_order_id,
        m.created_order_number,
        m.created_total,
        m.created_item_count
    FROM public.create_multi_product_checkout(
        p_customer_id,
        p_order_number,
        p_items
    ) AS m;

END;
$function$;

-- Verify installation
SELECT to_regprocedure(
    'public.create_idempotent_checkout(bigint,character varying,jsonb)'
) AS idempotent_checkout_function;
