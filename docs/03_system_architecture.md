# E-Commerce Database — System Architecture

**Project:** E-Commerce Database Design & SQL Analytics  
**Database:** PostgreSQL 17  
**Migration Tool:** Flyway OSS  
**Architecture Scope:** Relational data model, transactional checkout, inventory consistency, analytical queries, and database migrations.

## 1. Architecture Overview

This project is a database-focused e-commerce reference implementation. It demonstrates how PostgreSQL can enforce relational integrity and implement transactional business operations directly through SQL and PL/pgSQL.

The repository does not implement a web application, REST API, payment service, authentication service, or distributed microservices.

The implemented architecture consists of:

1. **Relational Data Layer** — Six normalized business tables.
2. **Transactional Business Logic** — PostgreSQL checkout functions.
3. **Concurrency Control** — Row locks, conditional stock updates, and transaction-scoped advisory locks.
4. **Reporting Layer** — SQL analytics and a customer summary view.
5. **Schema Versioning** — Ordered Flyway migrations.
6. **Verification** — SQL functional and concurrency test scripts.

## 2. Database Components

| Component | Responsibility |
|---|---|
| `customers` | Customer identities and contact information |
| `categories` | Product classification |
| `products` | Product catalog, SKU, pricing, and availability status |
| `inventory` | Current stock quantities |
| `orders` | Order headers, customer relationships, status, and totals |
| `order_items` | Ordered products, quantities, and historical unit prices |

### Relationships

- One customer can place multiple orders.
- One category can contain multiple products.
- One product can have at most one inventory record.
- One order can contain multiple order items.
- One product can appear in multiple orders.

Order items act as the association between orders and products.

The authoritative entity relationship diagram is maintained in `diagrams/ecommerce_erd.drawio`, with PNG and SVG exports.

## 3. Transactional Checkout Architecture

The database implements three checkout operations:

### 3.1 Single-Product Checkout

**Function:** `public.create_checkout_order`

The function:

1. Validates the requested quantity and order number.
2. Confirms that the customer exists.
3. Reads and locks the active product record to capture its price.
4. Deducts stock using a conditional atomic update.
5. Creates an order with `PENDING` status.
6. Creates the associated order item.
7. Calculates and stores the order total.

The conditional inventory update prevents a successful deduction when available stock is insufficient.

### 3.2 Multi-Product Checkout

**Function:** `public.create_multi_product_checkout`

Accepts a JSONB array of products and quantities.

Key characteristics:

- Validates the request structure and quantities.
- Rejects duplicate products within the same request.
- Processes product IDs in deterministic order to reduce deadlock risk.
- Protects product pricing using row locks.
- Deducts inventory using conditional updates.
- Creates a single order containing multiple order items.
- Stores historical unit prices and the calculated total.

All operations participate in the caller's PostgreSQL transaction.

If an unhandled exception occurs, the enclosing transaction must be rolled back; the function does not issue `COMMIT` or `ROLLBACK` itself.

### 3.3 Idempotent Checkout

**Function:** `public.create_idempotent_checkout`

This operation adds retry protection for multi-product checkout requests.

It uses:

- A unique constraint on `orders.order_number`.
- `pg_advisory_xact_lock` based on the order number.
- Existing-order lookup.
- Customer and order-item comparison.

For a repeated request with the same order number, customer, products, and quantities, the function returns the existing order without deducting stock again.

If the order number already belongs to a different customer or the requested items differ, the function raises an idempotency conflict.

**Design boundary:** Idempotency is based on the order number and the validated request data. This is not an independent HTTP idempotency-key service.

## 4. Data Consistency

### Referential Integrity

Foreign keys prevent invalid references between customers, categories, products, orders, inventory, and order items.

### Uniqueness

Unique constraints protect business identifiers including customer email, product SKU, order number, and the combination of order ID and product ID.

### Monetary Values

`NUMERIC(12,2)` is used for stored monetary values to avoid floating-point rounding issues.

The schema does not include a currency column. Sample reporting examples assume SAR.

### Historical Pricing

`order_items.unit_price` stores the price captured during checkout.

Later changes to `products.price` do not automatically alter historical order values.

### Stored Order Totals

