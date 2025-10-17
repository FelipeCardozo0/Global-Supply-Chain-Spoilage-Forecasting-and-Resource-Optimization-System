-- =====================================================
-- PHASE 2: CORE DATA MODEL (FIXED)
-- Global Supply Chain Spoilage Forecasting Project
-- =====================================================

USE DATABASE GLOBAL_SPOILAGE_DB;
USE SCHEMA CORE;

-- =====================================================
-- 1. ECONOMIC INDICATORS TABLE
-- =====================================================

CREATE OR REPLACE TABLE CORE.ECONOMIC_INDICATORS AS
SELECT 
    'FEDFUNDS' AS indicator_type,
    'Federal Funds Rate' AS indicator_name,
    'US' AS country_iso,
    'US' AS country_name,
    'Monthly' AS frequency,
    TRY_TO_DATE(COL1, 'YYYY-MM-DD') AS date,
    TRY_TO_DOUBLE(COL4) AS value,
    'Federal Reserve' AS source,
    CURRENT_TIMESTAMP() AS created_at
FROM RAW.FEDFUNDS_DFF
WHERE COL1 IS NOT NULL AND COL4 IS NOT NULL

UNION ALL

SELECT 
    'RETAIL_SALES' AS indicator_type,
    'Advance Retail Sales' AS indicator_name,
    'US' AS country_iso,
    'US' AS country_name,
    'Monthly' AS frequency,
    TRY_TO_DATE(COL1, 'MM/DD/YYYY') AS date,
    TRY_TO_DOUBLE(COL2) AS value,
    'FRED' AS source,
    CURRENT_TIMESTAMP() AS created_at
FROM RAW.RETAIL_SALES
WHERE COL1 IS NOT NULL AND COL2 IS NOT NULL

UNION ALL

SELECT 
    'TREASURY_10Y' AS indicator_type,
    '10-Year Treasury Rate' AS indicator_name,
    'US' AS country_iso,
    'US' AS country_name,
    'Monthly' AS frequency,
    TRY_TO_DATE(COL1, 'YYYY-MM-DD') AS date,
    TRY_TO_DOUBLE(COL4) AS value,
    'Federal Reserve' AS source,
    CURRENT_TIMESTAMP() AS created_at
FROM RAW.TREASURY_10Y
WHERE COL1 IS NOT NULL AND COL4 IS NOT NULL;

-- =====================================================
-- 2. COUNTRY DATA TABLE
-- =====================================================

CREATE OR REPLACE TABLE CORE.COUNTRY_DATA AS
SELECT 
    'US' AS country_iso,
    'United States' AS country_name,
    'North America' AS region,
    'High Income' AS income_group,
    331000000 AS population,
    65000 AS gdp_per_capita,
    2.5 AS inflation_rate,
    3.5 AS unemployment_rate,
    CURRENT_TIMESTAMP() AS created_at;

-- =====================================================
-- 3. DATE SPINE FOR CONTINUOUS TIME SERIES
-- =====================================================

CREATE OR REPLACE TABLE CORE.DATE_SPINE AS
SELECT 
    DATEADD('month', SEQ4(), '1990-01-01'::DATE) AS date,
    YEAR(DATEADD('month', SEQ4(), '1990-01-01'::DATE)) AS year,
    MONTH(DATEADD('month', SEQ4(), '1990-01-01'::DATE)) AS month,
    QUARTER(DATEADD('month', SEQ4(), '1990-01-01'::DATE)) AS quarter,
    DAYOFWEEK(DATEADD('month', SEQ4(), '1990-01-01'::DATE)) AS day_of_week,
    DAYOFYEAR(DATEADD('month', SEQ4(), '1990-01-01'::DATE)) AS day_of_year,
    CURRENT_TIMESTAMP() AS created_at
FROM TABLE(GENERATOR(ROWCOUNT => 420))  -- 35 years of monthly data
WHERE DATEADD('month', SEQ4(), '1990-01-01'::DATE) <= CURRENT_DATE();

