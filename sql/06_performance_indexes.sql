-- ============================================================================
-- Problem 2: The Marketing Warehouse
-- File: 06_performance_indexes.sql
-- Description: Targeted indexes for Query 3 (Funnel) and Query 4 (Attribution),
--              including covering and partial indexes, plus negative index rationale.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- INDEX 1: Accelerates Query 3 (Conversion Funnel) & Query 8 (Cohort Attribution)
-- Type: Partial Composite B-Tree Index
-- Rationale: Indexes customer_id and order_date while filtering out cancelled/returned
--            orders at index build time. Converts the O(N*M) sequential scan into
--            an O(log N) index range scan.
-- ----------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_orders_customer_date;

CREATE INDEX idx_orders_customer_date 
ON fact_orders (customer_id, order_date)
WHERE order_status NOT IN ('CANCELLED', 'RETURNED');

-- ----------------------------------------------------------------------------
-- INDEX 2: Accelerates Query 4 (Attribution Engine) & Query 2 (Platform Rank)
-- Type: Covering Composite B-Tree Index with INCLUDE clause
-- Rationale: Order attribution joins fact_orders and fact_leads on customer_id,
--            orders by created_at DESC, and retrieves campaign_id.
--            Including campaign_id in the index leaf pages enables an Index-Only Scan.
-- ----------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_leads_customer_created;

CREATE INDEX idx_leads_customer_created 
ON fact_leads (customer_id, created_at DESC) 
INCLUDE (campaign_id, lead_id);

-- ----------------------------------------------------------------------------
-- INDEX 3 (BONUS): Covering Index for Daily Platform Spend Rollups (Query 5)
-- Type: Covering B-Tree on fact_ad_spend_daily
-- ----------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_spend_daily_covering;

CREATE INDEX idx_spend_daily_covering 
ON fact_ad_spend_daily (spend_date, campaign_id) 
INCLUDE (ad_spend, impressions, clicks);

-- ----------------------------------------------------------------------------
-- COUNTER-EXAMPLE: An Index That Would NOT Help Here (Negative Design Pattern)
-- ----------------------------------------------------------------------------
-- CREATE INDEX idx_ineffective_order_status ON fact_orders (order_status);
-- 
-- WHY THIS INDEX FAILS TO HELP:
-- 1. Extremely Low Cardinality: 'order_status' has only 4 distinct values 
--    ('DELIVERED', 'PROCESSING', 'CANCELLED', 'RETURNED'), where DELIVERED represents >75% of rows.
-- 2. I/O Cost Model Rejection: When a filter matches 75% of a table, traversing an index tree 
--    and then performing random page lookups in table heap requires far more I/O blocks than 
--    a single sequential block read (Seq Scan). PostgreSQL optimizer will deliberately ignore it.
-- 3. Write Degradation: Every new order insertion or status change must incur additional index 
--    write locking and buffer dirtying with zero read performance benefit.
