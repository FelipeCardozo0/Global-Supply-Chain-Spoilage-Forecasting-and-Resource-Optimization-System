"""
Test Snowflake Connection and Basic SQL
"""

import json
from snowflake.snowpark import Session

# Load config
with open('snowflake_config.json', 'r') as f:
    config = json.load(f)

# Create session
session = Session.builder.configs(config).create()
print("Connected to Snowflake")

# Test basic SQL
try:
    result = session.sql("SELECT CURRENT_DATABASE()").collect()
    print(f"Current database: {result[0][0]}")
except Exception as e:
    print(f"Error: {e}")

# Test creating database
try:
    result = session.sql("CREATE DATABASE IF NOT EXISTS GLOBAL_SPOILAGE_DB").collect()
    print("Database created")
except Exception as e:
    print(f"Database error: {e}")

# Test using database
try:
    result = session.sql("USE DATABASE GLOBAL_SPOILAGE_DB").collect()
    print("Using database")
except Exception as e:
    print(f"Use database error: {e}")

session.close()
print("Disconnected")
