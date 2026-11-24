"""
Problem 2: The Marketing Warehouse
File: generate_legacy_data.py
Description: Generates 50,000 synthetic messy rows modeling Meridian Threads'
             denormalized marketing_sales_master table.
"""

import sys
import os
import random
from datetime import datetime, timedelta
from collections import defaultdict
import pg8000.native
import pg8000.dbapi

# Set deterministic seed
random.seed(42)

# Configuration
TOTAL_ROWS = 50000
DB_HOST = os.environ.get("PGHOST", "localhost")
DB_PORT = int(os.environ.get("PGPORT", 5432))
DB_USER = os.environ.get("PGUSER", "postgres")
DB_PASSWORD = os.environ.get("PGPASSWORD", "root")
DB_NAME = os.environ.get("PGDATABASE", "meridian_warehouse")

# Seed Master Data
PLATFORMS_RAW = [
    "Meta", "meta", "META ADS", "Meta Ads",
    "Google", "google_ads", "Google Ads", "  Google  "
]

CAMPAIGNS = [
    ("CMP-01", "Diwali Festive Sale", "Meta"),
    ("CMP-02", "Winter Woolens 2026", "Meta"),
    ("CMP-03", "Summer Linen Shirts", "Google"),
    ("CMP-04", "Monsoon Athleisure", "Google"),
    ("CMP-05", "Casual Denims Launch", "Meta"),
    ("CMP-06", "Silk Sarees Premium", "Google"),
    ("CMP-07", "Kids Festive Collection", "Meta"),
    ("CMP-08", "Mens Formal Shirts", "Google"),
    ("CMP-09", "Footwear Clearance", "Meta"),
    ("CMP-10", "Activewear Flash Sale", "Google"),
    ("CMP-11", "Organic Cotton Kurtas", "Meta"),
    ("CMP-12", "Leather Belts & Wallets", "Google"),
    ("CMP-13", "Chinos & Khakis Promo", "Meta"),
    ("CMP-14", "Bridal Wear Special", "Google"),
    ("CMP-15", "College Streetwear Drop", "Meta"),
    ("CMP-16", "Yoga & Gym Trackpants", "Google"),
    ("CMP-17", "Linen Trousers Autumn", "Meta"),
    ("CMP-18", "Pure Pashmina Shawls", "Google"),
    ("CMP-19", "T-Shirts Essentials Pack", "Meta"),
    ("CMP-20", "Designer Dupattas Sale", "Google")
]

CATEGORIES = [
    ("Men > Shirts > Linen", "Men Linen Shirt", 1499.00, "12%"),
    ("Men > Shirts > Cotton", "Men Casual Cotton Shirt", 1199.00, "12%"),
    ("Men > Trousers > Chinos", "Men Slim Fit Chino", 1899.00, "12%"),
    ("Men > Trousers > Jeans", "Men Relaxed Denim", 2199.00, "12%"),
    ("Women > Ethnic > Sarees > Silk", "Banarasi Silk Saree", 4499.00, "5%"),
    ("Women > Ethnic > Sarees > Cotton", "Chanderi Cotton Saree", 2299.00, "5%"),
    ("Women > Ethnic > Kurtas", "Anarkali Embroidered Kurta", 1799.00, "5%"),
    ("Women > Western > Dresses", "Floral Summer Dress", 1699.00, "12%"),
    ("Women > Western > Tops", "Satin Wrap Top", 999.00, "12%"),
    ("Accessories > Belts > Leather", "Genuine Leather Belt", 899.00, "18%"),
    ("Accessories > Bags > Totes", "Canvas Everyday Tote", 799.00, "18%"),
    ("Kids > Boys > Ethnic", "Boys Kurta Pyjama Set", 1299.00, "5%"),
    ("Kids > Girls > Dresses", "Girls Party Frock", 1399.00, "12%")
]

STATES = [
    "Maharashtra", "Karnataka", "Delhi", "Tamil Nadu", "Gujarat",
    "Telangana", "Uttar Pradesh", "West Bengal", "Kerala", "Rajasthan"
]

PAYMENT_MODES = ["UPI", "Credit Card", "Debit Card", "COD", "Cash on Delivery", "Net Banking"]

STATUSES_DIRTY = [
    "DELIVERED", "Delivered", "delivered",
    "PROCESSING", "Processing",
    "CANCELLED", "CANCELED", "Cancelled",
    "RETURNED", "Returned", "returned"
]

FIRST_NAMES = [
    "Aarav", "Vivaan", "Aditya", "Vihaan", "Arjun", "Sai", "Reyansh", "Ayaan", "Krishna", "Ishaan",
    "Diya", "Saanvi", "Aanya", "Aadhya", "Pari", "Ananya", "Myra", "Riya", "Navya", "Kavya",
    "राहुल", "प्रिया", "अमित", "स्नेहा", "विक्रम", "पूजा"
]

