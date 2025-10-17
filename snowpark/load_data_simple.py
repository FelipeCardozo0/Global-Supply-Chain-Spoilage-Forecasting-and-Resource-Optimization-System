"""
Simple Data Loading Script
Loads CSV files into Snowflake with clean table names
"""

import os
import json
import pandas as pd
import logging
from pathlib import Path
from snowflake.snowpark import Session

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/simple_data_loading.log'),
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

def clean_table_name(directory_name):
    """Clean directory name to create valid table name"""
    # Remove special characters and replace with underscores
    clean_name = directory_name.replace(' ', '_').replace('-', '_').replace('[', '').replace(']', '').replace(',', '').replace('.', '').replace('(', '').replace(')', '')
    # Remove multiple underscores
    clean_name = '_'.join([part for part in clean_name.split('_') if part])
    # Limit length and make uppercase
    clean_name = clean_name[:50].upper()
    return clean_name

def load_csv_to_snowflake(session: Session, csv_file_path: str, table_name: str):
    """Load a single CSV file into Snowflake"""
    try:
        logger.info(f"Loading {csv_file_path} -> {table_name}")
        
        # Read CSV to get structure
        df = pd.read_csv(csv_file_path, nrows=5)
        
        # Create table with simple structure
        create_sql = f"""
        CREATE OR REPLACE TABLE {table_name} (
            COL1 STRING,
            COL2 STRING,
            COL3 STRING,
            COL4 STRING,
            COL5 STRING,
            COL6 STRING,
            COL7 STRING,
            COL8 STRING,
            COL9 STRING,
            COL10 STRING,
            LOADED_AT TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
        )
        """
        
        session.sql(create_sql).collect()
        logger.info(f"Created table {table_name}")
        
        # Upload file to stage
        stage_name = f"@RAW.KAGGLE_STAGE/{Path(csv_file_path).name}"
        session.file.put(csv_file_path, "@RAW.KAGGLE_STAGE", auto_compress=False, overwrite=True)
        
        # Copy data to table
        copy_sql = f"""
        COPY INTO {table_name}
        FROM {stage_name}
        FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FORMAT')
        ON_ERROR = 'CONTINUE'
        """
        
        result = session.sql(copy_sql).collect()
        logger.info(f"Loaded data into {table_name}")
        
        return True
        
    except Exception as e:
        logger.error(f"Error loading {csv_file_path}: {str(e)}")
        return False

def main():
    """Main execution function"""
    create_logs_directory()
    
    logger.info("=" * 60)
    logger.info("SIMPLE DATA LOADING INTO SNOWFLAKE")
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
        # Define specific files to load (one from each dataset)
        files_to_load = [
            ("../Effective Federal Funds Rate/DFF.csv", "RAW.FEDFUNDS_DFF"),
            ("../FRED U.S. Advance Retail Sales Dataset/RSXFS.csv", "RAW.RETAIL_SALES"),
            ("../US macro-economic/macrodata.csv", "RAW.MACRO_DATA"),
            ("../US Treasury securities held by the Federal Reserve/TREAS10Y.csv", "RAW.TREASURY_10Y"),
            ("../World Bank Data/countrydata.csv", "RAW.WORLD_BANK_DATA")
        ]
        
        results = {}
        
        for file_path, table_name in files_to_load:
            if os.path.exists(file_path):
                success = load_csv_to_snowflake(session, file_path, table_name)
                results[table_name] = success
            else:
                logger.warning(f"File not found: {file_path}")
                results[table_name] = False
        
        # Report results
        success_count = sum(1 for success in results.values() if success)
        total_count = len(results)
        logger.info(f"Loaded {success_count}/{total_count} files successfully")
        
        for table_name, success in results.items():
            status = "SUCCESS" if success else "FAILED"
            logger.info(f"  {table_name}: {status}")
        
        # Check tables in RAW schema
        tables = session.sql("""
            SELECT TABLE_NAME 
            FROM INFORMATION_SCHEMA.TABLES 
            WHERE TABLE_SCHEMA = 'RAW'
            ORDER BY TABLE_NAME
        """).collect()
        
        logger.info(f"Found {len(tables)} tables in RAW schema:")
        for table in tables:
            table_name = table[0]
            try:
                count_result = session.sql(f"SELECT COUNT(*) FROM RAW.{table_name}").collect()
                row_count = count_result[0][0]
                logger.info(f"  {table_name}: {row_count} rows")
            except Exception as e:
                logger.error(f"  {table_name}: Error counting rows - {str(e)}")
        
        logger.info("Data loading completed!")
        
    except Exception as e:
        logger.error(f"Data loading failed: {str(e)}")
        return
    finally:
        session.close()
        logger.info("Disconnected from Snowflake")

if __name__ == "__main__":
    main()
