# E-Commerce Sales Reports

These read-only PostgreSQL 17 queries report sales grouped by **UTC order-placement date**.

| File | Grouping |
| --- | --- |
| `01_daily_sales.sql` | Day |
| `02_monthly_sales.sql` | Month |
| `03_yearly_sales.sql` | Year |

## Requirements

Run `database/01_schema.sql` on a new database and then optionally `database/02_sample_data.sql` to seed demo rows. Open each report in pgAdmin Query Tool connected to `ecommerce_db`.

## Metrics

- `total_orders`: All orders, regardless of state.
- `pending_orders`, `delivered_orders`, `cancelled_orders`: Order counts by status. `CONFIRMED` and `SHIPPED` are included in total_orders but not listed as separate count columns.
- `total_order_value`: Sum of `orders.total_amount` across all order states, **including cancelled orders**. It is a pipeline/order-value metric, not revenue.
- `recognized_revenue`: Sum of `orders.total_amount` for orders currently marked `DELIVERED` only. This is a **demonstration rule**, not a general accounting policy.

## Limitations / future improvements

- Revenue is attributed to the **order-placement date**, because the current schema does not store delivery/completion timestamps. It must not be interpreted as actual revenue-by-recognition-date.
- No currencies, refunds, taxes, shipping charges, discounts, or payments are modeled yet.
- The current schema does not automatically synchronize `orders.total_amount` when order_items change; these reports assume stored totals have been validated.
- Grouping uses UTC rather than the PostgreSQL session time zone. To use Saudi Arabia business days, consistently replace `AT TIME ZONE 'UTC'` with `AT TIME ZONE 'Asia/Riyadh'` in all three queries.
- Dates with zero orders are omitted. A reporting calendar can be added later to display zero-activity periods.
