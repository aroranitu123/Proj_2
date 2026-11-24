-- ============================================================================
-- Problem 2: The Marketing Warehouse
-- File: ml/generate_ml_dataset.sql
-- Description: Builds the production ML-ready dataset for predicting lead-to-order
--              conversion within 14 days, with strict anti-leakage guarantees,
--              temporal train/test split, and class balance reporting.
-- ============================================================================

DROP TABLE IF EXISTS ml_lead_conversion_dataset CASCADE;

CREATE TABLE ml_lead_conversion_dataset AS
WITH historical_customer_orders AS (
    -- Compute prior customer order history STRICTLY BEFORE lead creation timestamp (T0)
    SELECT 
        l.lead_id,
        COUNT(o.order_id) AS prior_orders_count,
        COALESCE(SUM(o.order_total), 0.00) AS prior_total_spend,
        MAX(o.order_date) AS latest_prior_order_date
    FROM fact_leads l
    LEFT JOIN fact_orders o 
           ON o.customer_id = l.customer_id 
          AND o.order_date < l.created_at
          AND o.order_status NOT IN ('CANCELLED', 'RETURNED')
    GROUP BY l.lead_id
),
lead_conversions AS (
    -- Target Label: Check if customer ordered between [T0, T0 + 14 days]
    SELECT 
        l.lead_id,
        CASE 
            WHEN EXISTS (
                SELECT 1 
                FROM fact_orders o 
                WHERE o.customer_id = l.customer_id 
                  AND o.order_date >= l.created_at
                  AND o.order_date <= l.created_at + INTERVAL '14 days'
                  AND o.order_status NOT IN ('CANCELLED', 'RETURNED')
            ) THEN 1 
            ELSE 0 
        END AS converted_within_14d
    FROM fact_leads l
)
SELECT 
    l.lead_id,
    l.customer_id,
    l.created_at AS lead_created_at,
    
    -- Feature 1 & 2: Platform and Campaign
    p.platform_name,
    c.campaign_id,
    c.campaign_name,
    
    -- Feature 3 & 4: Temporal lead features (hour and day of week)
    l.lead_hour,
    l.lead_weekday,
    
    -- Feature 5 & 6: Data quality & contact verification flags
    l.is_phone_valid::INTEGER AS is_phone_valid,
    l.is_email_valid::INTEGER AS is_email_valid,
    
    -- Feature 7: Prior order count strictly before lead creation
    COALESCE(hco.prior_orders_count, 0) AS prior_orders_count,
    
    -- Feature 8: Historical LTV strictly before lead creation
    COALESCE(hco.prior_total_spend, 0.00) AS prior_total_spend,
    
    -- Feature 9: Days since last order (Missing imputed to -1.0 with indicator flag)
    CASE 
        WHEN hco.latest_prior_order_date IS NOT NULL THEN
            ROUND((EXTRACT(EPOCH FROM (l.created_at - hco.latest_prior_order_date)) / 86400.0)::NUMERIC, 2)
        ELSE -1.00
    END AS days_since_last_order,
    
    -- Feature 10: Repeat customer indicator
    CASE WHEN COALESCE(hco.prior_orders_count, 0) > 0 THEN 1 ELSE 0 END AS is_repeat_customer,
    
    -- Time-Based Train / Test Split (Cutoff: 2026-09-15)
    CASE 
        WHEN l.created_at < '2026-09-15 00:00:00+00'::TIMESTAMPTZ THEN 'TRAIN'
        ELSE 'TEST'
    END AS dataset_split,
    
    -- TARGET LABEL (1 = Converted within 14 days, 0 = Did not convert)
    lc.converted_within_14d

FROM fact_leads l
JOIN dim_customer cust ON cust.customer_id = l.customer_id
LEFT JOIN dim_campaign c ON c.campaign_id = l.campaign_id
LEFT JOIN dim_platform p ON p.platform_id = c.platform_id
JOIN historical_customer_orders hco ON hco.lead_id = l.lead_id
JOIN lead_conversions lc ON lc.lead_id = l.lead_id;

-- Add Primary Key to ML table
ALTER TABLE ml_lead_conversion_dataset ADD PRIMARY KEY (lead_id);

-- ============================================================================
-- CLASS BALANCE AND SPLIT SUMMARY REPORT
-- ============================================================================
SELECT '==================================================' AS divider;
SELECT '        ML DATASET CLASS BALANCE & SPLIT REPORT    ' AS title;
SELECT '==================================================' AS divider;

SELECT 
    dataset_split,
    COUNT(*) AS total_samples,
    SUM(converted_within_14d) AS positive_converted,
    COUNT(*) - SUM(converted_within_14d) AS negative_unconverted,
    ROUND((SUM(converted_within_14d)::NUMERIC / COUNT(*) * 100.0), 2) AS positive_class_pct
FROM ml_lead_conversion_dataset
GROUP BY dataset_split
ORDER BY dataset_split DESC;

SELECT 
    'OVERALL TOTAL' AS dataset_split,
    COUNT(*) AS total_samples,
    SUM(converted_within_14d) AS positive_converted,
    COUNT(*) - SUM(converted_within_14d) AS negative_unconverted,
    ROUND((SUM(converted_within_14d)::NUMERIC / COUNT(*) * 100.0), 2) AS positive_class_pct
FROM ml_lead_conversion_dataset;
