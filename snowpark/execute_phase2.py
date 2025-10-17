"""
Phase 2 Execution Script
Global Supply Chain Spoilage Forecasting Project
Builds CORE data model with unified time series
"""

import os
import json
import logging
from pathlib import Path
from snowflake.snowpark import Session

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/phase2_execution.log'),
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

def validate_phase2_setup(session: Session):
    """Validate Phase 2 setup"""
    try:
        logger.info("Validating Phase 2 setup...")
        
        # Check CORE tables exist
        core_tables = session.sql("""
            SELECT TABLE_NAME 
            FROM INFORMATION_SCHEMA.TABLES 
            WHERE TABLE_SCHEMA = 'CORE'
            ORDER BY TABLE_NAME
        """).collect()
        
        expected_tables = ['ECONOMIC_INDICATORS', 'COUNTRY_DATA', 'DATE_SPINE', 'UNIFIED_TIME_SERIES', 'DATA_QUALITY_SUMMARY']
        found_tables = [row[0] for row in core_tables]
        
        logger.info(f"Found CORE tables: {found_tables}")
        
        if set(expected_tables).issubset(set(found_tables)):
            logger.info("All required CORE tables exist")
        else:
            missing = set(expected_tables) - set(found_tables)
            logger.error(f"Missing CORE tables: {missing}")
            return False
        
        # Check data in UNIFIED_TIME_SERIES
        unified_count = session.sql("SELECT COUNT(*) FROM CORE.UNIFIED_TIME_SERIES").collect()
        logger.info(f"UNIFIED_TIME_SERIES rows: {unified_count[0][0]}")
        
        # Check data quality
        quality_check = session.sql("SELECT * FROM CORE.DATA_QUALITY_SUMMARY").collect()
        logger.info("Data quality summary:")
        for row in quality_check:
            logger.info(f"  {row[0]}: {row[1]} rows, {row[2]} null values")
        
        logger.info("Phase 2 validation completed successfully")
        return True
        
    except Exception as e:
        logger.error(f"Phase 2 validation failed: {str(e)}")
        return False

def main():
    """Main execution function"""
    create_logs_directory()
    
    logger.info("=" * 60)
    logger.info("PHASE 2: CORE DATA MODEL")
    logger.info("=" * 60)
    
    # Load Snowflake configuration
    config = load_snowflake_config()
    if not config:
        return
    
    # Create Snowflake session
    try:
        session = Session.builder.configs(config).create()
        logger.info("Connected to Snowflake")
    except Exception as e:
        logger.error(f"Failed to connect to Snowflake: {str(e)}")
        return
    
    try:
        # Step 1: Build CORE data model
        logger.info("Step 1: Building CORE data model...")
        execute_sql_file(session, 'snowflake/02_build_core_simple.sql')
        logger.info("CORE data model created")
        
        # Step 2: Validate setup
        logger.info("Step 2: Validating setup...")
        if validate_phase2_setup(session):
            logger.info("Phase 2 completed successfully!")
            logger.info("Next steps:")
            logger.info("  1. Review CORE tables in Snowflake")
            logger.info("  2. Run Phase 3: Feature Engineering")
            logger.info("  3. Continue with ML pipeline")
        else:
            logger.error("Phase 2 validation failed")
            return
        
    except Exception as e:
        logger.error(f"Phase 2 execution failed: {str(e)}")
        return
    finally:
        session.close()
        logger.info("Disconnected from Snowflake")

if __name__ == "__main__":
    main()
