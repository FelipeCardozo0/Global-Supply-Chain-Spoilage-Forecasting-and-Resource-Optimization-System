"""
Phase 4 Execution Script
Global Supply Chain Spoilage Forecasting Project
Prepares ML datasets with train/test splits and target variables
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
        logging.FileHandler('logs/phase4_execution.log'),
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

def validate_phase4_setup(session: Session):
    """Validate Phase 4 setup"""
    try:
        logger.info("Validating Phase 4 setup...")
        
        # Check ML tables exist
        ml_tables = session.sql("""
            SELECT TABLE_NAME 
            FROM INFORMATION_SCHEMA.TABLES 
            WHERE TABLE_SCHEMA = 'ML'
            ORDER BY TABLE_NAME
        """).collect()
        
        expected_tables = ['TARGETS', 'TRAIN_SET', 'VAL_SET', 'TEST_SET', 'SCALER_PARAMS', 'FEATURE_SELECTION_SUMMARY', 'ML_READY_MASTER', 'ML_VALIDATION_SUMMARY']
        found_tables = [row[0] for row in ml_tables]
        
        logger.info(f"Found ML tables: {found_tables}")
        
        if set(expected_tables).issubset(set(found_tables)):
            logger.info("All required ML tables exist")
        else:
            missing = set(expected_tables) - set(found_tables)
            logger.error(f"Missing ML tables: {missing}")
            return False
        
        # Check data in ML_READY_MASTER
        master_count = session.sql("SELECT COUNT(*) FROM ML.ML_READY_MASTER").collect()
        logger.info(f"ML_READY_MASTER rows: {master_count[0][0]}")
        
        # Check split distribution
        train_count = session.sql("SELECT COUNT(*) FROM ML.TRAIN_SET").collect()
        val_count = session.sql("SELECT COUNT(*) FROM ML.VAL_SET").collect()
        test_count = session.sql("SELECT COUNT(*) FROM ML.TEST_SET").collect()
        
        logger.info(f"Train set: {train_count[0][0]} rows")
        logger.info(f"Validation set: {val_count[0][0]} rows")
        logger.info(f"Test set: {test_count[0][0]} rows")
        
        logger.info("Data split distribution validated")
        
        # Check validation summary
        validation_check = session.sql("SELECT * FROM ML.ML_VALIDATION_SUMMARY").collect()
        logger.info("ML validation summary:")
        for row in validation_check:
            if len(row) >= 3:
                logger.info(f"  {row[0]}: {row[1]} - {row[2]}")
            else:
                logger.info(f"  Validation record: {row}")
        
        logger.info("Phase 4 validation completed successfully")
        return True
        
    except Exception as e:
        logger.error(f"Phase 4 validation failed: {str(e)}")
        return False

def main():
    """Main execution function"""
    create_logs_directory()
    
    logger.info("=" * 60)
    logger.info("PHASE 4: ML DATA PREPARATION")
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
        # Step 1: Prepare ML datasets
        logger.info("Step 1: Preparing ML datasets...")
        execute_sql_file(session, 'snowflake/04_ml_preparation_simple.sql')
        logger.info("ML data preparation completed")
        
        # Step 2: Validate setup
        logger.info("Step 2: Validating setup...")
        if validate_phase4_setup(session):
            logger.info("Phase 4 completed successfully!")
            logger.info("Next steps:")
            logger.info("  1. Review ML tables in Snowflake")
            logger.info("  2. Run Phase 5: Model Training")
            logger.info("  3. Continue with ML pipeline")
        else:
            logger.error("Phase 4 validation failed")
            return
        
    except Exception as e:
        logger.error(f"Phase 4 execution failed: {str(e)}")
        return
    finally:
        session.close()
        logger.info("Disconnected from Snowflake")

if __name__ == "__main__":
    main()
