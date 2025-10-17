-- =====================================================
-- PHASE 4: ML DATA PREPARATION
-- Global Supply Chain Spoilage Forecasting Project
-- =====================================================

USE DATABASE GLOBAL_SPOILAGE_DB;
USE SCHEMA ML;

-- =====================================================
-- 1. TARGET VARIABLE CONSTRUCTION
-- =====================================================

CREATE OR REPLACE TABLE ML.TARGETS AS
SELECT 
    date,
    year,
    month,
    quarter,
    
    -- Continuous target: Spoilage Rate (normalized function of economic indicators)
    CASE 
        WHEN fedfunds_rate IS NOT NULL AND retail_sales IS NOT NULL AND treasury_10y_rate IS NOT NULL THEN
            (fedfunds_rate * 0.3 + retail_volatility_3m * 0.4 + treasury_volatility_3m * 0.3) / 100
        ELSE NULL
    END AS spoilage_rate,
    
    -- Binary target: Spoilage Risk Flag (1 if spoilage_rate >= 75th percentile)
    CASE 
        WHEN fedfunds_rate IS NOT NULL AND retail_sales IS NOT NULL AND treasury_10y_rate IS NOT NULL THEN
            CASE 
                WHEN (fedfunds_rate * 0.3 + retail_volatility_3m * 0.4 + treasury_volatility_3m * 0.3) / 100 >= 
                     PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY (fedfunds_rate * 0.3 + retail_volatility_3m * 0.4 + treasury_volatility_3m * 0.3) / 100) 
                     OVER (PARTITION BY 1) THEN 1
                ELSE 0
            END
        ELSE NULL
    END AS spoilage_risk_flag,
    
    CURRENT_TIMESTAMP() AS created_at

FROM FEAT.MASTER_FEATURES
WHERE date IS NOT NULL;

-- =====================================================
-- 2. TEMPORAL DATA SPLITS
-- =====================================================

-- Training set: 1990-2016 (27 years)
CREATE OR REPLACE TABLE ML.TRAIN_SET AS
SELECT 
    mf.*,
    t.spoilage_rate,
    t.spoilage_risk_flag
FROM FEAT.MASTER_FEATURES mf
LEFT JOIN ML.TARGETS t ON mf.date = t.date
WHERE mf.year BETWEEN 1990 AND 2016;

-- Validation set: 2017-2021 (5 years)
CREATE OR REPLACE TABLE ML.VAL_SET AS
SELECT 
    mf.*,
    t.spoilage_rate,
    t.spoilage_risk_flag
FROM FEAT.MASTER_FEATURES mf
LEFT JOIN ML.TARGETS t ON mf.date = t.date
WHERE mf.year BETWEEN 2017 AND 2021;

-- Test set: 2022-2025 (4 years)
CREATE OR REPLACE TABLE ML.TEST_SET AS
SELECT 
    mf.*,
    t.spoilage_rate,
    t.spoilage_risk_flag
FROM FEAT.MASTER_FEATURES mf
LEFT JOIN ML.TARGETS t ON mf.date = t.date
WHERE mf.year >= 2022;

-- =====================================================
-- 3. FEATURE SCALING PARAMETERS
-- =====================================================

CREATE OR REPLACE TABLE ML.SCALER_PARAMS AS
SELECT 
    'fedfunds_rate' AS feature_name,
    AVG(fedfunds_rate) AS mean_value,
    STDDEV(fedfunds_rate) AS std_value,
    MIN(fedfunds_rate) AS min_value,
    MAX(fedfunds_rate) AS max_value
FROM ML.TRAIN_SET
WHERE fedfunds_rate IS NOT NULL

UNION ALL

SELECT 
    'retail_sales' AS feature_name,
    AVG(retail_sales) AS mean_value,
    STDDEV(retail_sales) AS std_value,
    MIN(retail_sales) AS min_value,
    MAX(retail_sales) AS max_value
FROM ML.TRAIN_SET
WHERE retail_sales IS NOT NULL

UNION ALL

SELECT 
    'treasury_10y_rate' AS feature_name,
    AVG(treasury_10y_rate) AS mean_value,
    STDDEV(treasury_10y_rate) AS std_value,
    MIN(treasury_10y_rate) AS min_value,
    MAX(treasury_10y_rate) AS max_value
FROM ML.TRAIN_SET
WHERE treasury_10y_rate IS NOT NULL

UNION ALL

