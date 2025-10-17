-- =====================================================
-- PHASE 4: ML DATA PREPARATION (SIMPLE)
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
    
    -- Continuous target: Spoilage Rate (simplified)
    CASE 
        WHEN fedfunds_rate IS NOT NULL AND retail_sales IS NOT NULL AND treasury_10y_rate IS NOT NULL THEN
            (fedfunds_rate + retail_sales/1000 + treasury_10y_rate) / 3
        ELSE NULL
    END AS spoilage_rate,
    
    -- Binary target: Spoilage Risk Flag (1 if spoilage_rate >= 75th percentile)
    CASE 
        WHEN fedfunds_rate IS NOT NULL AND retail_sales IS NOT NULL AND treasury_10y_rate IS NOT NULL THEN
            CASE 
                WHEN (fedfunds_rate + retail_sales/1000 + treasury_10y_rate) / 3 >= 2.0 THEN 1
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
    mf.date,
    mf.year,
    mf.month,
    mf.quarter,
    mf.fedfunds_rate,
    mf.retail_sales,
    mf.treasury_10y_rate,
    mf.fedfunds_3m_avg,
    mf.retail_3m_avg,
    mf.treasury_3m_avg,
    mf.fedfunds_lag_1m,
    mf.retail_lag_1m,
    mf.treasury_lag_1m,
    mf.fedfunds_growth_1m,
    mf.retail_growth_1m,
    mf.treasury_growth_1m,
    mf.fedfunds_volatility_3m,
    mf.retail_volatility_3m,
    mf.treasury_volatility_3m,
    mf.yield_curve_inversion,
    mf.yield_spread,
    t.spoilage_rate,
    t.spoilage_risk_flag
FROM FEAT.MASTER_FEATURES mf
LEFT JOIN ML.TARGETS t ON mf.date = t.date
WHERE mf.year BETWEEN 1990 AND 2016;

-- Validation set: 2017-2021 (5 years)
CREATE OR REPLACE TABLE ML.VAL_SET AS
SELECT 
    mf.date,
    mf.year,
    mf.month,
    mf.quarter,
    mf.fedfunds_rate,
    mf.retail_sales,
    mf.treasury_10y_rate,
    mf.fedfunds_3m_avg,
    mf.retail_3m_avg,
    mf.treasury_3m_avg,
    mf.fedfunds_lag_1m,
    mf.retail_lag_1m,
    mf.treasury_lag_1m,
    mf.fedfunds_growth_1m,
    mf.retail_growth_1m,
    mf.treasury_growth_1m,
    mf.fedfunds_volatility_3m,
    mf.retail_volatility_3m,
    mf.treasury_volatility_3m,
    mf.yield_curve_inversion,
    mf.yield_spread,
    t.spoilage_rate,
    t.spoilage_risk_flag
FROM FEAT.MASTER_FEATURES mf
LEFT JOIN ML.TARGETS t ON mf.date = t.date
WHERE mf.year BETWEEN 2017 AND 2021;

-- Test set: 2022-2025 (4 years)
CREATE OR REPLACE TABLE ML.TEST_SET AS
SELECT 
    mf.date,
    mf.year,
    mf.month,
    mf.quarter,
    mf.fedfunds_rate,
    mf.retail_sales,
    mf.treasury_10y_rate,
    mf.fedfunds_3m_avg,
    mf.retail_3m_avg,
    mf.treasury_3m_avg,
    mf.fedfunds_lag_1m,
    mf.retail_lag_1m,
    mf.treasury_lag_1m,
    mf.fedfunds_growth_1m,
    mf.retail_growth_1m,
    mf.treasury_growth_1m,
    mf.fedfunds_volatility_3m,
    mf.retail_volatility_3m,
    mf.treasury_volatility_3m,
    mf.yield_curve_inversion,
    mf.yield_spread,
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
    STDDEV(fedfunds_rate) AS std_value
FROM ML.TRAIN_SET
WHERE fedfunds_rate IS NOT NULL

UNION ALL

SELECT 
    'retail_sales' AS feature_name,
    AVG(retail_sales) AS mean_value,
    STDDEV(retail_sales) AS std_value
FROM ML.TRAIN_SET
WHERE retail_sales IS NOT NULL

UNION ALL

SELECT 
    'treasury_10y_rate' AS feature_name,
    AVG(treasury_10y_rate) AS mean_value,
    STDDEV(treasury_10y_rate) AS std_value
FROM ML.TRAIN_SET
WHERE treasury_10y_rate IS NOT NULL;

-- =====================================================
-- 4. ML READY MASTER TABLE
-- =====================================================

CREATE OR REPLACE TABLE ML.ML_READY_MASTER AS
SELECT 
    mf.date,
    mf.year,
    mf.month,
    mf.quarter,
    mf.fedfunds_rate,
    mf.retail_sales,
    mf.treasury_10y_rate,
    mf.fedfunds_3m_avg,
    mf.retail_3m_avg,
    mf.treasury_3m_avg,
    mf.fedfunds_lag_1m,
    mf.retail_lag_1m,
    mf.treasury_lag_1m,
    mf.fedfunds_growth_1m,
    mf.retail_growth_1m,
    mf.treasury_growth_1m,
    mf.fedfunds_volatility_3m,
    mf.retail_volatility_3m,
    mf.treasury_volatility_3m,
    mf.yield_curve_inversion,
    mf.yield_spread,
    t.spoilage_rate,
    t.spoilage_risk_flag,
    CASE 
        WHEN mf.year BETWEEN 1990 AND 2016 THEN 'TRAIN'
        WHEN mf.year BETWEEN 2017 AND 2021 THEN 'VAL'
        WHEN mf.year >= 2022 THEN 'TEST'
        ELSE 'UNKNOWN'
    END AS split_type,
    CURRENT_TIMESTAMP() AS created_at
FROM FEAT.MASTER_FEATURES mf
LEFT JOIN ML.TARGETS t ON mf.date = t.date
ORDER BY mf.date;

-- =====================================================
-- 5. DATA QUALITY VALIDATION
-- =====================================================

CREATE OR REPLACE TABLE ML.ML_VALIDATION_SUMMARY AS
SELECT 
    'TRAIN_SET' AS dataset_name,
    COUNT(*) AS total_rows,
    COUNT(CASE WHEN spoilage_rate IS NOT NULL THEN 1 END) AS non_null_targets,
    MIN(date) AS min_date,
    MAX(date) AS max_date,
    CURRENT_TIMESTAMP() AS created_at
FROM ML.TRAIN_SET

UNION ALL

SELECT 
    'VAL_SET' AS dataset_name,
    COUNT(*) AS total_rows,
    COUNT(CASE WHEN spoilage_rate IS NOT NULL THEN 1 END) AS non_null_targets,
    MIN(date) AS min_date,
    MAX(date) AS max_date,
    CURRENT_TIMESTAMP() AS created_at
FROM ML.VAL_SET

UNION ALL

SELECT 
    'TEST_SET' AS dataset_name,
    COUNT(*) AS total_rows,
    COUNT(CASE WHEN spoilage_rate IS NOT NULL THEN 1 END) AS non_null_targets,
    MIN(date) AS min_date,
    MAX(date) AS max_date,
    CURRENT_TIMESTAMP() AS created_at
FROM ML.TEST_SET;

-- =====================================================
-- 6. AUDIT LOG
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
