
# Problem 2: The Marketing Warehouse

**Horrazon AI – Round 2 Technical Assessment**  
**Role:** Data Engineering Intern  
**Candidate:** Nitya Arora  
**Project:** Marketing Data Warehouse  
**Database:** PostgreSQL  
**Architecture:** 3NF Relational Database

---

## 1. Project Overview

The Marketing Warehouse project focuses on redesigning a denormalised marketing database into a structured, normalised relational data model.

The original `marketing_sales_master` table combines advertising, CRM, customer, product and order information, resulting in duplicated records, inconsistent data types, update anomalies and unreliable analytical queries.

The project addresses these issues through:

- Database auditing and identification of data quality defects.
- Designing a Third Normal Form (3NF) relational schema.
- Migrating legacy data into the redesigned model.
- Developing analytical SQL queries.
- Optimising query performance using indexes.
- Creating an ML-ready lead conversion dataset while preventing data leakage.

---

## 2. Project Objectives

1. Identify structural and data quality problems in the legacy database.
2. Design a normalised relational database.
3. Implement primary keys, foreign keys and integrity constraints.
4. Migrate and clean historical marketing data.
5. Develop analytical queries for marketing performance.
6. Analyse query performance using EXPLAIN ANALYZE.
7. Prepare a time-aware dataset for lead conversion prediction.

---

## 3. Technology Stack

| Technology | Purpose |
|---|---|
| PostgreSQL | Database management |
| SQL | Schema design and analytical queries |
| Python | Synthetic data generation and migration |
| [Library] | Data processing |
| [Tool] | Database interaction |
| Git | Version control |

---

## 4. Legacy Database Audit

The starting point is the denormalised `marketing_sales_master` table.

### Problems investigated

Document the actual defects identified in your audit.

| No. | Defect | Business impact |
|---|---|---|
| 1 | Missing primary key | [Your finding] |
| 2 | Repeated advertising spend | [Your finding] |
| 3 | Inconsistent data types | [Your finding] |
| 4 | Missing foreign key relationships | [Your finding] |
| 5 | Multiple values packed into category_path | [Your finding] |
| 6 | Duplicate customer and lead information | [Your finding] |

Include the SQL queries used to identify these problems in:

`sql/audit.sql`

---

## 5. Database Architecture – 3NF

The redesigned database separates entities according to their business responsibilities.

### Entity overview

| Entity | Responsibility |
|---|---|
| Campaigns | Advertising campaign information |
| Daily Ad Spend | Campaign-level daily performance |
| Customers | Unique customer records |
| Leads | CRM enquiries |
| Categories | Product category hierarchy |
| Products | Product master data |
| Orders | Customer order information |
| Order Items | Individual products within orders |

### Normalisation

**First Normal Form (1NF)**

[Explain how atomic values and individual records are maintained.]

**Second Normal Form (2NF)**

[Explain how partial dependencies are eliminated.]

**Third Normal Form (3NF)**

[Explain how transitive dependencies are eliminated.]

### Entity Relationship Diagram

Insert your actual ERD here.

The diagram should demonstrate:
- Primary and foreign key relationships.
- One-to-many relationships.
- Customer-to-lead relationships.
- Customer-to-order relationships.
- Order-to-order-item relationships.
- Parent-child category relationships.
- Campaign-to-daily-ad-spend relationships.

---

## 6. Data Migration

The migration process transfers legacy records into the redesigned schema.

### Migration workflow

```text
Legacy Marketing Table
          |
          v
    Data Extraction
          |
          v
   Data Standardisation
          |
          v
   Entity Identification
          |
          v
   Foreign Key Mapping
          |
          v
   Constraint Validation
          |
      +---+---+
      |       |
      v       v
 Successful  Rejected
  Records    Records
      |
      v
 Normalised 3NF Tables
```

### Migration considerations

Document your actual implementation for:

- Customer identification.
- Campaign mapping.
- Product and category extraction.
- Date and timestamp conversion.
- Monetary value conversion.
- Duplicate handling.
- Invalid record rejection.
- Foreign key validation.

### Migration reconciliation

| Metric | Before | After |
|---|---:|---:|
| Total records | [Value] | [Value] |
| Total advertising spend | [Value] | [Value] |
| Total order value | [Value] | [Value] |
| Rejected records | — | [Value] |

Explain differences between source and target totals, particularly the effect of repeated advertising spend in the original table.

---

## 7. Analytical SQL Queries

The warehouse supports eight analytical queries.

| No. | Query | SQL concept |
|---|---|---|
| 1 | Weekly CTR and CPC | Aggregation and NULLIF |
| 2 | Campaign ranking by net revenue | Window functions |
| 3 | Lead-to-order conversion funnel | Joins and conditional aggregation |
| 4 | Order campaign attribution | LATERAL JOIN / window functions |
| 5 | Daily platform spend | Running totals and moving averages |
| 6 | Duplicate lead identification | ROW_NUMBER |
| 7 | Category-level net revenue | Recursive CTE |
| 8 | Monthly CAC and ROAS | Aggregations and CTEs |

