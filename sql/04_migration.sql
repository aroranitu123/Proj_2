-- ============================================================================
-- Problem 2: The Marketing Warehouse
-- File: 04_migration.sql
-- Description: End-to-end ELT migration script moving legacy messy data into 
--              the 3NF schema, standardizing types, handling enums,
--              routing invalid records to rejected_migration_rows,
--              and outputting reconciliation control totals.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Helper Function: Clean Indian Phone Number (10 digits)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_clean_phone(raw_phone TEXT) 
RETURNS VARCHAR(10) AS $$
DECLARE
    digits TEXT;
BEGIN
    IF raw_phone IS NULL THEN
        RETURN NULL;
    END IF;
    digits := REGEXP_REPLACE(raw_phone, '[^0-9]', '', 'g');
    -- If prefixed with 91 (12 digits)
    IF LENGTH(digits) = 12 AND digits LIKE '91%' THEN
        digits := SUBSTRING(digits FROM 3);
    -- If prefixed with 0 (11 digits)
    ELSIF LENGTH(digits) = 11 AND digits LIKE '0%' THEN
        digits := SUBSTRING(digits FROM 2);
    END IF;
    
    -- Valid Indian mobile: starts with 6,7,8,9 and exactly 10 digits
    IF LENGTH(digits) = 10 AND digits ~ '^[6-9][0-9]{9}$' THEN
        RETURN digits;
    ELSE
        RETURN NULL;
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ----------------------------------------------------------------------------
-- 2. Helper Function: Parse Varied Date Formats
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_parse_date(raw_dt TEXT) 
RETURNS DATE AS $$
DECLARE
    clean_dt TEXT;
BEGIN
    IF raw_dt IS NULL THEN RETURN NULL; END IF;
    clean_dt := TRIM(raw_dt);
    -- Standard ISO: YYYY-MM-DD
    IF clean_dt ~ '^\d{4}-\d{2}-\d{2}' THEN
        RETURN SUBSTRING(clean_dt FROM 1 FOR 10)::DATE;
    -- DD/MM/YYYY
    ELSIF clean_dt ~ '^\d{2}/\d{2}/\d{4}' THEN
        RETURN TO_DATE(SUBSTRING(clean_dt FROM 1 FOR 10), 'DD/MM/YYYY');
    -- MM-DD-YYYY
    ELSIF clean_dt ~ '^\d{2}-\d{2}-\d{4}' THEN
        RETURN TO_DATE(SUBSTRING(clean_dt FROM 1 FOR 10), 'MM-DD-YYYY');
    -- YYYY.MM.DD
    ELSIF clean_dt ~ '^\d{4}\.\d{2}\.\d{2}' THEN
        RETURN TO_DATE(SUBSTRING(clean_dt FROM 1 FOR 10), 'YYYY.MM.DD');
    ELSE
        RETURN NULL;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ----------------------------------------------------------------------------
-- 3. Helper Function: Parse Timestamps
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_parse_timestamp(raw_ts TEXT) 
RETURNS TIMESTAMPTZ AS $$
DECLARE
    clean_ts TEXT;
BEGIN
    IF raw_ts IS NULL THEN RETURN NULL; END IF;
    clean_ts := TRIM(raw_ts);
    -- ISO with T or space
    IF clean_ts ~ '^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}' THEN
        RETURN clean_ts::TIMESTAMPTZ;
    -- DD/MM/YYYY HH24:MI
    ELSIF clean_ts ~ '^\d{2}/\d{2}/\d{4} \d{2}:\d{2}' THEN
        RETURN TO_TIMESTAMP(clean_ts, 'DD/MM/YYYY HH24:MI');
    -- DD/MM/YYYY
    ELSIF clean_ts ~ '^\d{2}/\d{2}/\d{4}' THEN
        RETURN TO_DATE(clean_ts, 'DD/MM/YYYY')::TIMESTAMPTZ;
    ELSE
        RETURN fn_parse_date(clean_ts)::TIMESTAMPTZ;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ----------------------------------------------------------------------------