LAST_NAMES = [
    "Sharma", "Verma", "Patel", "Reddy", "Nair", "Iyer", "Rao", "Kumar", "Gupta", "Singh",
    "Deshmukh", "Mehta", "Bhatt", "Joshi", "Das", "Chatterjee", "Pillai", "Chauhan"
]

def generate_phone(seed_val, is_dirty=True):
    base_num = 9000000000 + (seed_val % 999999999)
    if not is_dirty:
        return str(base_num)
    choice = seed_val % 7
    if choice == 0:
        return f"+91 {str(base_num)[:5]} {str(base_num)[5:]}"
    elif choice == 1:
        return f"0{base_num}"
    elif choice == 2:
        return f"+91-{base_num}"
    elif choice == 3:
        return f"{str(base_num)[:5]} {str(base_num)[5:]}"
    elif choice == 4:
        return f"91{base_num}"
    elif choice == 5:
        # Invalid phone
        return f"98765" if (seed_val % 100 == 0) else str(base_num)
    return str(base_num)

def generate_email(name, seed_val, is_dirty=True):
    clean_name = "".join(c for c in name.lower() if c.isalnum())
    domains = ["gmail.com", "yahoo.co.in", "outlook.com", "meridianthreads.test"]
    domain = domains[seed_val % len(domains)]
    email = f"{clean_name}{seed_val % 999}@{domain}"
    if is_dirty and (seed_val % 15 == 0):
        return email.upper()
    if is_dirty and (seed_val % 150 == 0):
        return email.replace("@", "_at_") # invalid email
    return email

def generate_date_str(dt, fmt_choice):
    if fmt_choice == 0:
        return dt.strftime("%Y-%m-%d")
    elif fmt_choice == 1:
        return dt.strftime("%d/%m/%Y")
    elif fmt_choice == 2:
        return dt.strftime("%m-%d-%Y")
    else:
        return dt.strftime("%Y.%m.%d")

