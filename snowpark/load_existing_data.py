"""
Load Existing Data Files into Snowflake
Loads all CSV files from the project directory into RAW schema tables
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
        logging.FileHandler('logs/data_loading.log'),
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

def find_csv_files():
    """Find all CSV files in the project directory"""
    csv_files = []
    
    # Define the directories to search (from parent directory)
    directories = [
        "../Effective Federal Funds Rate",
        "../FRED U.S. Advance Retail Sales Dataset", 
        "../US macro-economic",
        "../US macro-economic data [1996-2020], source FRED",
        "../US Treasury securities held by the Federal Reserve",
        "../World Bank Climate Change Data",
        "../World Bank Data",
        "../World Development Indicators"
    ]
    
    for directory in directories:
        if os.path.exists(directory):
            logger.info(f"Searching in: {directory}")
            for file in os.listdir(directory):
                if file.endswith('.csv'):
                    file_path = os.path.join(directory, file)
                    csv_files.append({
                        'path': file_path,
                        'name': file,
                        'directory': directory
                    })
                    logger.info(f"Found CSV: {file}")
    
    return csv_files

def create_table_from_csv(session: Session, csv_file_path: str, table_name: str):
    """Create Snowflake table from CSV file"""
    try:
        logger.info(f"Processing {csv_file_path} -> {table_name}")
        
        # Read CSV to get structure
        df = pd.read_csv(csv_file_path, nrows=5)  # Read first 5 rows for structure
        
        # Generate CREATE TABLE statement
        columns = []
        for col in df.columns:
            col_clean = col.replace(' ', '_').replace('-', '_').replace('(', '').replace(')', '').replace('[', '').replace(']', '').upper()
            if df[col].dtype == 'object':
                columns.append(f"{col_clean} STRING")
            elif 'int' in str(df[col].dtype):
                columns.append(f"{col_clean} INTEGER")
            elif 'float' in str(df[col].dtype):
                columns.append(f"{col_clean} FLOAT")
            else:
                columns.append(f"{col_clean} STRING")
        
        create_sql = f"""
        CREATE OR REPLACE TABLE {table_name} (
            {', '.join(columns)},
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
        logger.error(f"Error processing {csv_file_path}: {str(e)}")
        return False

def load_all_data(session: Session):
    """Load all CSV files into Snowflake"""
    csv_files = find_csv_files()
    
    if not csv_files:
        logger.error("No CSV files found!")
        return False
    
    logger.info(f"Found {len(csv_files)} CSV files to load")
    
    results = {}
    
    for csv_info in csv_files:
        # Create table name from directory
        table_name = csv_info['directory'].replace(' ', '_').replace('-', '_').replace('[', '').replace(']', '').replace(',', '').upper()
        table_name = f"RAW.{table_name}"
        
        success = create_table_from_csv(session, csv_info['path'], table_name)
        results[csv_info['name']] = success
        
        if success:
            logger.info(f"SUCCESS: {csv_info['name']} -> {table_name}")
        else:
            logger.error(f"FAILED: {csv_info['name']} -> {table_name}")
    
    return results

def validate_data_loading(session: Session):
    """Validate that data was loaded successfully"""
    try:
        logger.info("Validating data loading...")
        
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
            count_result = session.sql(f"SELECT COUNT(*) FROM RAW.{table_name}").collect()
            row_count = count_result[0][0]
            logger.info(f"  {table_name}: {row_count} rows")
        
        return True
        
    except Exception as e:
        logger.error(f"Validation failed: {str(e)}")
        return False

def main():
    """Main execution function"""
    create_logs_directory()
    
    logger.info("=" * 60)
    logger.info("LOADING EXISTING DATA FILES INTO SNOWFLAKE")
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
        # Load all data
        logger.info("Loading all CSV files...")
        results = load_all_data(session)
        
        # Report results
        success_count = sum(1 for success in results.values() if success)
        total_count = len(results)
        logger.info(f"Loaded {success_count}/{total_count} files successfully")
        
        for filename, success in results.items():
            status = "SUCCESS" if success else "FAILED"
            logger.info(f"  {filename}: {status}")
        
        # Validate loading
        if validate_data_loading(session):
            logger.info("Data loading validation completed successfully!")
        else:
            logger.error("Data loading validation failed")
        
        logger.info("Data loading completed!")
        
    except Exception as e:
        logger.error(f"Data loading failed: {str(e)}")
        return
    finally:
        session.close()
        logger.info("Disconnected from Snowflake")

if __name__ == "__main__":
    main()
