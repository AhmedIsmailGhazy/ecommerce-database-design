-- E-Commerce Database Design
-- PostgreSQL 17
-- Recommended performance indexes

-- Products by category
CREATE INDEX IF NOT EXISTS idx_products_category_id
ON public.products (category_id);

-- Orders by customer
CREATE INDEX IF NOT EXISTS idx_orders_customer_id
ON public.orders (customer_id);

-- Orders by date
CREATE INDEX IF NOT EXISTS idx_orders_placed_at
ON public.orders (placed_at);

-- Order items by product
CREATE INDEX IF NOT EXISTS idx_order_items_product_id
ON public.order_items (product_id);
