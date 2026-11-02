# E-Commerce Database Design — Phase 1

## Goal
Design a relational database for an E-Commerce platform using PostgreSQL, starting with a clear logical data model and documented integrity rules.

## Entities

| Table | Primary key | Attributes | Purpose |
|---|---|---|---|
| customers | customer_id | first_name, last_name, email, password_hash, created_at | Registered customers |
| categories | category_id | name, description | Product classification |
| products | product_id | category_id, sku, name, description, price, is_active | Product catalog |
| inventory | product_id | quantity_available, updated_at | Stock per product |
| orders | order_id | customer_id, order_number, status, placed_at, total_amount | Customer purchases |
| order_items | order_item_id | order_id, product_id, quantity, unit_price | Order lines |

## Relationships

- One customer can place many orders; each order belongs to one customer.
- One category contains many products; each product belongs to one category in v1.
- A product has one inventory row, with inventory.product_id serving as both PK and FK. A product's corresponding inventory row must be created as part of product setup.
- Each order contains one or more order items; each order item points to one product.
- Products and orders form a many-to-many relationship resolved through order_items.

## Business and integrity rules

1. Use BIGINT identity primary keys, except inventory.product_id (shared PK/FK).
2. Enforce unique customer emails, product SKUs, and order numbers.
3. Use NUMERIC(12,2) for money; avoid floating-point fields.
4. Require strictly positive order quantities; ensure stock never becomes negative.
5. Store unit_price in each order item as the price snapshot at checkout.
6. Ensure orders.total_amount equals the sum of order-item quantity * unit_price, maintained transactionally.
7. Use TIMESTAMPTZ for timestamps and store timestamps in UTC.
8. Store only securely hashed passwords, never plaintext credentials.
9. Restrict deletion of referenced customers, products, and categories; deactivate where appropriate.
10. Define lifecycle status values for orders; revenue reports must exclude cancelled and unrecognized orders as appropriate.
11. In v1, prevent duplicate product rows in an order with UNIQUE(order_id, product_id).

## Out of scope for v1

Payment processing, shipments, addresses, reviews, coupons, returns, taxes, and multiple warehouses.

## Next step

Review this logical model, draw an ERD, and then implement the PostgreSQL schema.
