-- ============================================================================
-- Problem 2: The Marketing Warehouse
-- File: 01_legacy_schema.sql
-- Description: Meridian Threads' original unnormalized single-table warehouse.
--              Lacks PK, FK, indexes, and normal form guarantees.
-- ============================================================================

DROP TABLE IF EXISTS marketing_sales_master CASCADE;

CREATE TABLE marketing_sales_master (
  id SERIAL,
  record_date VARCHAR(30),
  platform VARCHAR(30),
  campaign_name VARCHAR(200),
  ad_spend FLOAT,
  impressions VARCHAR(20),
  clicks VARCHAR(20),
  lead_id VARCHAR(50),
  lead_name VARCHAR(200),
  lead_phone VARCHAR(20),
  lead_email VARCHAR(200),
  lead_created_at VARCHAR(40),
  order_id VARCHAR(50),
  order_date VARCHAR(30),
  customer_state VARCHAR(100),
  product_sku VARCHAR(50),
  product_name VARCHAR(255),
  category_path VARCHAR(500),   -- 'Men > Shirts > Linen'
  qty VARCHAR(20),
  unit_price FLOAT,
  gst_percent VARCHAR(10),
  order_total FLOAT,
  payment_mode VARCHAR(30),
  order_status VARCHAR(30)
);

COMMENT ON TABLE marketing_sales_master IS 'Legacy denormalized marketing and sales master table for Meridian Threads.';
