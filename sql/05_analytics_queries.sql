-- ============================================================================
-- Problem 2: The Marketing Warehouse
-- File: 05_analytics_queries.sql
-- Description: Eight production analytical queries built on the 3NF schema,
--              featuring attribution logic, recursive CTE rollups, moving
--              averages over calendar scaffolds, window ranking, and CAC/ROAS.
-- ============================================================================

-- ============================================================================
-- QUERY 1: Weekly CTR and CPC per Campaign
-- ----------------------------------------------------------------------------
-- Purpose: Evaluate campaign engagement and cost efficiency over weekly intervals.
-- Design Choice: Uses NULLIF on denominators to avoid division-by-zero crashes
--                when impressions or clicks are 0 on specific dates.
-- ============================================================================
SELECT 
    c.campaign_id,
    c.campaign_name,
    p.platform_name,
    DATE_TRUNC('week', s.spend_date)::DATE AS week_start_date,
    SUM(s.ad_spend) AS weekly_spend,
    SUM(s.impressions) AS weekly_impressions,
    SUM(s.clicks) AS weekly_clicks,
    -- CTR = clicks / impressions * 100
    ROUND((SUM(s.clicks)::NUMERIC / NULLIF(SUM(s.impressions), 0) * 100.0), 2) AS ctr_percentage,
    -- CPC = spend / clicks
    ROUND((SUM(s.ad_spend) / NULLIF(SUM(s.clicks), 0)), 2) AS cpc_inr
FROM fact_ad_spend_daily s
JOIN dim_campaign c ON c.campaign_id = s.campaign_id
JOIN dim_platform p ON p.platform_id = c.platform_id
GROUP BY c.campaign_id, c.campaign_name, p.platform_name, DATE_TRUNC('week', s.spend_date)
ORDER BY week_start_date DESC, weekly_spend DESC
LIMIT 10;


-- ============================================================================
-- QUERY 2: Rank Campaigns by Net Revenue within Each Platform
-- ----------------------------------------------------------------------------
-- Purpose: Identify top performing campaigns by revenue within Meta and Google.
-- Design Choice: Net revenue strictly excludes CANCELLED and RETURNED orders.
--                Uses DENSE_RANK() window function partitioned by platform.
-- ============================================================================
WITH attributed_orders AS (
    -- Attribute orders to the latest lead created before the order date
    SELECT DISTINCT ON (o.order_id)
        o.order_id,
        o.order_total,
        l.campaign_id
    FROM fact_orders o
    JOIN fact_leads l 
      ON l.customer_id = o.customer_id 
     AND l.created_at <= o.order_date
    WHERE o.order_status NOT IN ('CANCELLED', 'RETURNED')
    ORDER BY o.order_id, l.created_at DESC
)
SELECT 
    p.platform_name,
    DENSE_RANK() OVER (
        PARTITION BY p.platform_name 
        ORDER BY SUM(ao.order_total) DESC
    ) AS campaign_revenue_rank,
    c.campaign_id,
    c.campaign_name,
    COUNT(ao.order_id) AS total_net_orders,
    ROUND(SUM(ao.order_total), 2) AS total_net_revenue
FROM attributed_orders ao
JOIN dim_campaign c ON c.campaign_id = ao.campaign_id
JOIN dim_platform p ON p.platform_id = c.platform_id
GROUP BY p.platform_name, c.campaign_id, c.campaign_name
ORDER BY p.platform_name, campaign_revenue_rank;


