-- ============================================================================
-- Problem 2: The Marketing Warehouse
-- File: 03_new_schema.sql
-- Description: 3NF Normalized relational schema for Meridian Threads.
--              Includes PKs, FKs, CHECK, UNIQUE, NOT NULL, and NUMERIC types.
-- ============================================================================

-- Clean up any existing tables
DROP TABLE IF EXISTS rejected_migration_rows CASCADE;
DROP TABLE IF EXISTS fact_order_items CASCADE;
DROP TABLE IF EXISTS fact_orders CASCADE;
DROP TABLE IF EXISTS fact_leads CASCADE;
DROP TABLE IF EXISTS dim_customer CASCADE;
DROP TABLE IF EXISTS fact_ad_spend_daily CASCADE;
DROP TABLE IF EXISTS dim_product CASCADE;
DROP TABLE IF EXISTS dim_category CASCADE;
DROP TABLE IF EXISTS dim_campaign CASCADE;
DROP TABLE IF EXISTS dim_platform CASCADE;

-- ----------------------------------------------------------------------------
-- 1. Dimension: Marketing Platform (Meta, Google)
-- ----------------------------------------------------------------------------
CREATE TABLE dim_platform (
    platform_id SERIAL PRIMARY KEY,
    platform_name VARCHAR(50) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_platform_name CHECK (platform_name IN ('Meta', 'Google'))
);

-- ----------------------------------------------------------------------------
-- 2. Dimension: Campaign
-- ----------------------------------------------------------------------------
CREATE TABLE dim_campaign (
    campaign_id VARCHAR(50) PRIMARY KEY,
    platform_id INTEGER NOT NULL REFERENCES dim_platform(platform_id),
    campaign_name VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- 3. Fact: Daily Ad Spend (Campaign level granularity per date)
-- ----------------------------------------------------------------------------
CREATE TABLE fact_ad_spend_daily (
    ad_spend_id BIGSERIAL PRIMARY KEY,
    campaign_id VARCHAR(50) NOT NULL REFERENCES dim_campaign(campaign_id),
    spend_date DATE NOT NULL,
    ad_spend NUMERIC(12, 2) NOT NULL CHECK (ad_spend >= 0.00),
    impressions INTEGER NOT NULL CHECK (impressions >= 0),
    clicks INTEGER NOT NULL CHECK (clicks >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_campaign_spend_date UNIQUE (campaign_id, spend_date)
);

-- ----------------------------------------------------------------------------
-- 4. Dimension: Customer (Deduplicated on 10-digit clean phone)
-- ----------------------------------------------------------------------------
CREATE TABLE dim_customer (
    customer_id BIGSERIAL PRIMARY KEY,
    clean_phone VARCHAR(10) NOT NULL UNIQUE CHECK (clean_phone ~ '^[6-9][0-9]{9}$'),
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    state VARCHAR(100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_customer_email CHECK (email IS NULL OR email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- ----------------------------------------------------------------------------
-- 5. Fact: Leads
-- ----------------------------------------------------------------------------
CREATE TABLE fact_leads (
    lead_id VARCHAR(50) PRIMARY KEY,
    customer_id BIGINT NOT NULL REFERENCES dim_customer(customer_id),
    campaign_id VARCHAR(50) REFERENCES dim_campaign(campaign_id),
    created_at TIMESTAMPTZ NOT NULL,
    lead_hour INTEGER NOT NULL CHECK (lead_hour BETWEEN 0 AND 23),
    lead_weekday INTEGER NOT NULL CHECK (lead_weekday BETWEEN 0 AND 6),
    is_phone_valid BOOLEAN NOT NULL DEFAULT TRUE,
    is_email_valid BOOLEAN NOT NULL DEFAULT TRUE
);

-- ----------------------------------------------------------------------------
-- 6. Dimension: Category (Adjacency List Hierarchical Tree)
-- ----------------------------------------------------------------------------
CREATE TABLE dim_category (
    category_id SERIAL PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL,
    parent_category_id INTEGER REFERENCES dim_category(category_id),
    full_path VARCHAR(500) NOT NULL UNIQUE,
    depth_level INTEGER NOT NULL CHECK (depth_level >= 1)
);

-- ----------------------------------------------------------------------------
-- 7. Dimension: Product
-- ----------------------------------------------------------------------------
CREATE TABLE dim_product (
    product_id SERIAL PRIMARY KEY,
    sku VARCHAR(50) NOT NULL UNIQUE,
    product_name VARCHAR(255) NOT NULL,
    category_id INTEGER NOT NULL REFERENCES dim_category(category_id),
    base_price NUMERIC(10, 2) NOT NULL CHECK (base_price > 0.00),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- 8. Fact: Orders
-- ----------------------------------------------------------------------------
CREATE TABLE fact_orders (
    order_id VARCHAR(50) PRIMARY KEY,
    customer_id BIGINT NOT NULL REFERENCES dim_customer(customer_id),
    order_date TIMESTAMPTZ NOT NULL,
    customer_state VARCHAR(100) NOT NULL,
    payment_mode VARCHAR(50) NOT NULL CHECK (payment_mode IN ('UPI', 'Credit Card', 'Debit Card', 'Cash on Delivery', 'Net Banking')),
    order_status VARCHAR(50) NOT NULL CHECK (order_status IN ('DELIVERED', 'PROCESSING', 'CANCELLED', 'RETURNED')),
    order_total NUMERIC(12, 2) NOT NULL CHECK (order_total >= 0.00),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- 9. Fact: Order Items
-- ----------------------------------------------------------------------------
CREATE TABLE fact_order_items (
    item_id BIGSERIAL PRIMARY KEY,
    order_id VARCHAR(50) NOT NULL REFERENCES fact_orders(order_id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES dim_product(product_id),
    qty INTEGER NOT NULL CHECK (qty > 0),
    unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0.00),
    gst_percent NUMERIC(5, 2) NOT NULL CHECK (gst_percent >= 0.00 AND gst_percent <= 100.00),
    item_subtotal NUMERIC(12, 2) GENERATED ALWAYS AS (ROUND((qty * unit_price), 2)) STORED,
    item_total NUMERIC(12, 2) GENERATED ALWAYS AS (ROUND((qty * unit_price * (1.0 + gst_percent / 100.0)), 2)) STORED
);

-- ----------------------------------------------------------------------------
-- 10. Audit / Quarantine: Rejected Migration Rows
-- ----------------------------------------------------------------------------
CREATE TABLE rejected_migration_rows (
    reject_id BIGSERIAL PRIMARY KEY,
    source_id INTEGER,
    rejection_stage VARCHAR(50) NOT NULL,
    rule_name VARCHAR(100) NOT NULL,
    failure_reason TEXT NOT NULL,
    raw_payload JSONB NOT NULL,
    rejected_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Comments on Normal Forms
COMMENT ON TABLE dim_category IS '1NF & 3NF: Recursive category hierarchy replacing packed strings.';
COMMENT ON TABLE fact_ad_spend_daily IS '2NF & 3NF: Isolates ad spend from orders, eliminating 10x Cartesian inflation.';
COMMENT ON TABLE fact_order_items IS '1NF & 2NF: Granular line-item facts with stored GST and calculated totals.';
