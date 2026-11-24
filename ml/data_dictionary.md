# Part F: Machine Learning Dataset & Feature Engineering Architecture
**Repository**: `problem2-warehouse`  
**Target Table**: `ml_lead_conversion_dataset`  
**Prediction Objective**: *Will this newly captured lead place a confirmed order within 14 days of creation?*

---

## 1. Data Leakage Note

### What is Data Leakage?
Data leakage occurs when information from outside the training dataset or information that would **not** be accessible at inference time (prediction timestamp $T_0$) is erroneously introduced into the model training pipeline. Leakage leads to unrealistically high offline validation scores (e.g., 99% ROC-AUC) that completely collapse in production because the model was trained on future hindsight features.

### Where Leakage Could Have Occurred in This Dataset
1. **Look-Ahead Order History (`prior_orders_count`, `prior_total_spend`)**:
   If we had computed historical orders simply by doing `JOIN fact_orders o ON o.customer_id = l.customer_id` without filtering on `o.order_date < l.created_at`, orders placed on Day 3 or Day 10 *after* the lead was created would be counted in the feature vector. The model would learn a trivial rule: *"if order count > 0, predict 1"*, which is completely invalid for predicting future conversion from Day 0.
2. **Attributed Order Features**:
   Including order-level attributes (such as the value or product category of the converted order) inside the lead's feature vector.
3. **Random K-Fold Cross-Validation**:
   Randomly splitting rows between train and test leaks seasonal campaign dynamics and repeat customer behavior across the time boundary.

### How We Strictly Prevented Leakage
1. **Strict Temporal Point-in-Time Joins ($T_0$)**:
   All historical customer metrics (`prior_orders_count`, `prior_total_spend`, `days_since_last_order`) enforce a hard inequality filter:
   ```sql
   WHERE o.order_date < l.created_at
     AND o.order_status NOT IN ('CANCELLED', 'RETURNED')
   ```
2. **Time-Based Train/Test Split (Temporal Horizon)**:
   Instead of a random shuffle, we enforced a strict time cutoff at `2026-09-15 00:00:00+00`:
   - `TRAIN`: Leads arriving before September 15, 2026 (5,206 records).
   - `TEST`: Leads arriving on or after September 15, 2026 (1,091 records).
   This reflects real production inference where the model is evaluated on unseen future time windows.
3. **Isolated Target Label Window**:
   The target label (`converted_within_14d`) evaluates orders strictly in the 14-day forward window `[l.created_at, l.created_at + INTERVAL '14 days']`, ensuring absolute separation between historical features ($< T_0$) and outcome labels ($> T_0$).

---

## 2. Class Balance & Split Summary

| Split Partition | Time Range | Total Leads | Positive (Converted = 1) | Negative (Unconverted = 0) | Conversion Rate (%) |
|---|---|---|---|---|---|
| **TRAIN** | Aug 1, 2026 – Sep 14, 2026 | **5,206** | 1,622 | 3,584 | **31.16%** |
| **TEST** | Sep 15, 2026 – Sep 30, 2026 | **1,091** | 283 | 808 | **25.94%** |
| **OVERALL** | Full 60-Day Window | **6,297** | **1,905** | **4,392** | **30.25%** |

*Note: The dataset exhibits a realistic ~30% positive conversion class balance, well-suited for classification loss functions (Binary Cross-Entropy / Log-Loss) without requiring synthetic oversampling.*

---

## 3. Handling of Missing Values and Duplicates

1. **Duplicate Leads**:
   Deduplicated at the `lead_id` level using `PRIMARY KEY (lead_id)`. When multiple lead submissions occur for the same customer phone, each distinct lead captures the exact customer state *at that specific point in time*.
2. **First-Time vs. Repeat Customers (`days_since_last_order`)**:
   For leads originating from first-time shoppers who have no prior order history, `latest_prior_order_date` is `NULL`. 
   Rather than dropping these records or using arbitrary mean imputation, we:
   - Imputed `days_since_last_order = -1.00` (a sentinel value indicating absence of history).
   - Added an explicit binary indicator feature `is_repeat_customer` (`1` if prior orders > 0, else `0`), allowing decision trees (XGBoost/LightGBM) to split cleanly on new vs. returning customers.
3. **Data Quality Flags**:
   Invalid or malformed phones and emails were not deleted; instead, binary indicator features (`is_phone_valid`, `is_email_valid`) were created so the ML model can learn if bad contact info correlates with lower conversion rates.

---

## 4. Data Dictionary

| Column Name | Data Type | Nullable | Domain / Allowed Values | Description & ML Purpose |
|---|---|---|---|---|
| `lead_id` | `VARCHAR(50)` | NO | `LEAD-100001` .. | Unique Lead identifier (Primary Key, excluded from feature inputs). |
| `customer_id` | `BIGINT` | NO | Integer > 0 | Foreign key referencing `dim_customer`. |
| `lead_created_at` | `TIMESTAMPTZ` | NO | ISO Timestamps | Exact arrival timestamp ($T_0$) of the lead. |
| `platform_name` | `VARCHAR(50)` | NO | `'Meta'`, `'Google'` | Advertising channel origin (Categorical feature). |
| `campaign_id` | `VARCHAR(50)` | YES | `'CMP-01'` .. `'CMP-60'` | Specific campaign ID (Categorical feature for embedding/one-hot). |
| `campaign_name` | `VARCHAR(255)` | YES | Text | Cleaned marketing campaign name. |
| `lead_hour` | `INTEGER` | NO | `0` to `23` | Hour of the day the lead was captured (Time-of-day behavioral signal). |
| `lead_weekday` | `INTEGER` | NO | `0` (Sun) to `6` (Sat) | Day of week the lead arrived (Weekday vs. weekend shopping affinity). |
| `is_phone_valid` | `INTEGER` | NO | `0`, `1` | `1` if phone passed 10-digit Indian regex, `0` if malformed. |
| `is_email_valid` | `INTEGER` | NO | `0`, `1` | `1` if email passed RFC-compliant regex, `0` if malformed/missing. |
| `prior_orders_count` | `BIGINT` | NO | $\ge 0$ | Number of completed orders by this customer *strictly before* $T_0$. |
| `prior_total_spend` | `NUMERIC(12,2)` | NO | $\ge 0.00$ | Cumulative monetary spend (LTV) by customer *strictly before* $T_0$. |
| `days_since_last_order` | `NUMERIC` | NO | $\ge 0.00$ or `-1.00` | Days elapsed since most recent prior order. Imputed to `-1.00` for new shoppers. |
| `is_repeat_customer` | `INTEGER` | NO | `0`, `1` | `1` if customer had placed $\ge 1$ order prior to lead, `0` if net-new. |
| `dataset_split` | `VARCHAR(10)` | NO | `'TRAIN'`, `'TEST'` | Temporal train/test split indicator based on cutoff date `2026-09-15`. |
| **`converted_within_14d`** | `INTEGER` | NO | `0`, `1` | **Target Label**: `1` if customer placed a non-cancelled order within 14 days, else `0`. |