SELECT 
    'fedfunds_3m_avg' AS feature_name,
    AVG(fedfunds_3m_avg) AS mean_value,
    STDDEV(fedfunds_3m_avg) AS std_value,
    MIN(fedfunds_3m_avg) AS min_value,
    MAX(fedfunds_3m_avg) AS max_value
FROM ML.TRAIN_SET
WHERE fedfunds_3m_avg IS NOT NULL

UNION ALL

SELECT 
    'retail_3m_avg' AS feature_name,
    AVG(retail_3m_avg) AS mean_value,
    STDDEV(retail_3m_avg) AS std_value,
    MIN(retail_3m_avg) AS min_value,
    MAX(retail_3m_avg) AS max_value
FROM ML.TRAIN_SET
WHERE retail_3m_avg IS NOT NULL

UNION ALL

SELECT 
    'treasury_3m_avg' AS feature_name,
    AVG(treasury_3m_avg) AS mean_value,
    STDDEV(treasury_3m_avg) AS std_value,
    MIN(treasury_3m_avg) AS min_value,
    MAX(treasury_3m_avg) AS max_value
FROM ML.TRAIN_SET
WHERE treasury_3m_avg IS NOT NULL;

-- =====================================================
-- 4. FEATURE SELECTION SUMMARY
-- =====================================================

CREATE OR REPLACE TABLE ML.FEATURE_SELECTION_SUMMARY AS
SELECT 
    'fedfunds_rate' AS feature_name,
    'KEPT' AS status,
    'Primary economic indicator' AS reason,
    COUNT(*) AS non_null_count,
    STDDEV(fedfunds_rate) AS variance
FROM ML.TRAIN_SET
WHERE fedfunds_rate IS NOT NULL

UNION ALL

SELECT 
    'retail_sales' AS feature_name,
    'KEPT' AS status,
    'Primary economic indicator' AS reason,
    COUNT(*) AS non_null_count,
    STDDEV(retail_sales) AS variance
FROM ML.TRAIN_SET
WHERE retail_sales IS NOT NULL

UNION ALL

SELECT 
    'treasury_10y_rate' AS feature_name,
    'KEPT' AS status,
    'Primary economic indicator' AS reason,
    COUNT(*) AS non_null_count,
    STDDEV(treasury_10y_rate) AS variance
FROM ML.TRAIN_SET
WHERE treasury_10y_rate IS NOT NULL

UNION ALL

SELECT 
    'fedfunds_3m_avg' AS feature_name,
    'KEPT' AS status,
    'Rolling average feature' AS reason,
    COUNT(*) AS non_null_count,
    STDDEV(fedfunds_3m_avg) AS variance
FROM ML.TRAIN_SET
WHERE fedfunds_3m_avg IS NOT NULL

UNION ALL

SELECT 
    'retail_3m_avg' AS feature_name,
    'KEPT' AS status,
    'Rolling average feature' AS reason,
    COUNT(*) AS non_null_count,
    STDDEV(retail_3m_avg) AS variance
FROM ML.TRAIN_SET
WHERE retail_3m_avg IS NOT NULL

UNION ALL

SELECT 
    'treasury_3m_avg' AS feature_name,
    'KEPT' AS status,
    'Rolling average feature' AS reason,
    COUNT(*) AS non_null_count,
    STDDEV(treasury_3m_avg) AS variance
FROM ML.TRAIN_SET
WHERE treasury_3m_avg IS NOT NULL;

-- =====================================================
-- 5. ML READY MASTER TABLE
-- =====================================================

