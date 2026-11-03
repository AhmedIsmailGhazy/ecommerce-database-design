# Normalization and Denormalization Decisions

## Scope
PostgreSQL 17 e-commerce sample schema: `customers`, `categories`, `products`, `inventory`, `orders`, and `order_items`.

## 1NF (First Normal Form)
Each table has a key and its columns store values of the intended atomic type. Products in an order are represented by separate `order_items` rows instead of comma-separated lists or repeated product columns.

## 2NF (Second Normal Form)
Non-key facts should depend on complete candidate keys. In `order_items`, the unique `(order_id, product_id)` identifies a line in v1; `quantity` and the `unit_price` captured for that line depend on that pairing. Product name or current catalog price are not duplicated there.

## 3NF (Third Normal Form)
Customer contact details live in `customers`, category details in `categories`, and current product details in `products`. `orders` references customers by ID instead of duplicating current email and names. The model is designed to avoid non-key attributes determining other unrelated non-key attributes; normal-form validation ultimately depends on business functional dependencies, not merely the presence of foreign keys.

## Derived data and historical facts
- `order_items.unit_price` is a **historical price snapshot** and intentionally differs from `products.price` after a price change.
- `orders.total_amount` is a derived/cached order total, which must be maintained transactionally whenever order lines change. The current seed script only synchronizes its demo orders, not all future writes.
- `inventory` is separated from product catalog details, with one possible inventory row per product enforced by shared PK/FK. Product creation must insert a corresponding inventory row to meet the stronger business rule.

## Customer summary view
See `database/04_customer_summary_view.sql`.

`public.v_customer_order_summary` combines `customers` and non-cancelled `orders` to show `total_orders` and `total_order_value` without storing redundant customer aggregates. It includes `PENDING` orders and thus reports **order value, not recognized revenue or verified payments**. The project currently assumes all amounts use SAR; there is no currency column in v1.

A PostgreSQL regular view stores a query definition, not materialized result rows. It therefore is **not physical denormalization**. It is the preferred first step for the small demonstration dataset because it needs no refresh or consistency synchronization.

## When to consider denormalization
For high-volume reporting, assess query plans, table size, refresh latency and measurement first. Potential options:
- Materialized view with a documented refresh schedule and stale-data tolerance.
- Cached aggregate columns maintained using transactionally correct logic.
- Dedicated analytics tables or pipelines if OLTP and reporting workloads diverge.

Any physical duplicate must explicitly define its source of truth and update/refresh strategy.

## Reproduction order
1. `database/01_schema.sql` (fresh database)
2. `database/02_sample_data.sql` (demo records)
3. `database/03_indexes.sql` (supporting indexes)
4. `database/04_customer_summary_view.sql` (read-only summary view)