All queries are available in:

`sql/queries/`

### Attribution methodology

Orders are attributed to the campaign associated with the customer's latest lead created before the order timestamp.

Orders without a qualifying lead are classified as Unattributed.

---

## 8. Query Performance Optimisation

Query performance is evaluated using PostgreSQL's EXPLAIN ANALYZE.

### Methodology

1. Identify the two slowest analytical queries.
2. Execute EXPLAIN ANALYZE before indexing.
3. Identify expensive scans, joins and sorts.
4. Create appropriate indexes.
5. Execute EXPLAIN ANALYZE again.
6. Compare execution plans and execution times.

### Performance comparison

| Query | Before | After | Improvement |
|---|---:|---:|---:|
| Query 1 | [Time] | [Time] | [Result] |
| Query 2 | [Time] | [Time] | [Result] |

Include the actual execution plans in:

`docs/explain_plans.md`

Also document one index that would not help and explain why.

---

## 9. ML-Ready Lead Conversion Dataset

### Objective

Prepare a dataset to support the prediction task:

**Will a lead place an order within 14 days of becoming a lead?**

The resulting dataset contains one row per lead.

### Feature engineering

Document the actual features implemented.

| Feature | Description |
|---|---|
| Platform | Advertising platform |
| Campaign | Lead acquisition campaign |
| Lead hour | Hour of lead creation |
| Lead weekday | Day of the week |
| Phone validity | Phone validity at lead creation |
| Email validity | Email validity at lead creation |
| Prior orders | Customer orders before lead creation |
| Days since last order | Historical purchase recency |

### Target label

`ordered_within_14_days`

- Yes: qualifying order within 14 days.
- No: no qualifying order within 14 days.

### Time-based split

| Dataset | Selection |
|---|---|
| Training | Leads before the cutoff date |
| Testing | Leads on or after the cutoff date |

### Leakage Prevention

Explain:

- What data leakage means.
- Why post-lead information cannot be used as predictive features.
- How historical customer information is restricted to timestamps before lead creation.
- How the 14-day outcome label is constructed.
- How the training and testing split respects time.

### Class balance

| Label | Count |
|---|---:|
| Converted (Yes) | [Value] |
| Not Converted (No) | [Value] |
| Total | [Value] |

Include your data dictionary and missing-value handling approach.

---

## 10. Project Structure

Document the actual repository structure.

```text
problem2-warehouse/
│
├── README.md
│
├── data/
│   └── [Generated data files]
│
├── scripts/
│   ├── [Data generator]
│   └── [Migration script]
│
├── sql/
│   ├── audit.sql
│   ├── schema.sql
│   ├── migration.sql
│   └── queries/
│       ├── query_01.sql
│       ├── query_02.sql
│       ├── query_03.sql
│       ├── query_04.sql
│       ├── query_05.sql
│       ├── query_06.sql
│       ├── query_07.sql
│       └── query_08.sql
│
├── ml/
│   ├── [Dataset generation script]
│   └── [Data dictionary]
│
├── docs/
│   ├── erd.md
│   └── explain_plans.md
│
└── requirements.txt
```

---

## 11. How to Run

### Prerequisites

- Python 3.9+
- PostgreSQL
- SQL client or pgAdmin
- Required Python dependencies

### Clone the repository

```bash
git clone <YOUR_REPOSITORY_URL>
cd problem2-warehouse
```

### Install dependencies

```bash
pip install -r requirements.txt
```

### Generate synthetic data

```bash
<YOUR_DATA_GENERATION_COMMAND>
```

### Create the database schema

```bash
psql -d <DATABASE_NAME> -f sql/schema.sql
```

### Run migration

```bash
<YOUR_MIGRATION_COMMAND>
```

### Execute analytical queries

```bash
<YOUR_QUERY_EXECUTION_COMMAND>
```

### Generate ML dataset

```bash
<YOUR_ML_DATASET_COMMAND>
```

Replace placeholders with commands verified against your repository.

---

## 12. Key Engineering Concepts Demonstrated

- Relational database design.
- First, Second and Third Normal Forms.
- Referential integrity.
- Data migration and reconciliation.
- Advanced SQL and window functions.
- Recursive Common Table Expressions.
- Indexing and query optimisation.
- Feature engineering.
- Temporal validation.
- Prevention of data leakage.

---

## 13. Assumptions and Limitations

Document the assumptions made during data generation, migration, attribution and revenue calculations.

Also list any incomplete features, known limitations and areas requiring additional validation.

---

## 14. Future Improvements

Potential extensions:

- Incremental warehouse migration.
- Partitioning large fact tables.
- Automated data quality monitoring.
- Materialised views for frequently accessed metrics.
- Advanced indexing strategies.
- Automated ML feature pipelines.
- Integration with Microsoft Fabric or another analytical warehouse.

---

## 15. Conclusion

[Summarise the actual achievements of your warehouse implementation, the improvements over the legacy database, and the engineering concepts demonstrated.]

---

**Horrazon AI – Round 2 Technical Assessment**  
**Problem 2: The Marketing Warehouse**