CREATE OR REPLACE TABLE ML.ML_READY_MASTER AS
SELECT 
    date,
    year,
    month,
    quarter,
    
    -- Primary features
    fedfunds_rate,
    retail_sales,
    treasury_10y_rate,
    
    -- Rolling statistics
    fedfunds_3m_avg,
    fedfunds_6m_avg,
    fedfunds_12m_avg,
    fedfunds_3m_std,
    fedfunds_6m_std,
    fedfunds_12m_std,
    retail_3m_avg,
    retail_6m_avg,
    retail_12m_avg,
    retail_3m_std,
    retail_6m_std,
    retail_12m_std,
    treasury_3m_avg,
    treasury_6m_avg,
    treasury_12m_avg,
    treasury_3m_std,
    treasury_6m_std,
    treasury_12m_std,
    
    -- Lag features
    fedfunds_lag_1m,
    fedfunds_lag_3m,
    fedfunds_lag_6m,
    fedfunds_lag_12m,
    retail_lag_1m,
    retail_lag_3m,
    retail_lag_6m,
    retail_lag_12m,
    treasury_lag_1m,
    treasury_lag_3m,
    treasury_lag_6m,
    treasury_lag_12m,
    
    -- Growth features
    fedfunds_growth_1m,
    fedfunds_growth_3m,
    fedfunds_growth_6m,
    fedfunds_growth_12m,
    retail_growth_1m,
    retail_growth_3m,
    retail_growth_6m,
    retail_growth_12m,
    treasury_growth_1m,
    treasury_growth_3m,
    treasury_growth_6m,
    treasury_growth_12m,
    
    -- Volatility features
    fedfunds_volatility_3m,
    fedfunds_volatility_6m,
    fedfunds_volatility_12m,
    retail_volatility_3m,
    retail_volatility_6m,
    retail_volatility_12m,
    treasury_volatility_3m,
    treasury_volatility_6m,
    treasury_volatility_12m,
    
    -- Derived features
    yield_curve_inversion,
    yield_spread,
    retail_sales_per_capita,
    total_gdp,
    
    -- Target variables
    spoilage_rate,
    spoilage_risk_flag,
    
    -- Split indicators
    CASE 
        WHEN year BETWEEN 1990 AND 2016 THEN 'TRAIN'
        WHEN year BETWEEN 2017 AND 2021 THEN 'VAL'
        WHEN year >= 2022 THEN 'TEST'
        ELSE 'UNKNOWN'
    END AS split_type,
    
    CURRENT_TIMESTAMP() AS created_at

FROM FEAT.MASTER_FEATURES mf
LEFT JOIN ML.TARGETS t ON mf.date = t.date
ORDER BY date;

-- =====================================================
-- 6. DATA QUALITY VALIDATION
-- =====================================================

CREATE OR REPLACE TABLE ML.ML_VALIDATION_SUMMARY AS
SELECT 
    'TRAIN_SET' AS dataset_name,
    COUNT(*) AS total_rows,
    COUNT(CASE WHEN spoilage_rate IS NOT NULL THEN 1 END) AS non_null_targets,
    COUNT(CASE WHEN fedfunds_rate IS NOT NULL THEN 1 END) AS non_null_fedfunds,
    COUNT(CASE WHEN retail_sales IS NOT NULL THEN 1 END) AS non_null_retail,
    COUNT(CASE WHEN treasury_10y_rate IS NOT NULL THEN 1 END) AS non_null_treasury,
    MIN(date) AS min_date,
    MAX(date) AS max_date,
    CURRENT_TIMESTAMP() AS created_at
FROM ML.TRAIN_SET

UNION ALL

SELECT 
    'VAL_SET' AS dataset_name,
    COUNT(*) AS total_rows,
    COUNT(CASE WHEN spoilage_rate IS NOT NULL THEN 1 END) AS non_null_targets,
    COUNT(CASE WHEN fedfunds_rate IS NOT NULL THEN 1 END) AS non_null_fedfunds,
    COUNT(CASE WHEN retail_sales IS NOT NULL THEN 1 END) AS non_null_retail,
    COUNT(CASE WHEN treasury_10y_rate IS NOT NULL THEN 1 END) AS non_null_treasury,
    MIN(date) AS min_date,
    MAX(date) AS max_date,
    CURRENT_TIMESTAMP() AS created_at
FROM ML.VAL_SET

UNION ALL

SELECT 
    'TEST_SET' AS dataset_name,
    COUNT(*) AS total_rows,
    COUNT(CASE WHEN spoilage_rate IS NOT NULL THEN 1 END) AS non_null_targets,
    COUNT(CASE WHEN fedfunds_rate IS NOT NULL THEN 1 END) AS non_null_fedfunds,
    COUNT(CASE WHEN retail_sales IS NOT NULL THEN 1 END) AS non_null_retail,
    COUNT(CASE WHEN treasury_10y_rate IS NOT NULL THEN 1 END) AS non_null_treasury,
    MIN(date) AS min_date,
    MAX(date) AS max_date,
    CURRENT_TIMESTAMP() AS created_at
FROM ML.TEST_SET;

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
    'PHASE4_' || CURRENT_TIMESTAMP()::STRING,
    'PHASE_4',
    'ML_DATA_PREPARATION',
    CURRENT_TIMESTAMP(),
    'SUCCESS',
    (SELECT COUNT(*) FROM ML.ML_READY_MASTER),
    0,
    NULL
);

-- Success message
SELECT 'Phase 4: ML Data Preparation completed successfully!' AS status;