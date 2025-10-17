"""
Check ML data structure
"""

import os
import json
import logging
from snowflake.snowpark import Session

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def load_snowflake_config():
    """Load Snowflake configuration"""
    with open('snowflake_config.json', 'r') as f:
        return json.load(f)

def main():
    config = load_snowflake_config()
    session = Session.builder.configs(config).create()
    
    try:
        # Check ML.TRAIN_SET columns
        logger.info("ML.TRAIN_SET columns:")
        train_df = session.table("ML.TRAIN_SET").to_pandas()
        logger.info(f"Columns: {list(train_df.columns)}")
        logger.info(f"Shape: {train_df.shape}")
        logger.info(f"First few rows:")
        logger.info(train_df.head())
        
        # Check ML.VAL_SET columns
        logger.info("\nML.VAL_SET columns:")
        val_df = session.table("ML.VAL_SET").to_pandas()
        logger.info(f"Columns: {list(val_df.columns)}")
        logger.info(f"Shape: {val_df.shape}")
        
        # Check ML.TEST_SET columns
        logger.info("\nML.TEST_SET columns:")
        test_df = session.table("ML.TEST_SET").to_pandas()
        logger.info(f"Columns: {list(test_df.columns)}")
        logger.info(f"Shape: {test_df.shape}")
        
    except Exception as e:
        logger.error(f"Error: {e}")
    finally:
        session.close()

if __name__ == "__main__":
    main()
