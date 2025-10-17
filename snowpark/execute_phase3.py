"""
Phase 3 Execution Script
Global Supply Chain Spoilage Forecasting Project
Creates engineered features for ML models
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
        logging.FileHandler('logs/phase3_execution.log'),
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

def validate_phase3_setup(session: Session):
    """Validate Phase 3 setup"""
    try:
        logger.info("Validating Phase 3 setup...")
        
        # Check FEAT tables exist
        feat_tables = session.sql("""
            SELECT TABLE_NAME 
            FROM INFORMATION_SCHEMA.TABLES 
            WHERE TABLE_SCHEMA = 'FEAT'
            ORDER BY TABLE_NAME
        """).collect()
        
        expected_tables = ['ROLLING_STATS', 'LAG_FEATURES', 'GROWTH_FEATURES', 'VOLATILITY_FEATURES', 'MASTER_FEATURES', 'FEATURE_AUDIT']
        found_tables = [row[0] for row in feat_tables]
        
        logger.info(f"Found FEAT tables: {found_tables}")
        
        if set(expected_tables).issubset(set(found_tables)):
            logger.info("All required FEAT tables exist")
        else:
            missing = set(expected_tables) - set(found_tables)
            logger.error(f"Missing FEAT tables: {missing}")
            return False
        
        # Check data in MASTER_FEATURES
        master_count = session.sql("SELECT COUNT(*) FROM FEAT.MASTER_FEATURES").collect()
        logger.info(f"MASTER_FEATURES rows: {master_count[0][0]}")
        
        # Check feature audit
        audit_check = session.sql("SELECT * FROM FEAT.FEATURE_AUDIT").collect()
        logger.info("Feature audit summary:")
        for row in audit_check:
            logger.info(f"  {row[0]}: {row[1]} rows, {row[2]} non-null values")
        
        logger.info("Phase 3 validation completed successfully")
        return True
        
    except Exception as e:
        logger.error(f"Phase 3 validation failed: {str(e)}")
        return False

def main():
    """Main execution function"""
    create_logs_directory()
    
    logger.info("=" * 60)
    logger.info("PHASE 3: FEATURE ENGINEERING")
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
        # Step 1: Create engineered features
        logger.info("Step 1: Creating engineered features...")
        execute_sql_file(session, 'snowflake/03_features_simple.sql')
        logger.info("Feature engineering completed")
        
        # Step 2: Validate setup
        logger.info("Step 2: Validating setup...")
        if validate_phase3_setup(session):
            logger.info("Phase 3 completed successfully!")
            logger.info("Next steps:")
            logger.info("  1. Review FEAT tables in Snowflake")
            logger.info("  2. Run Phase 4: ML Data Preparation")
            logger.info("  3. Continue with model training")
        else:
            logger.error("Phase 3 validation failed")
            return
        
    except Exception as e:
        logger.error(f"Phase 3 execution failed: {str(e)}")
        return
    finally:
        session.close()
        logger.info("Disconnected from Snowflake")

if __name__ == "__main__":
    main()