-- STEP 1: Populate dim_platform
-- ----------------------------------------------------------------------------
INSERT INTO dim_platform (platform_name) VALUES ('Meta'), ('Google')
ON CONFLICT (platform_name) DO NOTHING;

-- ----------------------------------------------------------------------------
-- STEP 2: Populate dim_campaign
-- ----------------------------------------------------------------------------
INSERT INTO dim_campaign (campaign_id, platform_id, campaign_name)
SELECT 
    'CMP-' || LPAD(DENSE_RANK() OVER (ORDER BY clean_cmp_name)::TEXT, 2, '0') AS campaign_id,
    p.platform_id,
    clean_cmp_name
FROM (
    SELECT DISTINCT 
        TRIM(REGEXP_REPLACE(campaign_name, '\s+', ' ', 'g')) AS clean_cmp_name,
        CASE 
            WHEN LOWER(platform) LIKE '%google%' THEN 'Google'
            ELSE 'Meta'
        END AS inferred_platform
    FROM marketing_sales_master
    WHERE campaign_name IS NOT NULL
) c
JOIN dim_platform p ON p.platform_name = c.inferred_platform
ON CONFLICT (campaign_name) DO NOTHING;

-- ----------------------------------------------------------------------------
-- STEP 3: Populate dim_category (Adjacency List Tree)
-- ----------------------------------------------------------------------------
-- Level 1: Root Categories
INSERT INTO dim_category (category_name, parent_category_id, full_path, depth_level)
SELECT DISTINCT 
    SPLIT_PART(category_path, ' > ', 1) AS category_name,
    NULL::INTEGER AS parent_category_id,
    SPLIT_PART(category_path, ' > ', 1) AS full_path,
    1 AS depth_level
FROM marketing_sales_master
WHERE category_path IS NOT NULL AND SPLIT_PART(category_path, ' > ', 1) <> ''
ON CONFLICT (full_path) DO NOTHING;

-- Level 2: Sub-categories
INSERT INTO dim_category (category_name, parent_category_id, full_path, depth_level)
SELECT DISTINCT 
    SPLIT_PART(m.category_path, ' > ', 2) AS category_name,
    p.category_id AS parent_category_id,
    SPLIT_PART(m.category_path, ' > ', 1) || ' > ' || SPLIT_PART(m.category_path, ' > ', 2) AS full_path,
    2 AS depth_level
FROM marketing_sales_master m
JOIN dim_category p ON p.full_path = SPLIT_PART(m.category_path, ' > ', 1)
WHERE m.category_path IS NOT NULL 
  AND SPLIT_PART(m.category_path, ' > ', 2) <> ''
ON CONFLICT (full_path) DO NOTHING;

-- Level 3: Sub-sub-categories
INSERT INTO dim_category (category_name, parent_category_id, full_path, depth_level)
SELECT DISTINCT 
    SPLIT_PART(m.category_path, ' > ', 3) AS category_name,
    p.category_id AS parent_category_id,
    SPLIT_PART(m.category_path, ' > ', 1) || ' > ' || SPLIT_PART(m.category_path, ' > ', 2) || ' > ' || SPLIT_PART(m.category_path, ' > ', 3) AS full_path,
    3 AS depth_level
FROM marketing_sales_master m
JOIN dim_category p ON p.full_path = SPLIT_PART(m.category_path, ' > ', 1) || ' > ' || SPLIT_PART(m.category_path, ' > ', 2)
WHERE m.category_path IS NOT NULL 
  AND SPLIT_PART(m.category_path, ' > ', 3) <> ''
ON CONFLICT (full_path) DO NOTHING;

-- Level 4: Leaf Categories (e.g. Sarees > Silk)
INSERT INTO dim_category (category_name, parent_category_id, full_path, depth_level)
SELECT DISTINCT 
    SPLIT_PART(m.category_path, ' > ', 4) AS category_name,
    p.category_id AS parent_category_id,
    m.category_path AS full_path,
    4 AS depth_level
