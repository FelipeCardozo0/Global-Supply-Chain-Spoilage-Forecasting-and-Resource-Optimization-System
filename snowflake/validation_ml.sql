-- ============================================================================
-- PHASE 4: ML DATA VALIDATION
-- Global Supply Chain Spoilage and Resource Allocation Forecasting
-- ============================================================================
-- Purpose: Comprehensive validation of ML layer tables
-- Run after: 04_ml_preparation.sql
-- ============================================================================

USE DATABASE GLOBAL_SPOILAGE_DB;
USE SCHEMA ML;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================================
-- PART 1: TABLE EXISTENCE & ROW COUNTS
-- ============================================================================

SELECT 'ML TABLE VALIDATION - EXISTENCE & COUNTS' AS validation_section;

SELECT 
    TABLE_NAME,
    ROW_COUNT,
    CASE 
        WHEN ROW_COUNT = 0 THEN 'EMPTY TABLE'
        WHEN ROW_COUNT < 50 THEN 'VERY SMALL DATASET'
        WHEN ROW_COUNT < 200 THEN 'SMALL DATASET'
        ELSE 'OK'
    END AS status,
    BYTES / 1024 / 1024 AS size_mb
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'ML'
  AND TABLE_TYPE = 'BASE TABLE'
ORDER BY ROW_COUNT DESC;

-- ============================================================================
-- PART 2: TARGET VARIABLE VALIDATION
-- ============================================================================

SELECT 'TARGET VARIABLE VALIDATION' AS validation_section;

-- Target distribution
SELECT 
    'Target Distribution' AS check_name,
    COUNT(*) AS total_rows,
    MIN(spoilage_rate) AS min_rate,
    MAX(spoilage_rate) AS max_rate,
    AVG(spoilage_rate) AS mean_rate,
    MEDIAN(spoilage_rate) AS median_rate,
    STDDEV(spoilage_rate) AS std_rate,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY spoilage_rate) AS q25,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY spoilage_rate) AS q75,
    CASE 
        WHEN MIN(spoilage_rate) >= 0 AND MAX(spoilage_rate) <= 1
        THEN 'OK - VALID RANGE'
        ELSE 'CRITICAL - OUT OF RANGE'
    END AS status
FROM ML.TARGETS;

-- Binary target balance
SELECT 
    'Binary Target Balance' AS check_name,
    SUM(spoilage_risk_flag) AS positive_class,
    COUNT(*) - SUM(spoilage_risk_flag) AS negative_class,
    COUNT(*) AS total,
    ROUND(100.0 * SUM(spoilage_risk_flag) / COUNT(*), 2) AS pct_positive,
    CASE 
        WHEN SUM(spoilage_risk_flag) * 100.0 / COUNT(*) BETWEEN 15 AND 35
        THEN 'OK - BALANCED'
        WHEN SUM(spoilage_risk_flag) * 100.0 / COUNT(*) < 5
        THEN 'CRITICAL - SEVERE IMBALANCE'
        ELSE 'WARN - IMBALANCED'
    END AS status
FROM ML.TARGETS;

-- Target by year (check for temporal stability)
SELECT 
    YEAR(date) AS year,
    COUNT(*) AS rows,
    ROUND(AVG(spoilage_rate), 4) AS avg_spoilage_rate,
    ROUND(STDDEV(spoilage_rate), 4) AS std_spoilage_rate,
    SUM(spoilage_risk_flag) AS high_risk_months,
    ROUND(100.0 * SUM(spoilage_risk_flag) / COUNT(*), 2) AS pct_high_risk
FROM ML.TARGETS
GROUP BY YEAR(date)
ORDER BY year;

-- ============================================================================
-- PART 3: DATA SPLIT VALIDATION
-- ============================================================================

SELECT 'DATA SPLIT VALIDATION' AS validation_section;

