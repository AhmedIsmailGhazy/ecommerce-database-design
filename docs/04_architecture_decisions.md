# Architecture Decision Records (ADR)

**Project:** E-Commerce Database Design & SQL Analytics  
**Technology:** PostgreSQL 17, SQL, PL/pgSQL, Flyway  
**Last Updated:** November 7, 2026

## Purpose

This document records the significant architecture decisions made during the development of the E-Commerce Database Design project.

Each decision describes the technical context, alternatives, rationale, consequences, and trade-offs.

These records reflect the implemented educational database architecture, not a production-ready e-commerce platform.

---

## ADR-001: Use PostgreSQL as the Primary Database

**Status:** Accepted

### Context

The project requires a relational database supporting:

- Referential integrity and unique constraints.
- ACID transactions.
- Concurrent inventory updates.
- Complex analytical SQL queries.
- Database functions and procedural logic.
- Controlled database schema evolution.

### Decision

Use **PostgreSQL 17** as the primary relational database.

### Alternatives Considered

- MySQL.
- Microsoft SQL Server.
- NoSQL document databases.

### Rationale

PostgreSQL provides native support for:

- Foreign keys and transactional constraints.
- Row-level locking.
- `JSONB` request processing.
- PL/pgSQL stored functions.
- Advisory locks.
- Window functions and analytical queries.
- Integration with Flyway.

### Consequences

**Benefits**

- Strong relational consistency.
- Transactional checkout implementation.
- Rich SQL capabilities.
- Open-source database platform.

**Trade-offs**

- Database-specific PL/pgSQL logic reduces portability.
- Advanced PostgreSQL features require specialized knowledge.
- Database operations still require monitoring and maintenance in a real deployment.

---

## ADR-002: Use Normalized Relational Tables and Surrogate Keys

**Status:** Accepted

### Context

E-commerce data contains multiple related entities, including customers, products, categories, inventory, orders, and order items.

A poorly structured database could introduce duplicated data, inconsistent relationships, and difficult maintenance.

### Decision

Use six related tables with:

- Surrogate `BIGINT` primary keys for independent entities.
- Primary-key and foreign-key constraints.
- Unique business identifiers.
- Normalized product, customer, and order data.
- A separate `order_items` table for the relationship between orders and products.

### Alternatives Considered

- Natural business identifiers as primary keys.
- Composite primary keys throughout the model.
- A denormalized order table containing embedded product details.

### Rationale

Surrogate keys provide stable internal identifiers that remain independent of changing business information.

Unique constraints preserve business-level integrity for values such as email, SKU, and order number.

The normalized model reduces redundant storage and improves maintainability.

### Consequences

**Benefits**

- Clear entity relationships.
- Stable internal identifiers.
- Enforced referential integrity.
- Reduced unnecessary duplication.

**Trade-offs**

- Reporting often requires joins.
- Additional constraints are necessary to enforce domain rules.
- Certain derived values, such as order totals, require controlled synchronization.

---

## ADR-003: Implement Atomic Checkout Inside PostgreSQL

**Status:** Accepted

### Context

Concurrent checkout requests may attempt to purchase the same inventory.

A simple read-then-update approach can create race conditions and potentially oversell products.

Checkout also involves multiple dependent operations that must succeed or fail together.

### Decision

Implement transactional checkout using PL/pgSQL functions and PostgreSQL locking mechanisms.

The database provides:

- `create_checkout_order` for single-product checkout.
- `create_multi_product_checkout` for multi-product checkout.
- Conditional atomic inventory updates.
- Row-level locking for product price consistency.
- Deterministic product processing order in multi-product checkout.

All changes participate in the caller's transaction.

### Alternatives Considered

- Application-only stock validation.
- Separate inventory reads followed by unguarded updates.
- Independent SQL statements without a shared transaction.
- Distributed inventory coordination.

### Rationale

Conditional inventory updates ensure stock is deducted only when sufficient quantity exists.

PostgreSQL transactional semantics keep order creation, order items, and inventory modifications together.

Processing products in a consistent order reduces deadlock risk.

### Consequences

**Benefits**

