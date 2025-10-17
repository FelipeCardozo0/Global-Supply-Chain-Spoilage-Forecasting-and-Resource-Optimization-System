"""
Kaggle Data Loader for Global Supply Chain Spoilage Forecasting
Downloads and loads all required datasets from Kaggle into Snowflake
"""

import os
import json
import pandas as pd
import zipfile
from pathlib import Path
from kaggle.api.kaggle_api_extended import KaggleApi
from snowflake.snowpark import Session
from snowflake.snowpark.types import StructType, StructField, StringType, FloatType, DateType, TimestampType
import logging
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class KaggleDataLoader:
    def __init__(self, session: Session):
        self.session = session
        self.kaggle_api = KaggleApi()
        self.kaggle_api.authenticate()
        
        # Dataset configurations
        self.datasets = {
            'fedfunds': {
                'kaggle_path': 'federalreserve/effective-federal-funds-rate',
                'table_name': 'RAW.FEDFUNDS',
                'description': 'Federal Funds Rate data'
            },
            'retail_sales': {
                'kaggle_path': 'swatih/fred-u-s-advance-retail-sales-dataset',
                'table_name': 'RAW.RETAIL_SALES',
                'description': 'US Advance Retail Sales'
            },
            'macro_economic': {
                'kaggle_path': 'alfredkondoro/u-s-economic-indicators-1974-2024',
                'table_name': 'RAW.MACRO_ECONOMIC',
                'description': 'US Economic Indicators 1974-2024'
            },
            'macro_fred': {
                'kaggle_path': 'devarshraval/us-macroeconomic-data-19962020-source-fred',
                'table_name': 'RAW.MACRO_FRED',
                'description': 'US Macroeconomic Data 1996-2020 (FRED)'
            },
            'treasury': {
                'kaggle_path': 'federalreserve/us-treasury-securities-held-by-the-federal-reserve',
                'table_name': 'RAW.TREASURY',
                'description': 'US Treasury Securities held by Federal Reserve'
            },
            'climate_change': {
                'kaggle_path': 'theworldbank/world-bank-climate-change-data',
                'table_name': 'RAW.CLIMATE_CHANGE',
                'description': 'World Bank Climate Change Data'
            },
            'wdi': {
                'kaggle_path': 'theworldbank/world-development-indicators',
                'table_name': 'RAW.WDI',
                'description': 'World Development Indicators'
            },
            'world_bank': {
                'kaggle_path': 'gemartin/world-bank-data-1960-to-2016',
                'table_name': 'RAW.WORLD_BANK',
                'description': 'World Bank Data 1960-2016'
            }
        }
    
    def download_dataset(self, dataset_key: str, download_path: str = './kaggle_data'):
        """Download a specific dataset from Kaggle"""
        try:
            dataset_config = self.datasets[dataset_key]
            kaggle_path = dataset_config['kaggle_path']
            
            logger.info(f"Downloading {dataset_key}: {kaggle_path}")
            
            # Create download directory
            Path(download_path).mkdir(parents=True, exist_ok=True)
            
            # Download dataset
            self.kaggle_api.dataset_download_files(
                dataset=kaggle_path,
                path=download_path,
                unzip=True
            )
            
            logger.info(f"Successfully downloaded {dataset_key}")
            return True
            
        except Exception as e:
            logger.error(f"Error downloading {dataset_key}: {str(e)}")
            return False
    
    def load_csv_to_snowflake(self, dataset_key: str, csv_file_path: str):
        """Load a CSV file into Snowflake table"""
        try:
            dataset_config = self.datasets[dataset_key]
            table_name = dataset_config['table_name']
            
            logger.info(f"Loading {csv_file_path} to {table_name}")
            
            # Read CSV to get structure
            df = pd.read_csv(csv_file_path, nrows=5)  # Read first 5 rows for structure
            
            # Create table if not exists
            self._create_table_from_dataframe(df, table_name)
            
            # Load data using Snowflake COPY command
            stage_name = f"@RAW.KAGGLE_STAGE/{Path(csv_file_path).name}"
            
            # Upload file to stage
            self.session.file.put(csv_file_path, "@RAW.KAGGLE_STAGE", auto_compress=False, overwrite=True)
            
            # Copy data to table
            copy_sql = f"""
            COPY INTO {table_name}
            FROM {stage_name}
            FILE_FORMAT = (FORMAT_NAME = 'RAW.CSV_FORMAT')
            ON_ERROR = 'CONTINUE'
            """
            
            result = self.session.sql(copy_sql).collect()
            logger.info(f"Loaded {len(result)} rows to {table_name}")
            
            # Log to audit table
            self._log_operation(dataset_key, 'LOAD', 'SUCCESS', len(result))
            
            return True
            
        except Exception as e:
            logger.error(f"Error loading {dataset_key}: {str(e)}")
            self._log_operation(dataset_key, 'LOAD', 'FAILED', 0, str(e))
            return False
    
    def _create_table_from_dataframe(self, df: pd.DataFrame, table_name: str):
        """Create Snowflake table based on DataFrame structure"""
        try:
            # Generate CREATE TABLE statement
            columns = []
            for col in df.columns:
                col_clean = col.replace(' ', '_').replace('-', '_').replace('(', '').replace(')', '').upper()
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
            
            self.session.sql(create_sql).collect()
            logger.info(f"Created table {table_name}")
            
        except Exception as e:
            logger.error(f"Error creating table {table_name}: {str(e)}")
            raise
    
    def _log_operation(self, dataset: str, operation: str, status: str, rows_affected: int = 0, error_message: str = None):
        """Log operation to audit table"""
        try:
            audit_sql = f"""
            INSERT INTO OPS.LOAD_AUDIT 
            SELECT 
                '{dataset}_{operation}_{datetime.now().strftime("%Y%m%d_%H%M%S")}' AS execution_id,
                'PHASE_1' AS phase,
                '{operation}_{dataset}' AS step,
                CURRENT_TIMESTAMP() AS execution_ts,
                '{status}' AS status,
                {rows_affected} AS rows_affected,
                0 AS execution_time_seconds,
                {f"'{error_message}'" if error_message else "NULL"} AS error_message
            """
            self.session.sql(audit_sql).collect()
        except Exception as e:
            logger.error(f"Error logging operation: {str(e)}")
    
    def load_all_datasets(self, download_path: str = './kaggle_data'):
        """Download and load all datasets"""
        results = {}
        
        for dataset_key in self.datasets.keys():
            logger.info(f"Processing dataset: {dataset_key}")
            
            # Download dataset
            if self.download_dataset(dataset_key, download_path):
                # Find CSV files in download directory
                dataset_dir = Path(download_path) / dataset_key
                if dataset_dir.exists():
                    csv_files = list(dataset_dir.glob('*.csv'))
                    if csv_files:
                        # Load the first CSV file found
                        success = self.load_csv_to_snowflake(dataset_key, str(csv_files[0]))
                        results[dataset_key] = success
                    else:
                        logger.warning(f"No CSV files found for {dataset_key}")
                        results[dataset_key] = False
                else:
                    logger.warning(f"Download directory not found for {dataset_key}")
                    results[dataset_key] = False
            else:
                results[dataset_key] = False
        
        return results

def main():
    """Main execution function"""
    # Load Snowflake configuration
    config_path = 'snowflake_config.json'
    if not os.path.exists(config_path):
        logger.error(f"Snowflake config file not found: {config_path}")
        return
    
    with open(config_path, 'r') as f:
        config = json.load(f)
    
    # Create Snowflake session
    session = Session.builder.configs(config).create()
    
    try:
        # Initialize loader
        loader = KaggleDataLoader(session)
        
        # Load all datasets
        logger.info("Starting Kaggle data loading process...")
        results = loader.load_all_datasets()
        
        # Print results
        logger.info("Loading Results:")
        for dataset, success in results.items():
            status = "SUCCESS" if success else "FAILED"
            logger.info(f"  {dataset}: {status}")
        
        # Summary
        success_count = sum(1 for success in results.values() if success)
        total_count = len(results)
        logger.info(f"Completed: {success_count}/{total_count} datasets loaded successfully")
        
    except Exception as e:
        logger.error(f"Error in main execution: {str(e)}")
    finally:
        session.close()

if __name__ == "__main__":
    main()