-- Split ratios
WITH split_stats AS (
    SELECT 
        (SELECT COUNT(*) FROM ML.TRAIN_SET) AS train_count,
        (SELECT COUNT(*) FROM ML.VAL_SET) AS val_count,
        (SELECT COUNT(*) FROM ML.TEST_SET) AS test_count
)
SELECT 
    'Split Ratios' AS check_name,
    train_count,
    val_count,
    test_count,
    train_count + val_count + test_count AS total_count,
    ROUND(100.0 * train_count / (train_count + val_count + test_count), 2) AS pct_train,
    ROUND(100.0 * val_count / (train_count + val_count + test_count), 2) AS pct_val,
    ROUND(100.0 * test_count / (train_count + val_count + test_count), 2) AS pct_test,
    CASE 
        WHEN 100.0 * train_count / (train_count + val_count + test_count) BETWEEN 65 AND 80
         AND 100.0 * val_count / (train_count + val_count + test_count) BETWEEN 10 AND 20
         AND 100.0 * test_count / (train_count + val_count + test_count) BETWEEN 10 AND 20
        THEN 'OK - GOOD SPLIT RATIOS'
        ELSE 'WARN - UNUSUAL SPLIT RATIOS'
    END AS status
FROM split_stats;

-- Date ranges per split
SELECT 
    'TRAIN_SET' AS dataset,
    MIN(date) AS start_date,
    MAX(date) AS end_date,
    COUNT(*) AS rows,
    DATEDIFF('month', MIN(date), MAX(date)) + 1 AS months_span
FROM ML.TRAIN_SET
UNION ALL
SELECT 'VAL_SET', MIN(date), MAX(date), COUNT(*),
       DATEDIFF('month', MIN(date), MAX(date)) + 1
FROM ML.VAL_SET
UNION ALL
SELECT 'TEST_SET', MIN(date), MAX(date), COUNT(*),
       DATEDIFF('month', MIN(date), MAX(date)) + 1
FROM ML.TEST_SET;

-- Check for temporal overlap (should be none)
SELECT 
    'Temporal Overlap Check' AS check_name,
    CASE 
        WHEN (SELECT MAX(date) FROM ML.TRAIN_SET) < (SELECT MIN(date) FROM ML.VAL_SET)
         AND (SELECT MAX(date) FROM ML.VAL_SET) < (SELECT MIN(date) FROM ML.TEST_SET)
        THEN 'OK - NO OVERLAP'
        ELSE 'CRITICAL - TEMPORAL OVERLAP DETECTED'
    END AS status;

-- ============================================================================
-- PART 4: TARGET CONSISTENCY ACROSS SPLITS
-- ============================================================================

SELECT 'TARGET CONSISTENCY ACROSS SPLITS' AS validation_section;

-- Target statistics by split
SELECT 
    'TRAIN' AS dataset,
    COUNT(*) AS rows,
    ROUND(AVG(spoilage_rate), 4) AS avg_target,
    ROUND(STDDEV(spoilage_rate), 4) AS std_target,
    ROUND(MIN(spoilage_rate), 4) AS min_target,
    ROUND(MAX(spoilage_rate), 4) AS max_target,
    SUM(spoilage_risk_flag) AS positive_class,
    ROUND(100.0 * SUM(spoilage_risk_flag) / COUNT(*), 2) AS pct_positive
FROM ML.TRAIN_SET
UNION ALL
SELECT 'VAL', COUNT(*), 
       ROUND(AVG(spoilage_rate), 4),
       ROUND(STDDEV(spoilage_rate), 4),
       ROUND(MIN(spoilage_rate), 4),
       ROUND(MAX(spoilage_rate), 4),
       SUM(spoilage_risk_flag),
       ROUND(100.0 * SUM(spoilage_risk_flag) / COUNT(*), 2)
FROM ML.VAL_SET
UNION ALL
SELECT 'TEST', COUNT(*), 
       ROUND(AVG(spoilage_rate), 4),
       ROUND(STDDEV(spoilage_rate), 4),
       ROUND(MIN(spoilage_rate), 4),
       ROUND(MAX(spoilage_rate), 4),
       SUM(spoilage_risk_flag),
       ROUND(100.0 * SUM(spoilage_risk_flag) / COUNT(*), 2)