-- =====================================================
-- 4. UNIFIED TIME SERIES TABLE
-- =====================================================

CREATE OR REPLACE TABLE CORE.UNIFIED_TIME_SERIES AS
SELECT 
    ds.date,
    ds.year,
    ds.month,
    ds.quarter,
    
    -- Federal Funds Rate
    fed.value AS fedfunds_rate,
    
    -- Retail Sales
    retail.value AS retail_sales,
    
    -- Treasury 10Y
    treas.value AS treasury_10y_rate,
    
    -- Country data (using US as default)
    cd.population,
    cd.gdp_per_capita,
    cd.inflation_rate,
    cd.unemployment_rate,
    
    CURRENT_TIMESTAMP() AS created_at

FROM CORE.DATE_SPINE ds

-- Join Federal Funds Rate
LEFT JOIN (
    SELECT date, value 
    FROM CORE.ECONOMIC_INDICATORS 
    WHERE indicator_type = 'FEDFUNDS'
) fed ON ds.date = fed.date

-- Join Retail Sales
LEFT JOIN (
    SELECT date, value 
    FROM CORE.ECONOMIC_INDICATORS 
    WHERE indicator_type = 'RETAIL_SALES'
) retail ON ds.date = retail.date

-- Join Treasury 10Y
LEFT JOIN (
    SELECT date, value 
    FROM CORE.ECONOMIC_INDICATORS 
    WHERE indicator_type = 'TREASURY_10Y'
) treas ON ds.date = treas.date

-- Join Country Data (US)
LEFT JOIN CORE.COUNTRY_DATA cd ON cd.country_iso = 'US'

ORDER BY ds.date;

-- =====================================================
-- 5. CREATE INDEXES FOR PERFORMANCE
-- =====================================================

-- Create indexes on key columns
CREATE INDEX IF NOT EXISTS idx_economic_indicators_date ON CORE.ECONOMIC_INDICATORS(date);
CREATE INDEX IF NOT EXISTS idx_economic_indicators_type ON CORE.ECONOMIC_INDICATORS(indicator_type);
CREATE INDEX IF NOT EXISTS idx_unified_timeseries_date ON CORE.UNIFIED_TIME_SERIES(date);
CREATE INDEX IF NOT EXISTS idx_country_data_iso ON CORE.COUNTRY_DATA(country_iso);

-- =====================================================
-- 6. DATA QUALITY CHECKS
-- =====================================================

-- Check for missing values
CREATE OR REPLACE TABLE CORE.DATA_QUALITY_SUMMARY AS
SELECT 
    'ECONOMIC_INDICATORS' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(CASE WHEN value IS NULL THEN 1 END) AS null_values,
    COUNT(CASE WHEN date IS NULL THEN 1 END) AS null_dates,
    MIN(date) AS min_date,
    MAX(date) AS max_date,
    CURRENT_TIMESTAMP() AS created_at
FROM CORE.ECONOMIC_INDICATORS

UNION ALL

SELECT 
    'UNIFIED_TIME_SERIES' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(CASE WHEN fedfunds_rate IS NULL THEN 1 END) AS null_fedfunds,
    COUNT(CASE WHEN retail_sales IS NULL THEN 1 END) AS null_retail,
    MIN(date) AS min_date,
    MAX(date) AS max_date,
    CURRENT_TIMESTAMP() AS created_at
FROM CORE.UNIFIED_TIME_SERIES;

-- =====================================================
-- 7. AUDIT LOG
-- =====================================================

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
    'PHASE2_' || CURRENT_TIMESTAMP()::STRING,
    'PHASE_2',
    'CORE_DATA_MODEL',
    CURRENT_TIMESTAMP(),
    'SUCCESS',
    (SELECT COUNT(*) FROM CORE.UNIFIED_TIME_SERIES),
    0,
    NULL
);

-- Success message
SELECT 'Phase 2: Core Data Model created successfully!' AS status;
