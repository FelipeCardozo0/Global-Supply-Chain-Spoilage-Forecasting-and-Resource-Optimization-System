"""
Check RAW table structure
"""

import json
from snowflake.snowpark import Session

# Load config
with open('snowflake_config.json', 'r') as f:
    config = json.load(f)

# Create session
session = Session.builder.configs(config).create()
print("Connected to Snowflake")

# Check RAW table structures
tables = ['FEDFUNDS_DFF', 'RETAIL_SALES', 'TREASURY_10Y', 'WORLD_BANK_DATA']

for table in tables:
    print(f"\n=== {table} ===")
    try:
        # Get column info
        result = session.sql(f"DESCRIBE TABLE RAW.{table}").collect()
        for row in result:
            print(f"  {row[0]}: {row[1]}")
        
        # Get sample data
        sample = session.sql(f"SELECT * FROM RAW.{table} LIMIT 3").collect()
        print(f"  Sample data: {len(sample)} rows")
        if sample:
            print(f"  First row: {sample[0]}")
    except Exception as e:
        print(f"  Error: {e}")

session.close()
print("Disconnected")