FROM ML.TEST_SET;

-- ============================================================================
-- PART 5: FEATURE NULL ANALYSIS
-- ============================================================================

SELECT 'FEATURE NULL ANALYSIS' AS validation_section;

-- Critical features NULL check per split
WITH train_nulls AS (
    SELECT 
        'TRAIN' AS dataset,
        COUNT(*) AS total_rows,
        SUM(CASE WHEN fedfunds_rate IS NULL THEN 1 ELSE 0 END) AS null_fedfunds,
        SUM(CASE WHEN retail_sales IS NULL THEN 1 ELSE 0 END) AS null_retail,
        SUM(CASE WHEN unemployment_rate IS NULL THEN 1 ELSE 0 END) AS null_unemployment,
        SUM(CASE WHEN spoilage_rate IS NULL THEN 1 ELSE 0 END) AS null_target
    FROM ML.TRAIN_SET
),
val_nulls AS (
    SELECT 
        'VAL' AS dataset,
        COUNT(*),
        SUM(CASE WHEN fedfunds_rate IS NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN retail_sales IS NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN unemployment_rate IS NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN spoilage_rate IS NULL THEN 1 ELSE 0 END)
    FROM ML.VAL_SET
),
test_nulls AS (
    SELECT 
        'TEST' AS dataset,
        COUNT(*),
        SUM(CASE WHEN fedfunds_rate IS NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN retail_sales IS NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN unemployment_rate IS NULL THEN 1 ELSE 0 END),
        SUM(CASE WHEN spoilage_rate IS NULL THEN 1 ELSE 0 END)
    FROM ML.TEST_SET
)
SELECT 
    dataset,
    total_rows,
    ROUND(100.0 * null_fedfunds / total_rows, 2) AS pct_null_fedfunds,
    ROUND(100.0 * null_retail / total_rows, 2) AS pct_null_retail,
    ROUND(100.0 * null_unemployment / total_rows, 2) AS pct_null_unemployment,
    ROUND(100.0 * null_target / total_rows, 2) AS pct_null_target,
    CASE 
        WHEN null_target = 0 THEN 'OK - NO NULL TARGETS'
        ELSE 'CRITICAL - NULL TARGETS DETECTED'
    END AS status
FROM train_nulls
UNION ALL
SELECT dataset, total_rows,
       ROUND(100.0 * null_fedfunds / total_rows, 2),
       ROUND(100.0 * null_retail / total_rows, 2),
       ROUND(100.0 * null_unemployment / total_rows, 2),
       ROUND(100.0 * null_target / total_rows, 2),
       CASE WHEN null_target = 0 THEN 'OK - NO NULL TARGETS' ELSE 'CRITICAL - NULL TARGETS DETECTED' END
FROM val_nulls
UNION ALL
SELECT dataset, total_rows,
       ROUND(100.0 * null_fedfunds / total_rows, 2),
       ROUND(100.0 * null_retail / total_rows, 2),
       ROUND(100.0 * null_unemployment / total_rows, 2),
       ROUND(100.0 * null_target / total_rows, 2),
       CASE WHEN null_target = 0 THEN 'OK - NO NULL TARGETS' ELSE 'CRITICAL - NULL TARGETS DETECTED' END
FROM test_nulls;

-- ============================================================================
-- PART 6: SCALER PARAMS VALIDATION
-- ============================================================================

SELECT 'SCALER PARAMS VALIDATION' AS validation_section;

-- Check scaler parameters exist and are reasonable
SELECT 
    'Scaler Parameters' AS check_name,
    COUNT(*) AS features_with_scalers,
    SUM(CASE WHEN mean_val IS NULL THEN 1 ELSE 0 END) AS null_means,
    SUM(CASE WHEN std_val IS NULL OR std_val = 0 THEN 1 ELSE 0 END) AS null_or_zero_stds,
    CASE 
        WHEN COUNT(*) >= 10 
         AND SUM(CASE WHEN mean_val IS NULL THEN 1 ELSE 0 END) = 0
         AND SUM(CASE WHEN std_val IS NULL OR std_val = 0 THEN 1 ELSE 0 END) = 0
        THEN 'OK - VALID SCALERS'
        ELSE 'WARN - CHECK SCALER PARAMS'
    END AS status
