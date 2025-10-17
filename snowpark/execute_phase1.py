"""
Phase 1 Execution Script
Global Supply Chain Spoilage Forecasting Project
Creates database, loads Kaggle data, and validates setup
"""

import os
import json
import sys
import logging
from pathlib import Path
from snowflake.snowpark import Session
from kaggle_data_loader import KaggleDataLoader

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/phase1_execution.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

def create_logs_directory():
    """Create logs directory if it doesn't exist"""
    Path('logs').mkdir(exist_ok=True)

def load_snowflake_config():
    """Load Snowflake configuration"""
    config_path = 'snowflake_config.json'
    if not os.path.exists(config_path):
        logger.error(f"Snowflake config file not found: {config_path}")
        logger.info("Please create snowflake_config.json with your Snowflake credentials")
        return None
    
    with open(config_path, 'r') as f:
        config = json.load(f)
    
    return config

def execute_sql_file(session: Session, sql_file: str):
    """Execute SQL file and return results"""
    try:
        logger.info(f"Executing SQL file: {sql_file}")
        
        with open(sql_file, 'r') as f:
            sql_content = f.read()
        
        # Split by semicolon and execute each statement
        statements = [stmt.strip() for stmt in sql_content.split(';') if stmt.strip()]
        
        results = []
        for stmt in statements:
            if stmt:
                result = session.sql(stmt).collect()
                results.extend(result)
        
        logger.info(f"Successfully executed {sql_file}")
        return results
        
    except Exception as e:
        logger.error(f"Error executing {sql_file}: {str(e)}")
        raise

def validate_phase1_setup(session: Session):
    """Validate Phase 1 setup"""
    try:
        logger.info("Validating Phase 1 setup...")
        
        # Check database exists
        db_check = session.sql("SELECT CURRENT_DATABASE()").collect()
        logger.info(f"Current database: {db_check[0][0]}")
        
        # Check schemas exist
        schema_check = session.sql("""
            SELECT SCHEMA_NAME 
            FROM INFORMATION_SCHEMA.SCHEMATA 
            WHERE SCHEMA_NAME IN ('RAW', 'CORE', 'FEAT', 'ML', 'OPS')
            ORDER BY SCHEMA_NAME
        """).collect()
        
        expected_schemas = ['RAW', 'CORE', 'FEAT', 'ML', 'OPS']
        found_schemas = [row[0] for row in schema_check]
        
        logger.info(f"Found schemas: {found_schemas}")
        
        if set(expected_schemas).issubset(set(found_schemas)):
            logger.info("✅ All required schemas exist")
        else:
            missing = set(expected_schemas) - set(found_schemas)
            logger.error(f"❌ Missing schemas: {missing}")
            return False
        
        # Check tables in RAW schema
        raw_tables = session.sql("""
            SELECT TABLE_NAME 
            FROM INFORMATION_SCHEMA.TABLES 
            WHERE TABLE_SCHEMA = 'RAW'
            ORDER BY TABLE_NAME
        """).collect()
        
        logger.info(f"RAW tables: {[row[0] for row in raw_tables]}")
        
        # Check audit table
        audit_check = session.sql("SELECT COUNT(*) FROM OPS.LOAD_AUDIT").collect()
        logger.info(f"Audit records: {audit_check[0][0]}")
        
        logger.info("✅ Phase 1 validation completed successfully")
        return True
        
    except Exception as e:
        logger.error(f"❌ Phase 1 validation failed: {str(e)}")
        return False

def main():
    """Main execution function"""
    create_logs_directory()
    
    logger.info("=" * 60)
    logger.info("PHASE 1: DATABASE INITIALIZATION & DATA LOADING")
    logger.info("=" * 60)
    
    # Load Snowflake configuration
    config = load_snowflake_config()
    if not config:
        return
    
    # Create Snowflake session
    try:
        session = Session.builder.configs(config).create()
        logger.info("✅ Connected to Snowflake")
    except Exception as e:
        logger.error(f"❌ Failed to connect to Snowflake: {str(e)}")
        return
    
    try:
        # Step 1: Initialize database and schemas
        logger.info("Step 1: Creating database and schemas...")
        execute_sql_file(session, '00_init_database_simple.sql')
        logger.info("✅ Database and schemas created")
        
        # Step 2: Load Kaggle datasets
        logger.info("Step 2: Loading Kaggle datasets...")
        loader = KaggleDataLoader(session)
        results = loader.load_all_datasets()
        
        # Report results
        success_count = sum(1 for success in results.values() if success)
        total_count = len(results)
        logger.info(f"✅ Loaded {success_count}/{total_count} datasets successfully")
        
        for dataset, success in results.items():
            status = "✅" if success else "❌"
            logger.info(f"  {status} {dataset}")
        
        # Step 3: Validate setup
        logger.info("Step 3: Validating setup...")
        if validate_phase1_setup(session):
            logger.info("🎉 Phase 1 completed successfully!")
            logger.info("Next steps:")
            logger.info("  1. Review loaded data in Snowflake")
            logger.info("  2. Run Phase 2: Core Data Model")
            logger.info("  3. Continue with feature engineering")
        else:
            logger.error("❌ Phase 1 validation failed")
            return
        
    except Exception as e:
        logger.error(f"❌ Phase 1 execution failed: {str(e)}")
        return
    finally:
        session.close()
        logger.info("Disconnected from Snowflake")

if __name__ == "__main__":
    main()