-- ============================================================================
-- QUERY 3: Lead-to-Order Conversion Funnel per Campaign (14-Day Window)
-- ----------------------------------------------------------------------------
-- Purpose: Measure lead conversion velocity and efficacy within 14 days.
-- Design Choice: Evaluates whether a customer who generated a lead placed an
--                order between lead_created_at and lead_created_at + 14 days.
-- ============================================================================
WITH lead_conversions AS (
    SELECT 
        l.lead_id,
        l.campaign_id,
        l.customer_id,
        l.created_at AS lead_created_at,
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
    c.campaign_id,
    c.campaign_name,
    COUNT(lc.lead_id) AS total_leads_generated,
    SUM(lc.converted_within_14d) AS leads_converted_14d,
    ROUND((SUM(lc.converted_within_14d)::NUMERIC / NULLIF(COUNT(lc.lead_id), 0) * 100.0), 2) AS conversion_rate_pct
FROM lead_conversions lc
JOIN dim_campaign c ON c.campaign_id = lc.campaign_id
GROUP BY c.campaign_id, c.campaign_name
ORDER BY conversion_rate_pct DESC;


-- ============================================================================
-- QUERY 4: Order Attribution Engine (Latest Lead Prior to Order)
-- ----------------------------------------------------------------------------
-- Purpose: Complete attribution ledger mapping every order to its credit campaign.
-- Design Choice: Uses ROW_NUMBER() partitioned by order_id ordered by lead
--                created_at DESC. Orders without prior leads show as 'Unattributed'.
-- ============================================================================
WITH ranked_leads AS (
    SELECT 
        o.order_id,
        l.campaign_id,
        l.lead_id,
        l.created_at AS lead_time,
        ROW_NUMBER() OVER (
            PARTITION BY o.order_id 
            ORDER BY l.created_at DESC
        ) AS lead_rank
    FROM fact_orders o
    JOIN fact_leads l 
      ON l.customer_id = o.customer_id 
     AND l.created_at <= o.order_date
)
SELECT 
    o.order_id,
    o.order_date,
    o.customer_id,
    o.order_status,
    o.order_total,
    COALESCE(c.campaign_id, 'UNATTRIBUTED') AS attributed_campaign_id,
    COALESCE(c.campaign_name, 'Unattributed Direct / Organic') AS attributed_campaign_name,
    COALESCE(p.platform_name, 'Direct') AS platform_name,
    rl.lead_id AS attributed_lead_id,
    rl.lead_time AS attributed_lead_timestamp
FROM fact_orders o
LEFT JOIN ranked_leads rl ON rl.order_id = o.order_id AND rl.lead_rank = 1
LEFT JOIN dim_campaign c ON c.campaign_id = rl.campaign_id
LEFT JOIN dim_platform p ON p.platform_id = c.platform_id
ORDER BY o.order_date DESC
LIMIT 10;


-- ============================================================================
-- QUERY 5: Daily Spend per Platform with Running Total & 7-Day Moving Average
-- ----------------------------------------------------------------------------
-- Purpose: Monitor marketing cash burn with rolling smoothing.
-- Design Choice: Uses generate_series() calendar scaffold crossed with dim_platform
--                to ensure dates with ZERO spend are included without time gaps.
-- ============================================================================
WITH date_bounds AS (
    SELECT 
        MIN(spend_date) AS min_dt, 
        MAX(spend_date) AS max_dt 
    FROM fact_ad_spend_daily
),
calendar_scaffold AS (
    SELECT 
        d::DATE AS calendar_date,
        p.platform_id,
        p.platform_name
    FROM date_bounds,
    GENERATE_SERIES(min_dt, max_dt, INTERVAL '1 day') AS d
    CROSS JOIN dim_platform p
),
platform_daily_spend AS (
    SELECT 
        cs.calendar_date,
        cs.platform_name,
        COALESCE(SUM(s.ad_spend), 0.00) AS daily_spend
    FROM calendar_scaffold cs
    LEFT JOIN dim_campaign c ON c.platform_id = cs.platform_id
    LEFT JOIN fact_ad_spend_daily s 
           ON s.campaign_id = c.campaign_id 
          AND s.spend_date = cs.calendar_date
    GROUP BY cs.calendar_date, cs.platform_name
)
SELECT 
    calendar_date,
    platform_name,
    daily_spend,
    -- Running Cumulative Spend
    ROUND(SUM(daily_spend) OVER (
        PARTITION BY platform_name 
        ORDER BY calendar_date
    ), 2) AS running_total_spend,
    -- 7-Day Moving Average (Trailing 6 days + current day)
    ROUND(AVG(daily_spend) OVER (
        PARTITION BY platform_name 
        ORDER BY calendar_date 
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2) AS moving_avg_7d_spend
FROM platform_daily_spend
ORDER BY calendar_date DESC, platform_name
LIMIT 14;


-- ============================================================================
-- QUERY 6: Identify Duplicate Leads (Same Phone) and Retain Earliest
-- ----------------------------------------------------------------------------
-- Purpose: Deduplicate leads arriving from repeat form fills or multi-touch ads.
-- Design Choice: Window function ROW_NUMBER() partitioned by clean_phone.
-- ============================================================================
WITH deduplicated_leads AS (
    SELECT 
        l.lead_id,
        c.clean_phone,
        c.full_name,
        l.campaign_id,
        l.created_at,
        ROW_NUMBER() OVER (
            PARTITION BY c.clean_phone 
            ORDER BY l.created_at ASC
        ) AS lead_occurrence_order
    FROM fact_leads l
    JOIN dim_customer c ON c.customer_id = l.customer_id
)
SELECT 
    lead_id,
    clean_phone,
    full_name,
    campaign_id,
    created_at AS lead_timestamp,
    lead_occurrence_order,
    CASE 
        WHEN lead_occurrence_order = 1 THEN 'PRIMARY_EARLIEST (RETAINED)'
        ELSE 'DUPLICATE (PRUNED)'
    END AS deduplication_action
FROM deduplicated_leads
WHERE clean_phone IN (
    -- Filter to phones that actually have duplicates to demonstrate the logic
    SELECT c.clean_phone 
    FROM fact_leads l2
    JOIN dim_customer c ON c.customer_id = l2.customer_id
    GROUP BY c.clean_phone
    HAVING COUNT(*) > 1
)
ORDER BY clean_phone, lead_occurrence_order
LIMIT 12;


-- ============================================================================
-- QUERY 7: Net Revenue Rolled Up Category Hierarchy (Recursive CTE)
-- ----------------------------------------------------------------------------
-- Purpose: Aggregate item revenues from subcategories up through parent departments.
-- Design Choice: Recursive CTE traverser maps leaf products up to parent and
--                root categories, allowing hierarchical drill-down and rollups.
-- ============================================================================
WITH RECURSIVE category_tree AS (
    -- Base Case: Every category mapped to itself as leaf/origin
    SELECT 
        category_id AS ancestor_id,
        category_name AS ancestor_name,
        parent_category_id,
        depth_level,
        full_path,
        category_id AS origin_category_id
    FROM dim_category
    
    UNION ALL
    
    -- Recursive Step: Link descendant origins to ancestors higher up the hierarchy
    SELECT 
        p.category_id AS ancestor_id,
        p.category_name AS ancestor_name,
        p.parent_category_id,
        p.depth_level,
        p.full_path,
        ct.origin_category_id
    FROM category_tree ct
    JOIN dim_category p ON p.category_id = ct.parent_category_id
),
origin_category_revenue AS (
    -- Net item revenue by direct product category
    SELECT 
        p.category_id AS origin_category_id,
        SUM(i.item_total) AS direct_net_revenue,
        COUNT(DISTINCT o.order_id) AS direct_order_count
    FROM fact_order_items i
    JOIN fact_orders o ON o.order_id = i.order_id
    JOIN dim_product p ON p.product_id = i.product_id
    WHERE o.order_status NOT IN ('CANCELLED', 'RETURNED')
    GROUP BY p.category_id
)
SELECT 
    ct.depth_level,
    ct.ancestor_id AS category_id,
    ct.ancestor_name AS category_name,
    ct.full_path,
    COUNT(DISTINCT r.origin_category_id) AS contributing_subcategories,
    COALESCE(ROUND(SUM(r.direct_net_revenue), 2), 0.00) AS rolled_up_net_revenue
FROM category_tree ct
LEFT JOIN origin_category_revenue r ON r.origin_category_id = ct.origin_category_id
GROUP BY ct.depth_level, ct.ancestor_id, ct.ancestor_name, ct.full_path
ORDER BY ct.depth_level ASC, rolled_up_net_revenue DESC;


-- ============================================================================
-- QUERY 8: Monthly CAC and ROAS by Campaign (First-Ever Customer Attribution)
-- ----------------------------------------------------------------------------
-- Purpose: Compute executive CAC and ROAS by month, where new customers
--          are defined strictly by their first-ever order date.
-- Design Choice: CTE cohorts first-ever order date per customer, attributes
--                orders to campaign, and aggregates with monthly campaign ad spend.
-- ============================================================================
WITH customer_first_orders AS (
    -- Identify the lifetime first order date for each customer
    SELECT 
        customer_id,
        MIN(order_date) AS first_order_date
    FROM fact_orders
    WHERE order_status NOT IN ('CANCELLED', 'RETURNED')
    GROUP BY customer_id
),
attributed_orders AS (
    -- Attribute orders using the latest lead rule
    SELECT DISTINCT ON (o.order_id)
        o.order_id,
        o.customer_id,
        o.order_date,
        o.order_total,
        l.campaign_id,
        DATE_TRUNC('month', o.order_date)::DATE AS order_month,
        -- Check if this order was the customer's first-ever order
        CASE 
            WHEN DATE_TRUNC('month', o.order_date) = DATE_TRUNC('month', cfo.first_order_date) THEN 1 
            ELSE 0 
        END AS is_first_order_for_customer
    FROM fact_orders o
    JOIN customer_first_orders cfo ON cfo.customer_id = o.customer_id
    JOIN fact_leads l 
      ON l.customer_id = o.customer_id 
     AND l.created_at <= o.order_date
    WHERE o.order_status NOT IN ('CANCELLED', 'RETURNED')
    ORDER BY o.order_id, l.created_at DESC
),
monthly_campaign_orders AS (
    SELECT 
        campaign_id,
        order_month,
        COUNT(order_id) AS total_orders,
        SUM(is_first_order_for_customer) AS new_customers_acquired,
        SUM(order_total) AS net_revenue
    FROM attributed_orders
    GROUP BY campaign_id, order_month
),
monthly_campaign_spend AS (
    SELECT 
        campaign_id,
        DATE_TRUNC('month', spend_date)::DATE AS spend_month,
        SUM(ad_spend) AS total_ad_spend
    FROM fact_ad_spend_daily
    GROUP BY campaign_id, DATE_TRUNC('month', spend_date)
)
SELECT 
    TO_CHAR(s.spend_month, 'YYYY-MM') AS report_month,
    c.campaign_id,
    c.campaign_name,
    p.platform_name,
    ROUND(s.total_ad_spend, 2) AS ad_spend,
    COALESCE(mco.new_customers_acquired, 0) AS new_customers_acquired,
    COALESCE(ROUND(mco.net_revenue, 2), 0.00) AS net_revenue,
    -- CAC = Ad Spend / New Customers Acquired
    ROUND((s.total_ad_spend / NULLIF(mco.new_customers_acquired, 0)), 2) AS cac_inr,
    -- ROAS = Net Revenue / Ad Spend
    ROUND((COALESCE(mco.net_revenue, 0.00) / NULLIF(s.total_ad_spend, 0)), 2) AS roas_multiplier
FROM monthly_campaign_spend s
JOIN dim_campaign c ON c.campaign_id = s.campaign_id
JOIN dim_platform p ON p.platform_id = c.platform_id
LEFT JOIN monthly_campaign_orders mco 
       ON mco.campaign_id = s.campaign_id 
      AND mco.order_month = s.spend_month
ORDER BY report_month DESC, roas_multiplier DESC NULLS LAST
LIMIT 12;