FROM ML.SCALER_PARAMS;

-- Show sample scaler parameters
SELECT 
    feature_name,
    ROUND(mean_val, 4) AS mean,
    ROUND(std_val, 4) AS std,
    ROUND(min_val, 4) AS min,
    ROUND(max_val, 4) AS max
FROM ML.SCALER_PARAMS
ORDER BY feature_name
LIMIT 10;

-- ============================================================================
-- PART 7: SCALING VERIFICATION (if scaled table exists)
-- ============================================================================

SELECT 'SCALING VERIFICATION' AS validation_section;

-- Check if scaled features have mean≈0 and std≈1
SELECT 
    'Scaled Features Check' AS check_name,
    ROUND(AVG(fedfunds_rate_scaled), 4) AS fedfunds_mean,
    ROUND(STDDEV(fedfunds_rate_scaled), 4) AS fedfunds_std,
    ROUND(AVG(retail_sales_scaled), 4) AS retail_mean,
    ROUND(STDDEV(retail_sales_scaled), 4) AS retail_std,
    CASE 
        WHEN ABS(AVG(fedfunds_rate_scaled)) < 0.1
         AND ABS(STDDEV(fedfunds_rate_scaled) - 1.0) < 0.2
         AND ABS(AVG(retail_sales_scaled)) < 0.1
         AND ABS(STDDEV(retail_sales_scaled) - 1.0) < 0.2
        THEN 'OK - PROPER SCALING'
        ELSE 'WARN - CHECK SCALING'
    END AS status
FROM ML.TRAIN_SET_SCALED;

-- ============================================================================
-- PART 8: FEATURE VARIANCE VALIDATION
-- ============================================================================

SELECT 'FEATURE VARIANCE VALIDATION' AS validation_section;

-- Check that no features have zero variance
SELECT 
    'Zero Variance Features' AS check_name,
    COUNT(*) AS total_features,
    SUM(CASE WHEN variance_val < 0.000001 THEN 1 ELSE 0 END) AS zero_variance_count,
    SUM(CASE WHEN recommendation LIKE 'KEEP%' THEN 1 ELSE 0 END) AS features_kept,
    SUM(CASE WHEN recommendation LIKE 'DROP%' THEN 1 ELSE 0 END) AS features_dropped,
    CASE 
        WHEN SUM(CASE WHEN recommendation LIKE 'KEEP%' THEN 1 ELSE 0 END) >= 5
        THEN 'OK - SUFFICIENT FEATURES'
        ELSE 'WARN - FEW FEATURES'
    END AS status
FROM ML.FEATURE_VARIANCE;

-- ============================================================================
-- PART 9: FEATURE SELECTION SUMMARY
-- ============================================================================

SELECT 'FEATURE SELECTION VALIDATION' AS validation_section;

SELECT 
    status,
    COUNT(*) AS feature_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM ML.FEATURE_SELECTION_SUMMARY
GROUP BY status;

-- ============================================================================
-- PART 10: ML_READY_MASTER VALIDATION
-- ============================================================================

SELECT 'ML_READY_MASTER VALIDATION' AS validation_section;

-- Structure check
SELECT 
    'ML_READY_MASTER Structure' AS check_name,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT dataset_split) AS unique_splits,
    COUNT(*) - COUNT(spoilage_rate) AS null_targets,
    CASE 
        WHEN COUNT(DISTINCT dataset_split) = 3
         AND COUNT(*) - COUNT(spoilage_rate) = 0
         AND COUNT(*) > 300
        THEN 'OK - VALID STRUCTURE'
        ELSE 'WARN - CHECK STRUCTURE'
    END AS status
FROM ML.ML_READY_MASTER;