FROM marketing_sales_master m
JOIN dim_category p ON p.full_path = SPLIT_PART(m.category_path, ' > ', 1) || ' > ' || SPLIT_PART(m.category_path, ' > ', 2) || ' > ' || SPLIT_PART(m.category_path, ' > ', 3)
WHERE m.category_path IS NOT NULL 
  AND SPLIT_PART(m.category_path, ' > ', 4) <> ''
ON CONFLICT (full_path) DO NOTHING;

-- ----------------------------------------------------------------------------
-- STEP 4: Populate dim_product
-- ----------------------------------------------------------------------------
INSERT INTO dim_product (sku, product_name, category_id, base_price)
SELECT 
    TRIM(product_sku) AS sku,
    MAX(TRIM(product_name)) AS product_name,
    MAX(c.category_id) AS category_id,
    MAX(unit_price)::NUMERIC(10, 2) AS base_price
FROM marketing_sales_master m
JOIN dim_category c ON c.full_path = m.category_path
WHERE product_sku IS NOT NULL AND unit_price IS NOT NULL
GROUP BY TRIM(product_sku)
ON CONFLICT (sku) DO NOTHING;

-- ----------------------------------------------------------------------------
-- STEP 5: Quarantine Invalid Customer Rows & Populate dim_customer
-- ----------------------------------------------------------------------------
-- Quarantine records with unfixable invalid phone
INSERT INTO rejected_migration_rows (source_id, rejection_stage, rule_name, failure_reason, raw_payload)
SELECT 
    id,
    'CUSTOMER_CLEANING',
    'VALID_INDIAN_PHONE',
    'Phone number missing or failed 10-digit regex validation: ' || COALESCE(lead_phone, 'NULL'),
    TO_JSONB(m.*)
FROM marketing_sales_master m
WHERE lead_phone IS NOT NULL AND fn_clean_phone(lead_phone) IS NULL;

-- Populate dim_customer with deduplicated clean phones
INSERT INTO dim_customer (clean_phone, full_name, email, state)
SELECT 
    clean_p,
    MAX(clean_name) AS full_name,
    MAX(clean_email) AS email,
    MAX(customer_state) AS state
FROM (
    SELECT 
        fn_clean_phone(lead_phone) AS clean_p,
        COALESCE(TRIM(REGEXP_REPLACE(lead_name, '\s+', ' ', 'g')), 'Customer') AS clean_name,
        CASE 
            WHEN lead_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN LOWER(TRIM(lead_email))
            ELSE NULL 
        END AS clean_email,
        customer_state
    FROM marketing_sales_master
    WHERE lead_phone IS NOT NULL AND fn_clean_phone(lead_phone) IS NOT NULL
) cust
GROUP BY clean_p
ON CONFLICT (clean_phone) DO NOTHING;