- Prevents successful stock deduction when inventory is insufficient.
- Supports atomic order creation.
- Protects consistency during concurrent database operations.
- Centralizes important checkout rules.

**Trade-offs**

- Checkout logic becomes PostgreSQL-specific.
- Lock contention may affect throughput.
- Deadlocks and transaction failures still require handling.
- Application integrations must manage transaction boundaries correctly.

---

## ADR-004: Use Order-Number-Based Idempotency

**Status:** Accepted

### Context

A checkout request may be repeated because of network failures, client retries, or uncertain responses.

Without retry protection, duplicate requests can attempt to create additional orders or deduct inventory repeatedly.

### Decision

Implement `create_idempotent_checkout` using:

1. The existing unique constraint on `orders.order_number`.
2. A transaction-scoped PostgreSQL advisory lock.
3. Lookup of an existing order.
4. Validation of customer identity, products, and quantities.
5. Reuse of the existing order when the request matches.
6. Explicit conflict handling when request details differ.

### Alternatives Considered

- Relying only on a unique order-number constraint.
- A separate idempotency-key table.
- Application-side in-memory locks.
- Distributed locking services such as Redis.

### Rationale

The project is database-focused and does not implement a separate API or service layer.

PostgreSQL advisory locks provide transaction-scoped serialization for requests using the same order number.

The unique constraint remains a final database-level safeguard against duplicate order numbers.

### Consequences

**Benefits**

- Prevents repeated inventory deduction for matching retries.
- Returns the previously created order when applicable.
- Detects conflicting requests using the same order number.
- Avoids introducing external infrastructure.

**Trade-offs**

- Idempotency depends on correct order-number reuse.
- Advisory lock keys are derived from a hash, so unrelated keys can theoretically contend.
- This implementation is not a generalized HTTP idempotency service.
- Retry behavior depends on transaction semantics and correct handling of database errors.

---

## ADR-005: Use Flyway for Database Schema Versioning

**Status:** Accepted

### Context

Manual execution of SQL scripts can cause inconsistencies between environments.

As the project grows, database schema changes require an ordered and reproducible deployment process.

### Decision

Adopt **Flyway OSS** with versioned SQL migrations.

The project currently includes:

| Migration | Description |
|---|---|
| `V1__create_schema.sql` | Tables and constraints |
| `V2__create_indexes.sql` | Supporting indexes |
| `V3__create_customer_summary_view.sql` | Customer summary view |
| `V4__create_checkout_function.sql` | Single-product checkout |
| `V5__create_multi_product_checkout.sql` | Multi-product checkout |
| `V6__create_idempotent_checkout.sql` | Idempotent checkout |

The `flyway_schema_history` table tracks the applied migration versions.

### Alternatives Considered

- Manual SQL script execution.
- Liquibase.
- A custom schema-version tracking table.

### Rationale

Flyway offers simple, ordered migration files that fit the SQL-focused repository.

Its migration history provides visibility into applied versions and execution results.

### Verification

On November 7, 2026:

- Flyway OSS 13.12.1 connected to PostgreSQL 17.11.
- The target database was `ecommerce_flyway_test`.
- All six migrations completed successfully.
- The schema history showed six successful migrations.
- The resulting schema version was V6.

### Consequences

**Benefits**

- Repeatable schema deployment process.
- Explicit version history.
- Ordered migration execution.
- Detection of changes to applied migration files through validation.

**Trade-offs**

- Applied migration scripts should remain immutable.
- Subsequent changes require new migration versions.
- Production deployment still requires environment-specific planning, permissions, backups, and rollback strategy.
- Migration success alone does not prove functional correctness.

**Sample data:** `database/02_sample_data.sql` remains separate from structural migrations.

---

## ADR-006: Preserve Historical Pricing and Separate Reporting Logic

**Status:** Accepted

### Context

Product catalog prices can change after customers place orders.

Reports must not recalculate historical purchases using current product prices.

Analytical queries should also be organized separately from transactional checkout functions.

### Decision

Use:

- `products.price` for the current catalog price.
- `order_items.unit_price` for historical order-line pricing.
- `orders.total_amount` for the
