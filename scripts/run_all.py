"""
Problem 2: The Marketing Warehouse
File: run_all.py
Description: Turnkey execution harness that runs all Problem 2 stages end-to-end:
             Schema creation -> Data generation -> Audit -> 3NF Redesign -> 
             Migration -> Analytics queries -> Index optimization -> ML Dataset.
"""

import os
import sys
import subprocess
import time

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
os.chdir(BASE_DIR)

PG_HOST = os.environ.get("PGHOST", "localhost")
PG_PORT = os.environ.get("PGPORT", "5432")
PG_USER = os.environ.get("PGUSER", "postgres")
PG_PASSWORD = os.environ.get("PGPASSWORD", "root")
PG_DATABASE = os.environ.get("PGDATABASE", "meridian_warehouse")

PSQL_PATH = os.environ.get("PSQL_PATH", r"C:\Program Files\PostgreSQL\19\bin\psql.exe")

def run_cmd(cmd, env_vars=None):
    env = os.environ.copy()
    if env_vars:
        env.update(env_vars)
    env["PGPASSWORD"] = PG_PASSWORD
    print(f"\n[EXEC] {' '.join(cmd)}")
    start = time.time()
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)
    elapsed = time.time() - start
    if result.returncode != 0:
        print(f"[ERROR] (Exit code {result.returncode} in {elapsed:.2f}s):\n{result.stderr}")
        sys.exit(result.returncode)
    else:
        print(f"[OK] (Completed in {elapsed:.2f}s)")
        if result.stdout.strip():
            print(result.stdout)
    return result.stdout

def run_sql_file(file_path):
    cmd = [
        PSQL_PATH,
        "-h", PG_HOST,
        "-p", PG_PORT,
        "-U", PG_USER,
        "-d", PG_DATABASE,
        "-f", file_path
    ]
    return run_cmd(cmd)

def main():
    print("=" * 70)
    print("  HORRAZON AI TECHNICAL ASSESSMENT - PROBLEM 2: MARKETING WAREHOUSE")
    print("  Automated Turnkey Orchestration Harness")
    print("=" * 70)

    # 1. Generate Legacy 50,000 messy rows
    print("\n--- PHASE 1: GENERATING 50,000 MESSY ROWS ---")
    gen_script = os.path.join(BASE_DIR, "scripts", "generate_legacy_data.py")
    run_cmd([sys.executable, gen_script])

    # 2. Run Audit Queries (Part A)
    print("\n--- PHASE 2: RUNNING DIAGNOSTIC AUDIT QUERIES ---")
    run_sql_file(os.path.join(BASE_DIR, "sql", "02_audit_queries.sql"))

    # 3. Apply 3NF Schema (Part B)
    print("\n--- PHASE 3: APPLYING 3NF RELATIONAL SCHEMA ---")
    run_sql_file(os.path.join(BASE_DIR, "sql", "03_new_schema.sql"))

    # 4. Run Migration and Control Totals (Part C)
    print("\n--- PHASE 4: RUNNING ELT MIGRATION & CONTROL RECONCILIATION ---")
    run_sql_file(os.path.join(BASE_DIR, "sql", "04_migration.sql"))

    # 5. Execute 8 Analytics Queries (Part D)
    print("\n--- PHASE 5: EXECUTING 8 PRODUCTION ANALYTICS QUERIES ---")
    run_sql_file(os.path.join(BASE_DIR, "sql", "05_analytics_queries.sql"))

    # 6. Apply Performance Indexes (Part E)
    print("\n--- PHASE 6: APPLYING PERFORMANCE INDEXES ---")
    run_sql_file(os.path.join(BASE_DIR, "sql", "06_performance_indexes.sql"))

    # 7. Generate ML-Ready Dataset (Part F)
    print("\n--- PHASE 7: BUILDING ML-READY DATASET (LEAD CONVERSION) ---")
    run_sql_file(os.path.join(BASE_DIR, "ml", "generate_ml_dataset.sql"))

    print("\n" + "=" * 70)
    print("  ALL PROBLEM 2 STAGES EXECUTED AND VERIFIED SUCCESSFULLY!")
    print("=" * 70)

if __name__ == "__main__":
    main()