def main():
    print(f"Connecting to PostgreSQL database '{DB_NAME}' on {DB_HOST}:{DB_PORT} as {DB_USER}...")
    conn = pg8000.native.Connection(
        user=DB_USER,
        password=DB_PASSWORD,
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME
    )

    # 1. Ensure table schema is created
    sql_path = os.path.join(os.path.dirname(__file__), "..", "sql", "01_legacy_schema.sql")
    with open(sql_path, "r", encoding="utf-8") as f:
        schema_sql = f.read()
    print("Executing 01_legacy_schema.sql...")
    for statement in schema_sql.split(";"):
        stmt = statement.strip()
        if stmt:
            conn.run(stmt)

    print("Generating simulated marketing and order entities...")
    # Pre-generate 60 days
    start_date = datetime(2026, 8, 1)
    dates = [start_date + timedelta(days=d) for d in range(60)]

    # Pre-generate daily ad metrics per campaign (to emulate true ad spend before repetition)
    daily_campaign_ads = {}
    for dt in dates:
        dt_str = dt.strftime("%Y-%m-%d")
        for cmp_id, cmp_name, platform in CAMPAIGNS:
            spend = round(random.uniform(500.0, 5000.0), 2)
            impressions = int(spend * random.uniform(8.0, 15.0))
            # Clicks normally 2% - 5% of impressions
            clicks = int(impressions * random.uniform(0.015, 0.05))
            # Anomaly: 1% of ad days have clicks > impressions
            if random.random() < 0.01:
                clicks = impressions + random.randint(10, 50)
            daily_campaign_ads[(dt_str, cmp_id)] = {
                "spend": spend,
                "impressions": impressions,
                "clicks": clicks,
                "platform": platform,
                "campaign_name": cmp_name
            }

    # Pre-generate pool of 8,000 customers
    customers = []
    for i in range(1, 8001):
        first = random.choice(FIRST_NAMES)
        last = random.choice(LAST_NAMES)
        name = f"{first} {last}"
        state = random.choice(STATES)
        phone = generate_phone(i, is_dirty=True)
        email = generate_email(f"{first}_{last}", i, is_dirty=True)
        customers.append({
            "cust_id": i,
            "name": name,
            "phone": phone,
            "email": email,
            "state": state
        })

    # Pre-generate pool of 12,000 leads
    leads = []
    for i in range(1, 12001):
        # 75% of leads tie to an existing customer, 25% are new
        cust = random.choice(customers) if random.random() < 0.75 else None
        lead_dt = start_date + timedelta(days=random.randint(0, 58), hours=random.randint(0, 23), minutes=random.randint(0, 59))
        cmp_id, cmp_name, platform = random.choice(CAMPAIGNS)
        phone = cust["phone"] if cust else generate_phone(20000 + i, is_dirty=True)
        email = cust["email"] if cust else generate_email(f"lead_{i}", i, is_dirty=True)
        name = cust["name"] if cust else f"Lead {i}"
        
        # Lead timestamp formats
        fmt_choice = random.randint(0, 2)
        if fmt_choice == 0:
            lead_created_at = lead_dt.strftime("%Y-%m-%d %H:%M:%S")
        elif fmt_choice == 1:
            lead_created_at = lead_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
        else:
            lead_created_at = lead_dt.strftime("%d/%m/%Y %H:%M")

        leads.append({
            "lead_id": f"LEAD-{100000 + i}",
            "name": name,
            "phone": phone,
            "email": email,
            "created_at_dt": lead_dt,
            "created_at_str": lead_created_at,
            "campaign_id": cmp_id,
            "campaign_name": cmp_name,
            "platform": platform,
            "customer": cust
        })

    # Generate Orders and assemble flat rows
    print(f"Synthesizing {TOTAL_ROWS} rows with deliberate real-world defects...")
    rows_to_insert = []
    order_counter = 1000

    # 1. First add ad-spend baseline rows (where orders didn't happen or purely ad impressions)
    for (dt_str, cmp_id), ad in daily_campaign_ads.items():
        dt = datetime.strptime(dt_str, "%Y-%m-%d")
        fmt = random.randint(0, 3)
        rec_date = generate_date_str(dt, fmt)
        plat = random.choice(PLATFORMS_RAW) if random.random() < 0.3 else ad["platform"]
        # Format impressions and clicks with dirty formats
        imp_str = f"{ad['impressions']:,}" if random.random() < 0.2 else str(ad['impressions'])
        click_str = f" {ad['clicks']} " if random.random() < 0.2 else str(ad['clicks'])

        rows_to_insert.append((
            rec_date, plat, ad["campaign_name"], ad["spend"], imp_str, click_str,
            None, None, None, None, None,
            None, None, None, None, None, None, None, None, None, None, None, None
        ))

    # 2. Add lead records that didn't order yet
    for lead in leads[:3000]:
        dt = lead["created_at_dt"]
        rec_date = generate_date_str(dt, random.randint(0, 3))
        plat = lead["platform"]
        ad_spend_val = daily_campaign_ads.get((dt.strftime("%Y-%m-%d"), lead["campaign_id"]), {}).get("spend", 1500.0)
        rows_to_insert.append((
            rec_date, plat, lead["campaign_name"], ad_spend_val, "1000", "50",
            lead["lead_id"], lead["name"], lead["phone"], lead["email"], lead["created_at_str"],
            None, None, None, None, None, None, None, None, None, None, None, None
        ))

    # Pre-index leads by customer for O(1) retrieval
    from collections import defaultdict
    leads_by_cust_id = defaultdict(list)
    for l in leads:
        if l["customer"]:
            leads_by_cust_id[l["customer"]["cust_id"]].append(l)

    # 3. Add Orders with Order Line Items (repeated spend on every item!)
    while len(rows_to_insert) < TOTAL_ROWS:
        order_counter += 1
        order_id = f"ORD-{order_counter}"
        cust = random.choice(customers)
        order_dt = start_date + timedelta(days=random.randint(2, 59), hours=random.randint(8, 22), minutes=random.randint(0, 59))
        order_date_str = order_dt.strftime("%Y-%m-%d %H:%M:%S")
        rec_date_str = generate_date_str(order_dt, random.randint(0, 3))
        state = cust["state"]
        payment_mode = random.choice(PAYMENT_MODES)
        order_status = random.choice(STATUSES_DIRTY)

        # Look up leads for this customer created prior to order_dt
        potential_leads = leads_by_cust_id.get(cust["cust_id"], [])
        cust_leads = [l for l in potential_leads if l["created_at_dt"] <= order_dt]
        
        # 75% attributed to latest lead, 25% unattributed (organic / direct)
        attributed_lead = None
        if cust_leads and random.random() < 0.75:
            cust_leads.sort(key=lambda x: x["created_at_dt"], reverse=True)
            attributed_lead = cust_leads[0]
            cmp_id = attributed_lead["campaign_id"]
            cmp_name = attributed_lead["campaign_name"]
            platform = attributed_lead["platform"]
        else:
            cmp_id = random.choice(CAMPAIGNS)[0]
            cmp_name = [c[1] for c in CAMPAIGNS if c[0] == cmp_id][0]
            platform = random.choice(["Meta", "Google"])

        # Fetch daily spend for that campaign (which will be erroneously duplicated on each line item!)
        dt_day_str = order_dt.strftime("%Y-%m-%d")
        ad_spend = daily_campaign_ads.get((dt_day_str, cmp_id), {}).get("spend", 2450.0)
        impressions = daily_campaign_ads.get((dt_day_str, cmp_id), {}).get("impressions", 15000)
        clicks = daily_campaign_ads.get((dt_day_str, cmp_id), {}).get("clicks", 600)

        # 1 to 4 items per order
        num_items = random.choices([1, 2, 3, 4], weights=[0.4, 0.35, 0.15, 0.1])[0]
        order_items = []
        calc_order_total = 0.0

        for it in range(num_items):
            cat_path, prod_base, unit_p, gst_str = random.choice(CATEGORIES)
            sku = f"{prod_base[:3].upper()}-{random.randint(100, 999)}"
            prod_name = f"{prod_base} {random.choice(['Classic', 'Premium', 'Regular', 'Standard'])}"
            qty_num = random.choices([1, 2, 3, 4], weights=[0.75, 0.18, 0.05, 0.02])[0]
            
            # Dirty qty string
            if random.random() < 0.05:
                qty_str = f" {qty_num} "
            elif random.random() < 0.005:
                qty_str = "two" if qty_num == 2 else "1"
            else:
                qty_str = str(qty_num)

            # GST calculation
            gst_numeric = float(gst_str.replace("%", "")) / 100.0
            item_total = (qty_num * unit_p) * (1.0 + gst_numeric)
            calc_order_total += item_total

            order_items.append({
                "sku": sku,
                "name": prod_name,
                "cat_path": cat_path,
                "qty": qty_str,
                "unit_price": unit_p,
                "gst_percent": gst_str
            })

        final_order_total = round(calc_order_total, 2)
        # Anomaly: 2% of rows have total mismatch
        if random.random() < 0.02:
            final_order_total = round(calc_order_total + random.choice([-100.0, 50.0, 150.0]), 2)
        # Anomaly: 0.5% recorded in paise instead of rupees
        if random.random() < 0.005:
            final_order_total = final_order_total * 100.0

        # Now append each item row
        for item in order_items:
            if len(rows_to_insert) >= TOTAL_ROWS:
                break
            
            # Dirty platform string variations
            plat_dirty = random.choice(PLATFORMS_RAW) if random.random() < 0.25 else platform
            
            # Dirty campaign casing
            cmp_dirty = cmp_name
            if random.random() < 0.1:
                cmp_dirty = f"  {cmp_name.lower()}  "
            elif random.random() < 0.05:
                cmp_dirty = cmp_name.upper()

            lead_id_val = attributed_lead["lead_id"] if attributed_lead else None
            lead_name_val = attributed_lead["name"] if attributed_lead else None
            lead_phone_val = attributed_lead["phone"] if attributed_lead else cust["phone"]
            lead_email_val = attributed_lead["email"] if attributed_lead else cust["email"]
            lead_created_str = attributed_lead["created_at_str"] if attributed_lead else None

            rows_to_insert.append((
                rec_date_str,
                plat_dirty,
                cmp_dirty,
                ad_spend, # NOTICE: repeated for every item!
                str(impressions),
                str(clicks),
                lead_id_val,
                lead_name_val,
                lead_phone_val,
                lead_email_val,
                lead_created_str,
                order_id,
                order_date_str,
                state,
                item["sku"],
                item["name"],
                item["cat_path"],
                item["qty"],
                item["unit_price"],
                item["gst_percent"],
                final_order_total,
                payment_mode,
                order_status
            ))

    print(f"Prepared {len(rows_to_insert)} total rows. Inserting into PostgreSQL in fast multi-row batches...")
    
    dbapi_conn = pg8000.dbapi.connect(
        user=DB_USER,
        password=DB_PASSWORD,
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME
    )
    cursor = dbapi_conn.cursor()
    
    insert_sql = """
    INSERT INTO marketing_sales_master (
        record_date, platform, campaign_name, ad_spend, impressions, clicks,
        lead_id, lead_name, lead_phone, lead_email, lead_created_at,
        order_id, order_date, customer_state, product_sku, product_name, category_path,
        qty, unit_price, gst_percent, order_total, payment_mode, order_status
    ) VALUES (
        %s, %s, %s, %s, %s, %s,
        %s, %s, %s, %s, %s,
        %s, %s, %s, %s, %s, %s,
        %s, %s, %s, %s, %s, %s
    )
    """
    
    chunk_size = 2000
    for idx in range(0, len(rows_to_insert), chunk_size):
        chunk = rows_to_insert[idx:idx + chunk_size]
        cursor.executemany(insert_sql, chunk)
        dbapi_conn.commit()
        print(f"  Inserted {min(idx + chunk_size, len(rows_to_insert))} / {len(rows_to_insert)} rows...")

    cursor.execute("SELECT COUNT(*) FROM marketing_sales_master;")
    count_res = cursor.fetchone()[0]
    cursor.close()
    dbapi_conn.close()
    print(f"SUCCESS! marketing_sales_master populated with {count_res} rows.")

if __name__ == "__main__":
    main()