`orders.total_amount` is a deliberately stored derived value. The checkout functions maintain it when creating orders.

Direct database modifications outside those functions could cause inconsistencies, so applications must control write permissions and preserve the relevant business invariants.

## 5. Concurrency Architecture

PostgreSQL provides the transaction and locking mechanisms.

**Stock consistency:** Checkout functions use conditional `UPDATE` statements requiring sufficient stock. Concurrent inventory modifications are serialized as necessary by PostgreSQL row locking.

**Price consistency:** `FOR SHARE` protects the selected product row while its current price is captured.

**Deadlock reduction:** Multi-product checkout processes product IDs in ascending order.

**Retry consistency:** Idempotent checkout takes a transaction-scoped advisory lock before checking the existing order or creating a new one.

These mechanisms improve consistency but do not replace transaction management, operational monitoring, retry handling, or full production concurrency testing.

## 6. Reporting Architecture

The repository separates operational checkout logic from analytical SQL scripts.

The `reports/` directory contains nine reporting queries covering sales periods, products, customers, rankings, growth, and cumulative metrics.

The view `public.v_customer_order_summary` provides reusable customer-level order summaries.

The reporting implementation uses ordinary SQL queries rather than a dedicated analytical warehouse or materialized reporting pipeline.

Revenue and order-value metrics must be interpreted according to their individual report definitions; the project does not implement a complete financial recognition system.

## 7. Database Migration Architecture

Flyway manages schema versions using SQL migration files in the `migrations/` directory.

| Version | Responsibility |
|---|---|
| V1 | Create relational tables and constraints |
| V2 | Create supporting indexes |
| V3 | Create customer summary view |
| V4 | Create single-product checkout function |
| V5 | Create multi-product checkout function |
| V6 | Create idempotent checkout function |

Flyway records completed migrations in `public.flyway_schema_history`.

### Verification Record

On November 7, 2026:

- Flyway OSS 13.12.1 was executed against PostgreSQL 17.11.
- The target database was `ecommerce_flyway_test`.
- All six migrations completed successfully.
- Schema history confirmed versions V1–V6 with `success = true`.
- The resulting schema version was V6.

The existing `ecommerce_db` development database was not used as the Flyway migration target.

### Migration Rules

- Run migrations against a known target database.
- Review migrations before execution.
- Never place database credentials in the repository.
- Do not edit previously applied migration files to introduce new schema changes.
- Add new versioned migrations for subsequent changes.
- Keep demonstration sample data separate from structural migrations.

## 8. Testing Strategy

The repository contains SQL tests for:

- Single-product checkout.
- Transaction rollback and insufficient inventory.
- Duplicate order numbers and invalid quantities.
- Multi-product checkout.
- Idempotent request retries and conflicts.
- Manual concurrency scenarios.

These are database-level tests. They do not represent end-to-end browser, API, payment, or load tests.

Migration success on `ecommerce_flyway_test` confirms successful schema deployment; it does not by itself mean that every functional test was rerun on that target database.

## 9. Security and Operational Boundaries

The project demonstrates database constraints and transaction handling, but does not provide a complete security or operations framework.

Important limitations include:

- No implemented authentication or authorization layer.
- No payment processing or payment-state integration.
- No dedicated audit log.
- No distributed transaction coordination.
- No automated production deployment workflow.
- No demonstrated production backup, restore, or disaster recovery process.
- No proof of production-scale throughput or availability.

Demo customer password hashes are placeholders and must not be used for real authentication.

## 10. Architecture References

- `database/` — Original SQL implementation scripts and demo data.
- `migrations/` — Flyway versioned SQL migrations.
- `diagrams/` — ERD source and exports.
- `reports/` — Analytical SQL queries.
- `tests/` — Database test scenarios.
- `docs/01_database_requirements.md` — Database requirements.
- `docs/02_normalization_and_denormalization.md` — Data modeling decisions.

## 11. Conclusion

The architecture demonstrates a PostgreSQL-centered approach to relational database design, transactional checkout, inventory consistency, retry-safe order creation, SQL reporting, and controlled schema evolution.

Its intended purpose is to serve as an educational SQL engineering and database architecture portfolio project rather than a production-ready e-commerce platform.
