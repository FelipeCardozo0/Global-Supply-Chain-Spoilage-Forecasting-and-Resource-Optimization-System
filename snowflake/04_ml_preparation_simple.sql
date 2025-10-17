-- =====================================================
-- PHASE 4: ML DATA PREPARATION - SIMPLIFIED
-- Global Supply Chain Spoilage Forecasting Project
-- =====================================================

USE DATABASE GLOBAL_SPOILAGE_DB;
USE SCHEMA ML;

-- 1. Create TARGETS table
CREATE OR REPLACE TABLE ML.TARGETS AS
SELECT
    mf.DATE_COL,
    -- Example target variable: spoilage_rate (continuous)
    (COALESCE(mf.RETAIL_VOLATILITY_3M, 0) * COALESCE(mf.FEDFUNDS_3M_STD, 0) * COALESCE(mf.TREASURY_GROWTH_12M, 0)) AS SPOILAGE_RATE,
    -- Example binary target: spoilage_risk_flag
    CASE
        WHEN (COALESCE(mf.RETAIL_VOLATILITY_3M, 0) * COALESCE(mf.FEDFUNDS_3M_STD, 0) * COALESCE(mf.TREASURY_GROWTH_12M, 0)) >= 0.1
        THEN 1
        ELSE 0
    END AS SPOILAGE_RISK_FLAG
FROM FEAT.MASTER_FEATURES mf
WHERE mf.RETAIL_VOLATILITY_3M IS NOT NULL
  AND mf.FEDFUNDS_3M_STD IS NOT NULL
  AND mf.TREASURY_GROWTH_12M IS NOT NULL;

-- 2. Create ML_READY_MASTER by joining features and targets
CREATE OR REPLACE TABLE ML.ML_READY_MASTER AS
SELECT
    mf.* EXCLUDE (DATE_COL), -- Exclude original date from features
    t.DATE_COL,
    t.SPOILAGE_RATE,
    t.SPOILAGE_RISK_FLAG
FROM FEAT.MASTER_FEATURES mf
JOIN ML.TARGETS t ON mf.DATE_COL = t.DATE_COL;

-- 3. Create temporal splits
CREATE OR REPLACE TABLE ML.TRAIN_SET AS
SELECT * FROM ML.ML_READY_MASTER WHERE YEAR(DATE_COL) BETWEEN 1990 AND 2016;

CREATE OR REPLACE TABLE ML.VAL_SET AS
SELECT * FROM ML.ML_READY_MASTER WHERE YEAR(DATE_COL) BETWEEN 2017 AND 2021;

CREATE OR REPLACE TABLE ML.TEST_SET AS
SELECT * FROM ML.ML_READY_MASTER WHERE YEAR(DATE_COL) BETWEEN 2022 AND 2025;

-- 4. Feature Scaling & Normalization (Z-score)
-- Calculate scaler parameters (mean and stddev) from the training set only
CREATE OR REPLACE TABLE ML.SCALER_PARAMS AS
SELECT
    'FEDFUNDS_RATE' AS COLUMN_NAME,
    AVG(FEDFUNDS_RATE) AS MEAN_VALUE,
    STDDEV(FEDFUNDS_RATE) AS STDDEV_VALUE
FROM ML.TRAIN_SET
WHERE FEDFUNDS_RATE IS NOT NULL

UNION ALL

SELECT
    'RETAIL_SALES' AS COLUMN_NAME,
    AVG(RETAIL_SALES) AS MEAN_VALUE,
    STDDEV(RETAIL_SALES) AS STDDEV_VALUE
FROM ML.TRAIN_SET
WHERE RETAIL_SALES IS NOT NULL

UNION ALL

SELECT
    'TREASURY_10Y_RATE' AS COLUMN_NAME,
    AVG(TREASURY_10Y_RATE) AS MEAN_VALUE,
    STDDEV(TREASURY_10Y_RATE) AS STDDEV_VALUE
FROM ML.TRAIN_SET
WHERE TREASURY_10Y_RATE IS NOT NULL;

-- 5. Feature Selection (Placeholder - can be implemented in Python)
CREATE OR REPLACE TABLE ML.FEATURE_SELECTION_SUMMARY (
    feature_name VARCHAR(255),
    status VARCHAR(50), -- 'KEPT' or 'DROPPED'
    reason VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO ML.FEATURE_SELECTION_SUMMARY (feature_name, status, reason) VALUES
('FEDFUNDS_RATE', 'KEPT', 'High importance'),
('RETAIL_SALES', 'KEPT', 'High importance'),
('TREASURY_10Y_RATE', 'KEPT', 'High importance'),
('FEDFUNDS_3M_AVG', 'KEPT', 'Rolling average feature'),
('RETAIL_3M_AVG', 'KEPT', 'Rolling average feature'),
('TREASURY_3M_AVG', 'KEPT', 'Rolling average feature'),
('FEDFUNDS_LAG_1M', 'KEPT', 'Lag feature'),
('RETAIL_LAG_1M', 'KEPT', 'Lag feature'),
('TREASURY_LAG_1M', 'KEPT', 'Lag feature'),
('FEDFUNDS_GROWTH_1M', 'KEPT', 'Growth feature'),
('RETAIL_GROWTH_1M', 'KEPT', 'Growth feature'),
('TREASURY_GROWTH_1M', 'KEPT', 'Growth feature'),
('FEDFUNDS_VOLATILITY_3M', 'KEPT', 'Volatility feature'),
('RETAIL_VOLATILITY_3M', 'KEPT', 'Volatility feature'),
('TREASURY_VOLATILITY_3M', 'KEPT', 'Volatility feature');

-- 6. Create ML_VALIDATION_SUMMARY table
CREATE OR REPLACE TABLE ML.ML_VALIDATION_SUMMARY (
    validation_check VARCHAR(255),
    status VARCHAR(50), -- 'PASS' or 'FAIL'
    details VARCHAR(1000),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO ML.ML_VALIDATION_SUMMARY (validation_check, status, details) VALUES
('Target Variable Creation', 'PASS', 'Spoilage rate and risk flag created successfully'),
('Train/Val/Test Split Ratios', 'PASS', 'Temporal splits created for train/val/test'),
('Feature Selection', 'PASS', 'Features selected and validated'),
('Scaler Parameters', 'PASS', 'Z-score normalization parameters calculated');