-- Split distribution in master
SELECT 
    dataset_split,
    COUNT(*) AS rows,
    MIN(date) AS start_date,
    MAX(date) AS end_date,
    ROUND(AVG(spoilage_rate), 4) AS avg_target,
    SUM(spoilage_risk_flag) AS positive_class
FROM ML.ML_READY_MASTER
GROUP BY dataset_split
ORDER BY 
    CASE dataset_split
        WHEN 'TRAIN' THEN 1
        WHEN 'VAL' THEN 2
        WHEN 'TEST' THEN 3
    END;

-- ============================================================================
-- PART 11: COLUMN COUNT CONSISTENCY
-- ============================================================================

SELECT 'COLUMN COUNT CONSISTENCY' AS validation_section;

-- Check all splits have same columns
WITH col_counts AS (
    SELECT 
        'TRAIN_SET' AS table_name,
        COUNT(*) AS column_count
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'ML' AND TABLE_NAME = 'TRAIN_SET'
    
    UNION ALL
    
    SELECT 'VAL_SET', COUNT(*)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'ML' AND TABLE_NAME = 'VAL_SET'
    
    UNION ALL
    
    SELECT 'TEST_SET', COUNT(*)
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'ML' AND TABLE_NAME = 'TEST_SET'
)
SELECT 
    'Column Count Consistency' AS check_name,
    MIN(column_count) AS min_cols,
    MAX(column_count) AS max_cols,
    AVG(column_count) AS avg_cols,
    CASE 
        WHEN MIN(column_count) = MAX(column_count)
        THEN 'OK - CONSISTENT COLUMNS'
        ELSE 'CRITICAL - COLUMN MISMATCH'
    END AS status
FROM col_counts;

-- ============================================================================
-- PART 12: DATA LEAKAGE CHECK
-- ============================================================================

SELECT 'DATA LEAKAGE CHECK' AS validation_section;

-- Verify scaler params computed only on training data
-- by checking if validation/test means differ from training means
WITH train_stats AS (
    SELECT 
        AVG(fedfunds_rate) AS train_mean_ff,
        STDDEV(fedfunds_rate) AS train_std_ff
    FROM ML.TRAIN_SET
    WHERE fedfunds_rate IS NOT NULL
),
val_stats AS (
    SELECT 
        AVG(fedfunds_rate) AS val_mean_ff,
        STDDEV(fedfunds_rate) AS val_std_ff
    FROM ML.VAL_SET
    WHERE fedfunds_rate IS NOT NULL
),
scaler_stats AS (
    SELECT mean_val AS scaler_mean_ff, std_val AS scaler_std_ff
    FROM ML.SCALER_PARAMS
    WHERE feature_name = 'fedfunds_rate'
)
SELECT 
    'Data Leakage Check' AS check_name,
    t.train_mean_ff,
    v.val_mean_ff,
    s.scaler_mean_ff,
    ROUND(ABS(t.train_mean_ff - s.scaler_mean_ff), 6) AS mean_diff,
    CASE 
        WHEN ABS(t.train_mean_ff - s.scaler_mean_ff) < 0.001
         AND ABS(t.train_mean_ff - v.val_mean_ff) > 0.01
        THEN 'OK - NO LEAKAGE DETECTED'
        WHEN ABS(t.train_mean_ff - s.scaler_mean_ff) > 0.001
        THEN 'WARN - POSSIBLE LEAKAGE'
        ELSE 'CHECK - UNUSUAL PATTERN'
    END AS status
FROM train_stats t, val_stats v, scaler_stats s;

-- ============================================================================
-- PART 13: TARGET-FEATURE CORRELATION CHECK
-- ============================================================================

SELECT 'TARGET-FEATURE CORRELATION' AS validation_section;

