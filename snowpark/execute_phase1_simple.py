"""
Phase 1 Execution Script (Simplified)
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

def initialize_database(session: Session):
    """Initialize database and schemas using direct SQL execution"""
    try:
        logger.info("Creating database and schemas...")
        
        # Create database
        session.sql("CREATE DATABASE IF NOT EXISTS GLOBAL_SPOILAGE_DB").collect()
        session.sql("USE DATABASE GLOBAL_SPOILAGE_DB").collect()
        
        # Create schemas
        session.sql("CREATE SCHEMA IF NOT EXISTS RAW").collect()
        session.sql("CREATE SCHEMA IF NOT EXISTS CORE").collect()
        session.sql("CREATE SCHEMA IF NOT EXISTS FEAT").collect()
        session.sql("CREATE SCHEMA IF NOT EXISTS ML").collect()
        session.sql("CREATE SCHEMA IF NOT EXISTS OPS").collect()
        
        # Create audit table
        session.sql("""
            CREATE OR REPLACE TABLE OPS.LOAD_AUDIT (
                execution_id STRING,
                phase STRING,
                step STRING,
                execution_ts TIMESTAMP,
                status STRING,
                rows_affected INTEGER,
                execution_time_seconds FLOAT,
                error_message STRING,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
            )
        """).collect()
        
        # Create warehouse
        session.sql("""
            CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
            WAREHOUSE_SIZE = 'SMALL'
            AUTO_SUSPEND = 300
            AUTO_RESUME = TRUE
            INITIALLY_SUSPENDED = TRUE
        """).collect()
        
        # Grant permissions
        session.sql("GRANT USAGE ON DATABASE GLOBAL_SPOILAGE_DB TO ROLE PUBLIC").collect()
        session.sql("GRANT USAGE ON SCHEMA RAW, CORE, FEAT, ML, OPS TO ROLE PUBLIC").collect()
        session.sql("GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE PUBLIC").collect()
        
        # Create file format
        session.sql("""
            CREATE OR REPLACE FILE FORMAT RAW.CSV_FORMAT
            TYPE = 'CSV'
            FIELD_DELIMITER = ','
            RECORD_DELIMITER = '\n'
            SKIP_HEADER = 1
            FIELD_OPTIONALLY_ENCLOSED_BY = '"'
            TRIM_SPACE = TRUE
            ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
            ESCAPE = 'NONE'
            ESCAPE_UNENCLOSED_FIELD = 'NONE'
            DATE_FORMAT = 'AUTO'
            TIMESTAMP_FORMAT = 'AUTO'
            NULL_IF = ('NULL', 'null', '\\N')
        """).collect()
        
        # Create stage
        session.sql("CREATE OR REPLACE STAGE RAW.KAGGLE_STAGE FILE_FORMAT = RAW.CSV_FORMAT").collect()
        
        # Insert initial audit record
        session.sql("""
            INSERT INTO OPS.LOAD_AUDIT (
                execution_id, phase, step, execution_ts, status, 
                rows_affected, execution_time_seconds, error_message
            ) VALUES (
                'INIT_' || CURRENT_TIMESTAMP()::STRING,
                'PHASE_0',
                'DATABASE_INIT',
                CURRENT_TIMESTAMP(),
                'SUCCESS',
                0,
                0,
                NULL
            )
        """).collect()
        
        logger.info("✅ Database and schemas created successfully")
        return True
        
    except Exception as e:
        logger.error(f"❌ Error creating database: {str(e)}")
        return False

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
        if not initialize_database(session):
            logger.error("❌ Database initialization failed")
            return
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