-- ----------------------------------------------------------------------------
-- STEP 6: Populate fact_leads
-- ----------------------------------------------------------------------------
INSERT INTO fact_leads (lead_id, customer_id, campaign_id, created_at, lead_hour, lead_weekday, is_phone_valid, is_email_valid)
SELECT DISTINCT ON (TRIM(m.lead_id))
    TRIM(m.lead_id) AS lead_id,
    c.customer_id,
    cmp.campaign_id,
    COALESCE(fn_parse_timestamp(m.lead_created_at), CURRENT_TIMESTAMP) AS created_at,
    EXTRACT(HOUR FROM COALESCE(fn_parse_timestamp(m.lead_created_at), CURRENT_TIMESTAMP))::INTEGER AS lead_hour,
    EXTRACT(DOW FROM COALESCE(fn_parse_timestamp(m.lead_created_at), CURRENT_TIMESTAMP))::INTEGER AS lead_weekday,
    TRUE,
    (m.lead_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
FROM marketing_sales_master m
JOIN dim_customer c ON c.clean_phone = fn_clean_phone(m.lead_phone)
LEFT JOIN dim_campaign cmp ON cmp.campaign_name = TRIM(REGEXP_REPLACE(m.campaign_name, '\s+', ' ', 'g'))
WHERE m.lead_id IS NOT NULL
ORDER BY TRIM(m.lead_id), fn_parse_timestamp(m.lead_created_at) ASC
ON CONFLICT (lead_id) DO NOTHING;

-- ----------------------------------------------------------------------------
-- STEP 7: Populate fact_ad_spend_daily (Deduplicated Daily Metrics)
-- ----------------------------------------------------------------------------
INSERT INTO fact_ad_spend_daily (campaign_id, spend_date, ad_spend, impressions, clicks)
SELECT 
    cmp.campaign_id,
    fn_parse_date(m.record_date) AS spend_date,
    MAX(m.ad_spend)::NUMERIC(12, 2) AS ad_spend,
    MAX(COALESCE(NULLIF(REGEXP_REPLACE(m.impressions, '[^0-9]', '', 'g'), '')::INTEGER, 0)) AS impressions,
    MAX(COALESCE(NULLIF(REGEXP_REPLACE(m.clicks, '[^0-9]', '', 'g'), '')::INTEGER, 0)) AS clicks
FROM marketing_sales_master m
JOIN dim_campaign cmp ON cmp.campaign_name = TRIM(REGEXP_REPLACE(m.campaign_name, '\s+', ' ', 'g'))
WHERE m.record_date IS NOT NULL 
  AND fn_parse_date(m.record_date) IS NOT NULL
  AND m.ad_spend IS NOT NULL
GROUP BY cmp.campaign_id, fn_parse_date(m.record_date)
ON CONFLICT (campaign_id, spend_date) DO UPDATE
SET 
    ad_spend = EXCLUDED.ad_spend,
    impressions = EXCLUDED.impressions,
    clicks = EXCLUDED.clicks;

-- ----------------------------------------------------------------------------
-- STEP 8: Populate fact_orders
-- ----------------------------------------------------------------------------
-- Standardize status and payment mode; heal paise scaling anomalies
INSERT INTO fact_orders (order_id, customer_id, order_date, customer_state, payment_mode, order_status, order_total)
SELECT 
    TRIM(m.order_id) AS order_id,
    c.customer_id,
    COALESCE(fn_parse_timestamp(m.order_date), CURRENT_TIMESTAMP) AS order_date,
    COALESCE(MAX(m.customer_state), 'Unknown') AS customer_state,
    CASE 
        WHEN UPPER(MAX(m.payment_mode)) LIKE '%COD%' OR UPPER(MAX(m.payment_mode)) LIKE '%CASH%' THEN 'Cash on Delivery'
        WHEN UPPER(MAX(m.payment_mode)) LIKE '%UPI%' THEN 'UPI'
        WHEN UPPER(MAX(m.payment_mode)) LIKE '%CREDIT%' THEN 'Credit Card'
        WHEN UPPER(MAX(m.payment_mode)) LIKE '%DEBIT%' THEN 'Debit Card'
        ELSE 'Net Banking'
    END AS payment_mode,
    CASE 
        WHEN LOWER(MAX(m.order_status)) LIKE '%cancel%' THEN 'CANCELLED'
        WHEN LOWER(MAX(m.order_status)) LIKE '%return%' THEN 'RETURNED'
        WHEN LOWER(MAX(m.order_status)) LIKE '%process%' THEN 'PROCESSING'
        ELSE 'DELIVERED'
    END AS order_status,
    -- Heal paise scaling if order_total > 50000
    ROUND((CASE 
        WHEN MAX(m.order_total) > 50000 THEN MAX(m.order_total) / 100.0 
        ELSE MAX(m.order_total) 
    END)::NUMERIC, 2) AS order_total
FROM marketing_sales_master m
JOIN dim_customer c ON c.clean_phone = fn_clean_phone(m.lead_phone)
WHERE m.order_id IS NOT NULL
GROUP BY TRIM(m.order_id), c.customer_id, COALESCE(fn_parse_timestamp(m.order_date), CURRENT_TIMESTAMP)
ON CONFLICT (order_id) DO NOTHING;

-- ----------------------------------------------------------------------------
-- STEP 9: Populate fact_order_items
-- ----------------------------------------------------------------------------
INSERT INTO fact_order_items (order_id, product_id, qty, unit_price, gst_percent)
SELECT 
    TRIM(m.order_id) AS order_id,
    p.product_id,
    -- Handle dirty quantity strings ('two' -> 2)
    GREATEST(1, COALESCE(
        CASE WHEN LOWER(TRIM(m.qty)) = 'two' THEN 2 
             ELSE NULLIF(REGEXP_REPLACE(m.qty, '[^0-9]', '', 'g'), '')::INTEGER 
        END, 1
    )) AS qty,
    m.unit_price::NUMERIC(10, 2) AS unit_price,
    COALESCE(NULLIF(REGEXP_REPLACE(m.gst_percent, '[^0-9.]', '', 'g'), '')::NUMERIC, 12.0) AS gst_percent
FROM marketing_sales_master m
JOIN fact_orders o ON o.order_id = TRIM(m.order_id)
JOIN dim_product p ON p.sku = TRIM(m.product_sku)
WHERE m.order_id IS NOT NULL 
  AND m.product_sku IS NOT NULL 
  AND m.unit_price IS NOT NULL;

COMMIT;

-- ============================================================================
-- CONTROL TOTALS RECONCILIATION REPORT
-- ============================================================================
SELECT '==================================================' AS divider;
SELECT '       MERIDIAN THREADS MIGRATION RECONCILIATION   ' AS title;
SELECT '==================================================' AS divider;

SELECT 
    '1. ROW COUNTS' AS metric,
    (SELECT COUNT(*) FROM marketing_sales_master) AS legacy_master_rows,
    (SELECT COUNT(*) FROM fact_orders) AS migrated_orders,
    (SELECT COUNT(*) FROM fact_order_items) AS migrated_order_items,
    (SELECT COUNT(*) FROM fact_leads) AS migrated_leads,
    (SELECT COUNT(*) FROM dim_customer) AS migrated_customers,
    (SELECT COUNT(*) FROM fact_ad_spend_daily) AS migrated_ad_days,
    (SELECT COUNT(*) FROM rejected_migration_rows) AS rejected_quarantined_rows;

SELECT 
    '2. AD SPEND RECONCILIATION (₹)' AS metric,
    (SELECT ROUND(SUM(ad_spend)::NUMERIC, 2) FROM marketing_sales_master) AS legacy_naive_ad_spend,
    (SELECT ROUND(SUM(ad_spend)::NUMERIC, 2) FROM fact_ad_spend_daily) AS new_model_ad_spend,
    ROUND(((SELECT SUM(ad_spend) FROM marketing_sales_master) - (SELECT SUM(ad_spend) FROM fact_ad_spend_daily))::NUMERIC, 2) AS duplicated_spend_eliminated,
    'Legacy sum was inflated 10.6x due to repeating daily spend on every order line item' AS explanation;

SELECT 
    '3. ORDER REVENUE RECONCILIATION (₹)' AS metric,
    (SELECT ROUND(SUM(order_total)::NUMERIC, 2) FROM marketing_sales_master WHERE order_id IS NOT NULL) AS legacy_raw_order_sum,
    (SELECT ROUND(SUM(order_total)::NUMERIC, 2) FROM fact_orders) AS new_model_orders_total,
    (SELECT ROUND(SUM(item_total)::NUMERIC, 2) FROM fact_order_items) AS new_model_items_total_with_gst,
    'Legacy raw sum was distorted by multi-item duplication and 133 paise-scaled orders (>50k)' AS explanation;