-- Check for reasonable correlations between target and key features
SELECT 
    'Target Correlations' AS check_name,
    ROUND(CORR(spoilage_rate, unemployment_rate), 4) AS corr_unemployment,
    ROUND(CORR(spoilage_rate, is_recession), 4) AS corr_recession,
    ROUND(CORR(spoilage_rate, retail_yoy_growth), 4) AS corr_retail_growth,
    ROUND(CORR(spoilage_rate, economic_uncertainty_index), 4) AS corr_uncertainty,
    CASE 
        WHEN ABS(CORR(spoilage_rate, unemployment_rate)) > 0.1
          OR ABS(CORR(spoilage_rate, is_recession)) > 0.1
        THEN 'OK - FEATURES CORRELATED WITH TARGET'
        ELSE 'WARN - WEAK TARGET CORRELATIONS'
    END AS status
FROM ML.TRAIN_SET
WHERE spoilage_rate IS NOT NULL
  AND unemployment_rate IS NOT NULL;

-- ============================================================================
-- PART 14: COMPLETENESS SCORE
-- ============================================================================

SELECT 'DATA COMPLETENESS SCORE' AS validation_section;

WITH completeness AS (
    SELECT 
        dataset_split,
        (CASE WHEN fedfunds_rate IS NOT NULL THEN 1 ELSE 0 END +
         CASE WHEN retail_sales IS NOT NULL THEN 1 ELSE 0 END +
         CASE WHEN unemployment_rate IS NOT NULL THEN 1 ELSE 0 END +
         CASE WHEN sp500_eom_close IS NOT NULL THEN 1 ELSE 0 END +
         CASE WHEN retail_yoy_growth IS NOT NULL THEN 1 ELSE 0 END +
         CASE WHEN economic_uncertainty_index IS NOT NULL THEN 1 ELSE 0 END +
         CASE WHEN spoilage_rate IS NOT NULL THEN 1 ELSE 0 END +
         CASE WHEN spoilage_risk_flag IS NOT NULL THEN 1 ELSE 0 END) AS completeness_score
    FROM ML.ML_READY_MASTER
)
SELECT 
    dataset_split,
    COUNT(*) AS total_rows,
    ROUND(AVG(completeness_score), 2) AS avg_completeness,
    MIN(completeness_score) AS min_score,
    MAX(completeness_score) AS max_score,
    SUM(CASE WHEN completeness_score >= 7 THEN 1 ELSE 0 END) AS highly_complete_rows,
    ROUND(100.0 * SUM(CASE WHEN completeness_score >= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_complete,
    CASE 
        WHEN AVG(completeness_score) >= 7.0 THEN 'OK - HIGH COMPLETENESS'
        WHEN AVG(completeness_score) >= 5.0 THEN 'WARN - MODERATE COMPLETENESS'
        ELSE 'CRITICAL - LOW COMPLETENESS'
    END AS status
FROM completeness
GROUP BY dataset_split
ORDER BY 
    CASE dataset_split
        WHEN 'TRAIN' THEN 1
        WHEN 'VAL' THEN 2
        WHEN 'TEST' THEN 3
    END;

-- ============================================================================
-- PART 15: FINAL VALIDATION SUMMARY
-- ============================================================================

SELECT 'VALIDATION SUMMARY' AS validation_section;

SELECT 
    '============================================================' AS summary
UNION ALL
SELECT 'PHASE 4 ML DATA VALIDATION COMPLETE'
UNION ALL
SELECT '============================================================'
UNION ALL
SELECT 'Tables: ' || COUNT(DISTINCT TABLE_NAME)
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'ML' AND TABLE_TYPE = 'BASE TABLE'
UNION ALL
SELECT 'Train Rows: ' || COUNT(*)
FROM ML.TRAIN_SET
UNION ALL
SELECT 'Val Rows: ' || COUNT(*)
FROM ML.VAL_SET
UNION ALL
SELECT 'Test Rows: ' || COUNT(*)
FROM ML.TEST_SET
UNION ALL
SELECT 'Features Selected: ' || COUNT(*)
FROM ML.FEATURE_SELECTION_SUMMARY
WHERE status = 'SELECTED'
UNION ALL
SELECT '============================================================'
UNION ALL
SELECT 'Review validation checks above for warnings or critical issues';

-- Show audit log
SELECT * FROM ML.LOAD_AUDIT
ORDER BY load_timestamp DESC;

