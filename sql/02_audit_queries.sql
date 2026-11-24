-- ============================================================================
-- Problem 2: The Marketing Warehouse
-- File: 02_audit_queries.sql
-- Description: Diagnostic SQL audit queries proving 6 critical defects
--              in the legacy marketing_sales_master schema and dataset.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- DEFECT 1: Cartesian Product & Duplicated Daily Ad Spend
-- Business Impact: Naive ad spend aggregations inflate actual spend by 10x-20x,
--                  causing computed ROAS to collapse and triggering false marketing panic.
-- ----------------------------------------------------------------------------
WITH raw_spend AS (
    SELECT SUM(ad_spend) AS naive_total 
    FROM marketing_sales_master
),
dedup_spend AS (
    SELECT SUM(daily_spend) AS dedup_total
    FROM (
        SELECT 
            TRIM(record_date) AS rec_dt,
            TRIM(LOWER(campaign_name)) AS cmp,
            MAX(ad_spend) AS daily_spend
        FROM marketing_sales_master
        WHERE ad_spend IS NOT NULL
        GROUP BY TRIM(record_date), TRIM(LOWER(campaign_name))
    ) d
)
SELECT 
    'DEFECT 1: Ad Spend Explosion' AS defect,
    ROUND(r.naive_total::NUMERIC, 2) AS naive_inflated_spend,
    ROUND(d.dedup_total::NUMERIC, 2) AS true_deduplicated_spend,
    ROUND((r.naive_total / NULLIF(d.dedup_total, 0))::NUMERIC, 2) AS inflation_multiplier
FROM raw_spend r, dedup_spend d;


-- ----------------------------------------------------------------------------
-- DEFECT 2: IEEE-754 Floating-Point Representation Drift in Financials
-- Business Impact: Accumulated fractional cent drift breaks reconciliation with
--                  bank settlements, payment gateways, and audited balance sheets.
-- ----------------------------------------------------------------------------
SELECT 
    'DEFECT 2: Float Precision Drift' AS defect,
    id,
    order_id,
    unit_price,
    order_total,
    (order_total::TEXT) AS float_as_text,
    ROUND(order_total::NUMERIC, 6) AS numeric_cast_value
FROM marketing_sales_master
WHERE order_total IS NOT NULL
  AND order_total::TEXT LIKE '%.9999%' OR order_total::TEXT LIKE '%.0000%'
LIMIT 5;


-- ----------------------------------------------------------------------------
-- DEFECT 3: Quantities and Metrics Stored as VARCHAR (Non-Numeric Garbage)
-- Business Impact: Aggregate queries (SUM, AVG) fail with type-casting exceptions
--                  or miss records due to dirty commas, percentage signs, or words.
-- ----------------------------------------------------------------------------
SELECT 
    'DEFECT 3: Text in Numeric Columns' AS defect,
    COUNT(*) FILTER (WHERE impressions ~ '[^0-9]') AS dirty_impressions_count,
    COUNT(*) FILTER (WHERE clicks ~ '[^0-9]') AS dirty_clicks_count,
    COUNT(*) FILTER (WHERE qty ~ '[^0-9]') AS dirty_qty_count,
    COUNT(*) FILTER (WHERE gst_percent LIKE '%') AS dirty_gst_count
FROM marketing_sales_master;


-- ----------------------------------------------------------------------------
-- DEFECT 4: Packed Hierarchy in Single Column (category_path)
-- Business Impact: Category rollups require fragile and slow string parsing/regex
--                  which misclassifies nested subcategories (e.g. Linen Shirts vs Cotton).
-- ----------------------------------------------------------------------------
SELECT 
    'DEFECT 4: Packed Category Path' AS defect,
    category_path,
    COUNT(*) AS row_count
FROM marketing_sales_master
WHERE category_path IS NOT NULL
GROUP BY category_path
ORDER BY row_count DESC
LIMIT 5;


-- ----------------------------------------------------------------------------
-- DEFECT 5: Inconsistent Enums, Mixed Casing, and Whitespace
-- Business Impact: Case-sensitive status filters (e.g. WHERE order_status = 'CANCELLED')
--                  silently exclude 'CANCELED' and 'Cancelled', corrupting net revenue calculations.
-- ----------------------------------------------------------------------------
SELECT 
    'DEFECT 5: Inconsistent Status Enums' AS defect,
    order_status,
    COUNT(*) AS frequency
FROM marketing_sales_master
WHERE order_status IS NOT NULL
GROUP BY order_status
ORDER BY order_status;


-- ----------------------------------------------------------------------------
-- DEFECT 6: Absence of Constraints & Order Item Total Discrepancies
-- Business Impact: Inaccurate invoice billing and ledger mismatches due to unvalidated
--                  line items, negative values, or paise recorded as rupees.
-- ----------------------------------------------------------------------------
WITH item_aggregates AS (
    SELECT 
        order_id,
        MAX(order_total) AS recorded_order_total,
        SUM(
            CASE 
                WHEN qty ~ '^[0-9]+$' THEN qty::INTEGER 
                ELSE 1 
            END * 
            unit_price * 
            (1.0 + (REPLACE(REPLACE(gst_percent, '%', ''), ' ', '')::NUMERIC / 100.0))
        ) AS computed_order_total
    FROM marketing_sales_master
    WHERE order_id IS NOT NULL 
      AND unit_price IS NOT NULL 
      AND order_total IS NOT NULL
    GROUP BY order_id
)
SELECT 
    'DEFECT 6: Order Total Discrepancy' AS defect,
    COUNT(*) AS total_orders_evaluated,
    COUNT(*) FILTER (WHERE ABS(recorded_order_total - computed_order_total) > 1.0) AS discrepant_orders_count,
    COUNT(*) FILTER (WHERE recorded_order_total > 50000) AS potential_paise_scaled_orders
FROM item_aggregates;
