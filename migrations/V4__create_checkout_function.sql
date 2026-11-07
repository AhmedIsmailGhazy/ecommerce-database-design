
-- ============================================================
-- PostgreSQL 17 | E-Commerce Database Design
-- Flyway Migration: V4__create_checkout_function.sql
--
-- Purpose:
-- Create the atomic single-product checkout function.
--
-- Prerequisite:
-- V1__create_schema.sql
--
-- Notes:
-- - Validates customer, product, and quantity.
-- - Prevents negative inventory under concurrent updates.
-- - Stores historical order-item prices.
-- - All changes belong to the caller's transaction.
-- - No COMMIT or ROLLBACK inside the function.
-- - Not an idempotent checkout API.
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_checkout_order(
    p_customer_id BIGINT,
    p_product_id BIGINT,
    p_quantity INTEGER,
    p_order_number VARCHAR(50)
)
RETURNS TABLE (
    created_order_id BIGINT,
    created_order_number VARCHAR(50),
    created_total NUMERIC(12,2)
)
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_price NUMERIC(12,2);
    v_order_id BIGINT;
    v_stock_after INTEGER;
    v_total NUMERIC(12,2);
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Quantity must be greater than zero';
    END IF;

    IF p_order_number IS NULL OR BTRIM(p_order_number) = '' THEN
        RAISE EXCEPTION 'Order number is required';
    END IF;

    PERFORM 1
    FROM public.customers
    WHERE customer_id = p_customer_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Customer not found';
    END IF;

    -- Protect the current price and active status.
    SELECT price
    INTO v_price
    FROM public.products
    WHERE product_id = p_product_id
      AND is_active = TRUE
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product not found or inactive';
    END IF;

    -- Atomic inventory deduction.
    UPDATE public.inventory
    SET quantity_available = quantity_available - p_quantity,
        updated_at = CURRENT_TIMESTAMP
    WHERE product_id = p_product_id
      AND quantity_available >= p_quantity
    RETURNING quantity_available INTO v_stock_after;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Insufficient stock for product %',
            p_product_id;
    END IF;

    INSERT INTO public.orders (
        customer_id,
        order_number,
        status
    )
    VALUES (
        p_customer_id,
        p_order_number,
        'PENDING'
    )
    RETURNING order_id INTO v_order_id;

    INSERT INTO public.order_items (
        order_id,
        product_id,
        quantity,
        unit_price
    )
    VALUES (
        v_order_id,
        p_product_id,
        p_quantity,
        v_price
    );

    SELECT SUM(quantity * unit_price)
    INTO v_total
    FROM public.order_items
    WHERE order_id = v_order_id;

    UPDATE public.orders
    SET total_amount = v_total
    WHERE order_id = v_order_id;

    RETURN QUERY
    SELECT
        v_order_id,
        p_order_number,
        v_total;
END;
$function$;
