-- =====================================================
-- PHASE 1: DATABASE & SCHEMA INITIALIZATION (SIMPLIFIED)
-- Global Supply Chain Spoilage Forecasting Project
-- =====================================================

-- Create main database
CREATE DATABASE IF NOT EXISTS GLOBAL_SPOILAGE_DB;
USE DATABASE GLOBAL_SPOILAGE_DB;

-- Create schemas for the pipeline
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS CORE;
CREATE SCHEMA IF NOT EXISTS FEAT;
CREATE SCHEMA IF NOT EXISTS ML;
CREATE SCHEMA IF NOT EXISTS OPS;

-- Create audit table for tracking all operations
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
);

-- Create warehouse for processing
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
    WAREHOUSE_SIZE = 'SMALL'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

-- Grant permissions
GRANT USAGE ON DATABASE GLOBAL_SPOILAGE_DB TO ROLE PUBLIC;
GRANT USAGE ON SCHEMA RAW, CORE, FEAT, ML, OPS TO ROLE PUBLIC;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE PUBLIC;

-- Create file format for CSV loading
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
    NULL_IF = ('NULL', 'null', '\\N');

-- Create stage for file uploads
CREATE OR REPLACE STAGE RAW.KAGGLE_STAGE
    FILE_FORMAT = RAW.CSV_FORMAT;

-- Insert initial audit record
INSERT INTO OPS.LOAD_AUDIT (
    execution_id,
    phase,
    step,
    execution_ts,
    status,
    rows_affected,
    execution_time_seconds,
    error_message
) VALUES (
    'INIT_' || CURRENT_TIMESTAMP()::STRING,
    'PHASE_0',
    'DATABASE_INIT',
    CURRENT_TIMESTAMP(),
    'SUCCESS',
    0,
    0,
    NULL
);

-- Success message
SELECT 'Database and schemas created successfully!' AS status;
