-- E-Commerce Database Design | PostgreSQL 17
-- Report 08: Top Products per Category
-- Rank products by ordered quantity within each category.
-- Excludes cancelled orders. PENDING orders count toward order value,
-- so the result does not represent recognized revenue.
-- Ties share the same DENSE_RANK; more than 3 products may be returned
-- per category if there is a tie at rank 3.

WITH product_sales AS (
    SELECT
        c.category_id,
        c.name AS category_name,
        p.product_id,
        p.sku,
        p.name AS product_name,
        COALESCE(SUM(
            CASE WHEN o.status <> 'CANCELLED'
                 THEN oi.quantity ELSE 0 END
        ), 0) AS units_sold,
        COALESCE(SUM(
            CASE WHEN o.status <> 'CANCELLED'
                 THEN oi.quantity * oi.unit_price ELSE 0 END
        ), 0) AS total_order_value
    FROM public.categories c
    JOIN public.products p
        ON p.category_id = c.category_id
    LEFT JOIN public.order_items oi
        ON oi.product_id = p.product_id
    LEFT JOIN public.orders o
        ON o.order_id = oi.order_id
    GROUP BY
        c.category_id, c.name,
        p.product_id, p.sku, p.name
),
ranked_products AS (
    SELECT
        *,
        DENSE_RANK() OVER (
            PARTITION BY category_id
            ORDER BY units_sold DESC
        ) AS category_rank
    FROM product_sales
)
SELECT
    category_name,
    product_name,
    sku,
    units_sold,
    total_order_value,
    category_rank
FROM ranked_products
WHERE category_rank <= 3
ORDER BY category_name, category_rank, product_name;
