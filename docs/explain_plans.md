# Part E: Performance Benchmarking & EXPLAIN ANALYZE Engineering Report
**Repository**: `problem2-warehouse`  
**Database**: PostgreSQL 19  
**Tables Profiled**: `fact_orders` (23,439 rows), `fact_leads` (6,297 rows)

---

## 1. Query 3: Lead-to-Order Conversion Funnel (Correlated Subquery)

### The Problem
Query 3 determines whether a lead placed an order within 14 days of creation using a correlated `EXISTS` clause.
Without an index on `fact_orders (customer_id, order_date)`, PostgreSQL was forced to perform a full sequential scan of all 23,439 rows in `fact_orders` for **each of the 6,297 leads** in `fact_leads`, scanning over **147.5 million rows** in total.

---

### BEFORE INDEX: Full Sequential Scan
```text
GroupAggregate (cost=0.14..10677756.76 rows=60 width=76) (actual time=69.436..59038.467 rows=60.00 loops=1)
  Group Key: c.campaign_name
  Buffers: shared hit=3399421
  -> Nested Loop (cost=0.14..5820.05 rows=6297 width=44) (actual time=0.932..148.542 rows=6297.00 loops=1)
       ...
  SubPlan exists_1
    -> Seq Scan on fact_orders o (cost=0.00..847.38 rows=1 width=0) (actual time=4.635..4.635 rows=0.30 loops=6297)
          Filter: ((order_date >= l.created_at) AND ((order_status)::text <> ALL ('{CANCELLED,RETURNED}'::text[])) 
                  AND (customer_id = l.customer_id) AND (order_date <= (l.created_at + '14 days'::interval)))
          Rows Removed by Filter: 19747
          Buffers: shared hit=1699677
  SubPlan exists_2
    -> Seq Scan on fact_orders o_1 (cost=0.00..847.38 rows=1 width=0) (actual time=4.616..4.616 rows=0.30 loops=6297)
          Filter: ((order_date >= l.created_at) AND ((order_status)::text <> ALL ('{CANCELLED,RETURNED}'::text[])) 
                  AND (customer_id = l.customer_id) AND (order_date <= (l.created_at + '14 days'::interval)))
          Rows Removed by Filter: 19747
          Buffers: shared hit=1699677

Planning Time: 3.916 ms
Execution Time: 59,038.998 ms (~59.04 seconds)
Buffer Hits: 3,399,421 blocks (~27.2 GB in memory cache churn)
```

---

### THE TARGETED INDEX
```sql
CREATE INDEX idx_orders_customer_date 
ON fact_orders (customer_id, order_date)
WHERE order_status NOT IN ('CANCELLED', 'RETURNED');
```
* **Design Rationale**: 
  1. **Partial Index**: Excludes `CANCELLED` and `RETURNED` orders entirely, keeping index size ~30% smaller.
  2. **Composite B-Tree**: Fast point lookup on `customer_id` followed by a localized B-tree range scan on `[created_at, created_at + 14 days]`.

---

### AFTER INDEX: Index-Only Scan
```text
GroupAggregate (cost=545.37..54905.73 rows=60 width=76) (actual time=6.475..17.086 rows=60.00 loops=1)
  Group Key: c.campaign_name
  Buffers: shared hit=25225 read=42
  -> Sort (cost=545.37..561.12 rows=6297 width=44) (actual time=5.753..6.059 rows=6297.00 loops=1)
       ...
  SubPlan exists_1
    -> Index Only Scan using idx_orders_customer_date on fact_orders o (cost=0.29..4.31 rows=1 width=0) (actual time=0.001..0.001 rows=0.30 loops=6297)
          Index Cond: ((customer_id = l.customer_id) AND (order_date >= l.created_at) AND (order_date <= (l.created_at + '14 days'::interval)))
          Heap Fetches: 0
          Index Searches: 6297
          Buffers: shared hit=12557 read=42
  SubPlan exists_2
    -> Index Only Scan using idx_orders_customer_date on fact_orders o_1 (cost=0.29..4.31 rows=1 width=0) (actual time=0.000..0.000 rows=0.30 loops=6297)
          Index Cond: ((customer_id = l.customer_id) AND (order_date >= l.created_at) AND (order_date <= (l.created_at + '14 days'::interval)))
          Heap Fetches: 0
          Index Searches: 6297
          Buffers: shared hit=12599

Planning Time: 1.596 ms
Execution Time: 17.369 ms (~0.017 seconds)
Buffer Hits: 25,225 blocks
```

### Performance Impact Summary
| Metric | Before Index | After Index | Improvement |
|---|---|---|---|
| **Execution Time** | **59,038.99 ms** | **17.37 ms** | **3,399x Faster** (99.97% latency reduction) |
| **Access Method** | Seq Scan (Filter 19,747 rows/loop) | Index Only Scan (Heap Fetches: 0) | Direct B-Tree Range Seek |
| **Shared Buffers Hit**| 3,399,421 blocks | 25,225 blocks | **99.2% I/O Cache Reduction** |

---

## 2. Query 4: Order Attribution Engine (Latest Lead Prior to Order)

### Targeted Index
```sql
CREATE INDEX idx_leads_customer_created 
ON fact_leads (customer_id, created_at DESC) 
INCLUDE (campaign_id, lead_id);
```
* **Design Rationale**: A **covering index** (`INCLUDE`) that allows the attribution CTE to resolve `customer_id`, timestamp comparison `created_at <= order_date`, and retrieve `campaign_id` directly from the index leaf pages without fetching table heap pages.

---

## 3. Negative Index Case Study: An Index That Would NOT Help Here

### The Proposed Bad Index
```sql
CREATE INDEX idx_ineffective_order_status ON fact_orders (order_status);
```

### Why This Index Fails to Help
1. **Extremely Low Cardinality**:
   The `order_status` column contains only 4 distinct values (`DELIVERED`, `PROCESSING`, `CANCELLED`, `RETURNED`). Of these, `DELIVERED` represents **over 75%** of all records.
2. **PostgreSQL Cost Model Rejection**:
   When a query filters on `order_status = 'DELIVERED'`, the optimizer estimates that it must retrieve 75% of table rows.
   - Using the index requires reading the index pages, then performing **17,500 random heap block lookups** across the table.
   - Performing a sequential scan (`Seq Scan`) requires reading the table heap sequentially in large multi-block I/O chunks.
   Because sequential block I/O is 4x-10x faster than random seek I/O, the optimizer will **completely ignore the index and choose a Sequential Scan**.
3. **Write Degradation with Zero Read Benefit**:
   Every INSERT, UPDATE, or DELETE on `fact_orders` must write to this index, adding index page lock contention and WAL write volume without ever speeding up a single analytical query.
