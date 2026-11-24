# Part A: Audit of Meridian Threads' Legacy Warehouse
**Repository**: `problem2-warehouse`  
**Dataset**: `marketing_sales_master` (50,000 messy rows)

---

## Executive Summary
Meridian Threads' legacy data architecture relies on a single denormalized table (`marketing_sales_master`) without primary keys, foreign keys, constraints, or indexes. By commingling top-of-funnel ad spend, middle-of-funnel lead attribution, and bottom-of-funnel order line items, the data layer suffers from massive Cartesian explosion, floating-point precision loss, and unstructured string attributes.

---

## The 6 Critical Defects & Audit Findings

| # | Defect Category | Technical Evidence | Business & Financial Impact |
|---|---|---|---|
| **1** | **Cartesian Explosion & Ad Spend Duplication** | Naive `SUM(ad_spend)` yields **₹13.94 Crore** vs. actual distinct daily spend of **₹1.31 Crore** (a **10.61x inflation multiplier**). | Marketing leadership believes ROAS is 0.25x when true ROAS is ~2.7x. Profitable growth campaigns would be cancelled erroneously. |
| **2** | **IEEE-754 Floating-Point Inaccuracy** | Currencies (`ad_spend`, `unit_price`, `order_total`) stored as `FLOAT`, producing artifacts like `217969.99999999997` and `241394.99999999997`. | Statutory compliance failure. Financial ledgers fail to balance against bank statements and payment gateway settlements by paise/cents. |
| **3** | **VARCHAR Storage for Quantifiable Metrics** | `impressions` (231 rows), `clicks` (224 rows), `qty` (2,226 rows), and `gst_percent` (45,800 rows) contain strings (`'12,500'`, `'two'`, `'12%'`). | Standard SQL analytical queries (`SUM`, `AVG`) throw runtime type-cast exceptions, crashing BI reports and pipelines. |
| **4** | **Unstructured Packed Hierarchies (`category_path`)** | Categories stored as raw strings (e.g. `'Men > Shirts > Linen'`, `'Women > Ethnic > Sarees > Silk'`). | Substring matching (`LIKE '%Shirts%'`) is slow, non-sargable, and misclassifies items (e.g. T-Shirts under Formal Shirts), breaking category rollups. |
| **5** | **Dirty Enums & Inconsistent Casing/Whitespace** | `order_status` has 11 distinct spellings/casings (4,125 `CANCELED`, 4,260 `CANCELLED`, 4,164 `Cancelled`, 3,903 `delivered`, etc.). | Filtering `WHERE order_status = 'CANCELLED'` silently misses 66% of cancellations, artificially inflating gross revenue and triggering tax overpayment. |
| **6** | **Absence of Integrity Constraints & Line Discrepancies** | 1,131 orders exhibit total mismatches against line items, and 133 orders are recorded in paise (> ₹50,000) rather than rupees. | Customers receive erroneous invoices, causing payment disputes, credit card chargebacks, and legal liability. |

---

## Audit Queries & Verification
All audit queries are saved in [sql/02_audit_queries.sql](../sql/02_audit_queries.sql) and can be executed via:
```bash
psql -U postgres -d meridian_warehouse -f sql/02_audit_queries.sql
```
