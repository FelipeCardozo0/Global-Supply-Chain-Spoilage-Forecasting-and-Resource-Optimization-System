-- ============================================================================
-- PHASE 5: MODEL VALIDATION
-- Global Supply Chain Spoilage and Resource Allocation Forecasting
-- ============================================================================
-- Purpose: Comprehensive validation of trained models and predictions
-- Run after: ml_model_training.py execution
-- ============================================================================

USE DATABASE GLOBAL_SPOILAGE_DB;
USE SCHEMA ML;
USE WAREHOUSE COMPUTE_WH;

-- Clear previous validation results
TRUNCATE TABLE IF EXISTS ML.MODEL_VALIDATION_SUMMARY;

-- ============================================================================
-- PART 1: MODEL EXISTENCE & COMPLETENESS CHECK
-- ============================================================================

SELECT 'MODEL VALIDATION - EXISTENCE & COMPLETENESS' AS validation_section;

-- Check that models were trained
INSERT INTO ML.MODEL_VALIDATION_SUMMARY (validation_check, status, details, actual_value)
SELECT 
    'Models Trained' AS validation_check,
    CASE 
        WHEN COUNT(*) >= 6 THEN 'PASS'
        WHEN COUNT(*) >= 3 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Found ' || COUNT(*) || ' models (expected 6: 3 regression + 3 classification)' AS details,
    COUNT(*) AS actual_value
FROM ML.MODEL_RESULTS;

-- Show what models exist
SELECT 
    'Trained Models' AS check_name,
    model_name,
    task,
    created_at
FROM ML.MODEL_RESULTS
ORDER BY task, model_name;

-- ============================================================================
-- PART 2: REGRESSION MODEL PERFORMANCE VALIDATION
-- ============================================================================

SELECT 'REGRESSION MODEL PERFORMANCE' AS validation_section;

-- R² threshold check (should be > 0.7 for good models, > 0.5 acceptable)
INSERT INTO ML.MODEL_VALIDATION_SUMMARY (validation_check, status, details, threshold_value, actual_value)
SELECT 
    'Regression R² Score' AS validation_check,
    CASE 
        WHEN AVG(val_r2) >= 0.7 THEN 'PASS'
        WHEN AVG(val_r2) >= 0.5 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Average validation R² = ' || ROUND(AVG(val_r2), 4) || 
    ' (best: ' || ROUND(MAX(val_r2), 4) || ')' AS details,
    0.7 AS threshold_value,
    AVG(val_r2) AS actual_value
FROM ML.MODEL_RESULTS
WHERE task = 'regression';

-- RMSE check
SELECT 
    model_name,
    ROUND(val_rmse, 4) AS val_rmse,
    ROUND(val_r2, 4) AS val_r2,
    ROUND(cv_rmse, 4) AS cv_rmse,
    ROUND(cv_std, 4) AS cv_std,
    CASE 
        WHEN val_r2 >= 0.7 THEN 'EXCELLENT'
        WHEN val_r2 >= 0.5 THEN 'GOOD'
        WHEN val_r2 >= 0.3 THEN 'ACCEPTABLE'
        ELSE 'POOR'
    END AS performance_rating
FROM ML.MODEL_RESULTS
WHERE task = 'regression'
ORDER BY val_r2 DESC;

-- ============================================================================
-- PART 3: CLASSIFICATION MODEL PERFORMANCE VALIDATION
-- ============================================================================

SELECT 'CLASSIFICATION MODEL PERFORMANCE' AS validation_section;

-- F1 Score threshold check (should be > 0.75 for good models, > 0.6 acceptable)
INSERT INTO ML.MODEL_VALIDATION_SUMMARY (validation_check, status, details, threshold_value, actual_value)
SELECT 
    'Classification F1 Score' AS validation_check,
    CASE 
        WHEN AVG(val_f1) >= 0.75 THEN 'PASS'
        WHEN AVG(val_f1) >= 0.6 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Average validation F1 = ' || ROUND(AVG(val_f1), 4) || 
    ' (best: ' || ROUND(MAX(val_f1), 4) || ')' AS details,
    0.75 AS threshold_value,
    AVG(val_f1) AS actual_value
FROM ML.MODEL_RESULTS
WHERE task = 'classification';

-- AUC threshold check
INSERT INTO ML.MODEL_VALIDATION_SUMMARY (validation_check, status, details, threshold_value, actual_value)
SELECT 
    'Classification AUC Score' AS validation_check,
    CASE 
        WHEN AVG(val_auc) >= 0.85 THEN 'PASS'
        WHEN AVG(val_auc) >= 0.7 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Average validation AUC = ' || ROUND(AVG(val_auc), 4) AS details,
    0.85 AS threshold_value,
    AVG(val_auc) AS actual_value
FROM ML.MODEL_RESULTS
WHERE task = 'classification';

-- Show classification metrics
SELECT 
    model_name,
    ROUND(val_f1, 4) AS val_f1,
    ROUND(val_auc, 4) AS val_auc,
    ROUND(val_precision, 4) AS val_precision,
    ROUND(val_recall, 4) AS val_recall,
    ROUND(cv_f1, 4) AS cv_f1,
    CASE 
        WHEN val_f1 >= 0.75 AND val_auc >= 0.85 THEN 'EXCELLENT'
        WHEN val_f1 >= 0.6 AND val_auc >= 0.7 THEN 'GOOD'
        ELSE 'ACCEPTABLE'
    END AS performance_rating
FROM ML.MODEL_RESULTS
WHERE task = 'classification'
ORDER BY val_f1 DESC;

-- ============================================================================
-- PART 4: CROSS-VALIDATION STABILITY CHECK
-- ============================================================================

SELECT 'CROSS-VALIDATION STABILITY' AS validation_section;

-- Check CV standard deviation (should be low for stable models)
INSERT INTO ML.MODEL_VALIDATION_SUMMARY (validation_check, status, details, threshold_value, actual_value)
SELECT 
    'Cross-Validation Stability' AS validation_check,
    CASE 
        WHEN AVG(cv_std) < 0.05 THEN 'PASS'
        WHEN AVG(cv_std) < 0.1 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Average CV std = ' || ROUND(AVG(cv_std), 4) || ' (lower is better)' AS details,
    0.05 AS threshold_value,
    AVG(cv_std) AS actual_value
FROM ML.MODEL_RESULTS;

-- Show CV metrics
SELECT 
    model_name,
    task,
    CASE 
        WHEN task = 'regression' THEN cv_rmse
        ELSE cv_f1
    END AS cv_metric,
    ROUND(cv_std, 4) AS cv_std,
    CASE 
        WHEN cv_std < 0.05 THEN 'STABLE'
        WHEN cv_std < 0.1 THEN 'MODERATE'
        ELSE 'UNSTABLE'
    END AS stability_rating
FROM ML.MODEL_RESULTS
ORDER BY task, cv_std;

-- ============================================================================
-- PART 5: FEATURE IMPORTANCE VALIDATION
-- ============================================================================

SELECT 'FEATURE IMPORTANCE VALIDATION' AS validation_section;

-- Check that feature importances were computed
INSERT INTO ML.MODEL_VALIDATION_SUMMARY (validation_check, status, details, actual_value)
SELECT 
    'Feature Importance Computed' AS validation_check,
    CASE 
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Found ' || COUNT(*) || ' feature importance records' AS details,
    COUNT(*) AS actual_value
FROM ML.FEATURE_IMPORTANCE;

-- Check feature importance distribution (top feature should not dominate)
WITH importance_stats AS (
    SELECT 
        model_name,
        feature_name,
        importance_score,
        importance_score / SUM(importance_score) OVER (PARTITION BY model_name) AS importance_pct,
        RANK() OVER (PARTITION BY model_name ORDER BY importance_score DESC) AS feature_rank
    FROM ML.FEATURE_IMPORTANCE
)
INSERT INTO ML.MODEL_VALIDATION_SUMMARY (validation_check, status, details, threshold_value, actual_value)
SELECT 
    'Feature Importance Balance' AS validation_check,
    CASE 
        WHEN MAX(importance_pct) < 0.3 THEN 'PASS'
        WHEN MAX(importance_pct) < 0.5 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Max single feature importance = ' || ROUND(MAX(importance_pct) * 100, 2) || '% (should be < 30%)' AS details,
    0.3 AS threshold_value,
    MAX(importance_pct) AS actual_value
FROM importance_stats
WHERE feature_rank = 1;

-- Show top 10 features across models
SELECT 
    feature_name,
    COUNT(DISTINCT model_name) AS models_count,
    ROUND(AVG(importance_score), 4) AS avg_importance,
    ROUND(MAX(importance_score), 4) AS max_importance
FROM ML.FEATURE_IMPORTANCE
GROUP BY feature_name
ORDER BY avg_importance DESC
LIMIT 10;

-- ============================================================================
-- PART 6: PREDICTION COMPLETENESS CHECK
-- ============================================================================

SELECT 'PREDICTION COMPLETENESS' AS validation_section;

-- Check that predictions were generated
INSERT INTO ML.MODEL_VALIDATION_SUMMARY (validation_check, status, details, actual_value)
SELECT 
    'Predictions Generated' AS validation_check,
    CASE 
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Found ' || COUNT(*) || ' prediction records' AS details,
    COUNT(*) AS actual_value
FROM ML.PREDICTIONS;

-- Check for NULL predictions (should be none)
INSERT INTO ML.MODEL_VALIDATION_SUMMARY (validation_check, status, details, actual_value)
SELECT 
    'Non-NULL Predictions' AS validation_check,
    CASE 
        WHEN SUM(CASE WHEN randomforestregressor_pred IS NULL THEN 1 ELSE 0 END) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Found ' || SUM(CASE WHEN randomforestregressor_pred IS NULL THEN 1 ELSE 0 END) || 
    ' NULL predictions' AS details,
    SUM(CASE WHEN randomforestregressor_pred IS NULL THEN 1 ELSE 0 END) AS actual_value
FROM ML.PREDICTIONS;

-- Check prediction range (regression predictions should be 0-1)
INSERT INTO ML.MODEL_VALIDATION_SUMMARY (validation_check, status, details, actual_value)
SELECT 
    'Prediction Range Valid' AS validation_check,
    CASE 
        WHEN MIN(randomforestregressor_pred) >= 0 
         AND MAX(randomforestregressor_pred) <= 1
        THEN 'PASS'
        WHEN MIN(randomforestregressor_pred) >= -0.1 
         AND MAX(randomforestregressor_pred) <= 1.1
        THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Prediction range: [' || ROUND(MIN(randomforestregressor_pred), 4) || ', ' || 
    ROUND(MAX(randomforestregressor_pred), 4) || '] (expected [0, 1])' AS details,
    MAX(randomforestregressor_pred) AS actual_value
FROM ML.PREDICTIONS
WHERE randomforestregressor_pred IS NOT NULL;

-- ============================================================================
-- PART 7: CLASSIFICATION PROBABILITY CHECK
-- ============================================================================

SELECT 'CLASSIFICATION PROBABILITY CHECK' AS validation_section;

-- Check probability range (should be 0-1)
INSERT INTO ML.MODEL_VALIDATION_SUMMARY (validation_check, status, details)
SELECT 
    'Classification Probabilities Valid' AS validation_check,
    CASE 
        WHEN MIN(randomforestclassifier_proba) >= 0 
         AND MAX(randomforestclassifier_proba) <= 1
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Probability range: [' || ROUND(MIN(randomforestclassifier_proba), 4) || ', ' || 
    ROUND(MAX(randomforestclassifier_proba), 4) || ']' AS details
FROM ML.PREDICTIONS
WHERE randomforestclassifier_proba IS NOT NULL;

-- Check class balance in predictions
SELECT 
    'Predicted Class Distribution' AS check_name,
    SUM(randomforestclassifier_pred) AS predicted_positive,
    COUNT(*) - SUM(randomforestclassifier_pred) AS predicted_negative,
    ROUND(100.0 * SUM(randomforestclassifier_pred) / COUNT(*), 2) AS pct_positive,
    CASE 
        WHEN SUM(randomforestclassifier_pred) * 100.0 / COUNT(*) BETWEEN 10 AND 40
        THEN 'BALANCED'
        ELSE 'CHECK_DISTRIBUTION'
    END AS status
FROM ML.PREDICTIONS
WHERE randomforestclassifier_pred IS NOT NULL;

-- ============================================================================
-- PART 8: MODEL CONVERGENCE CHECK
-- ============================================================================

SELECT 'MODEL CONVERGENCE' AS validation_section;

-- Check train vs validation performance gap (overfitting check)
WITH performance_gaps AS (
    SELECT 
        model_name,
        task,
        CASE 
            WHEN task = 'regression' THEN ABS(train_r2 - val_r2)
            ELSE ABS(train_f1 - val_f1)
        END AS performance_gap
    FROM ML.MODEL_RESULTS
)
INSERT INTO ML.MODEL_VALIDATION_SUMMARY (validation_check, status, details, threshold_value, actual_value)
SELECT 
    'Overfitting Check' AS validation_check,
    CASE 
        WHEN AVG(performance_gap) < 0.1 THEN 'PASS'
        WHEN AVG(performance_gap) < 0.2 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Average train-val gap = ' || ROUND(AVG(performance_gap), 4) || 
    ' (lower is better, < 0.1 ideal)' AS details,
    0.1 AS threshold_value,
    AVG(performance_gap) AS actual_value
FROM performance_gaps;

-- Show train vs val metrics
SELECT 
    model_name,
    task,
    CASE WHEN task = 'regression' THEN train_r2 ELSE train_f1 END AS train_metric,
    CASE WHEN task = 'regression' THEN val_r2 ELSE val_f1 END AS val_metric,
    CASE 
        WHEN task = 'regression' THEN ABS(train_r2 - val_r2)
        ELSE ABS(train_f1 - val_f1)
    END AS gap,
    CASE 
        WHEN ABS(CASE WHEN task = 'regression' THEN train_r2 - val_r2 ELSE train_f1 - val_f1 END) < 0.1
        THEN 'NO_OVERFITTING'
        WHEN ABS(CASE WHEN task = 'regression' THEN train_r2 - val_r2 ELSE train_f1 - val_f1 END) < 0.2
        THEN 'MILD_OVERFITTING'
        ELSE 'SIGNIFICANT_OVERFITTING'
    END AS overfitting_status
FROM ML.MODEL_RESULTS
ORDER BY gap DESC;

-- ============================================================================
-- PART 9: SHAP VALUES VALIDATION (if available)
-- ============================================================================

SELECT 'SHAP VALUES VALIDATION' AS validation_section;

-- Check if SHAP values were computed
INSERT INTO ML.MODEL_VALIDATION_SUMMARY (validation_check, status, details, actual_value)
SELECT 
    'SHAP Values Computed' AS validation_check,
    CASE 
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'WARN'
    END AS status,
    'Found ' || COUNT(*) || ' SHAP summary records (optional)' AS details,
    COUNT(*) AS actual_value
FROM ML.SHAP_SUMMARY;

-- ============================================================================
-- PART 10: METADATA COMPLETENESS
-- ============================================================================

SELECT 'METADATA COMPLETENESS' AS validation_section;

-- Check that all models have metadata
INSERT INTO ML.MODEL_VALIDATION_SUMMARY (validation_check, status, details)
SELECT 
    'Model Metadata Complete' AS validation_check,
    CASE 
        WHEN COUNT(DISTINCT model_name) >= 6 THEN 'PASS'
        ELSE 'WARN'
    END AS status,
    'Metadata exists for ' || COUNT(DISTINCT model_name) || ' models' AS details
FROM ML.MODEL_RESULTS;

-- ============================================================================
-- PART 11: TIMESTAMP VALIDATION
-- ============================================================================

SELECT 'TIMESTAMP VALIDATION' AS validation_section;

-- Check that training occurred recently
INSERT INTO ML.MODEL_VALIDATION_SUMMARY (validation_check, status, details)
SELECT 
    'Training Recency' AS validation_check,
    CASE 
        WHEN DATEDIFF('day', MAX(created_at), CURRENT_TIMESTAMP()) <= 7 THEN 'PASS'
        WHEN DATEDIFF('day', MAX(created_at), CURRENT_TIMESTAMP()) <= 30 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Last training was ' || DATEDIFF('day', MAX(created_at), CURRENT_TIMESTAMP()) || 
    ' days ago' AS details
FROM ML.MODEL_RESULTS;

-- ============================================================================
-- PART 12: OVERALL VALIDATION STATUS
-- ============================================================================

SELECT 'OVERALL VALIDATION STATUS' AS validation_section;

-- Compute overall pass/fail
WITH validation_counts AS (
    SELECT 
        SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END) AS pass_count,
        SUM(CASE WHEN status = 'WARN' THEN 1 ELSE 0 END) AS warn_count,
        SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END) AS fail_count,
        COUNT(*) AS total_checks
    FROM ML.MODEL_VALIDATION_SUMMARY
)
INSERT INTO ML.MODEL_VALIDATION_SUMMARY (validation_check, status, details)
SELECT 
    'OVERALL_STATUS' AS validation_check,
    CASE 
        WHEN fail_count = 0 AND warn_count <= 2 THEN 'PASS'
        WHEN fail_count = 0 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Pass: ' || pass_count || ', Warn: ' || warn_count || ', Fail: ' || fail_count || 
    ' (Total: ' || total_checks || ' checks)' AS details
FROM validation_counts;

-- ============================================================================
-- FINAL SUMMARY
-- ============================================================================

SELECT 
    '============================================================' AS summary
UNION ALL
SELECT 'PHASE 5 MODEL VALIDATION COMPLETE'
UNION ALL
SELECT '============================================================'
UNION ALL
SELECT 'Total Validation Checks: ' || COUNT(*)
FROM ML.MODEL_VALIDATION_SUMMARY
UNION ALL
SELECT 'Passed: ' || SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END)
FROM ML.MODEL_VALIDATION_SUMMARY
UNION ALL
SELECT 'Warnings: ' || SUM(CASE WHEN status = 'WARN' THEN 1 ELSE 0 END)
FROM ML.MODEL_VALIDATION_SUMMARY
UNION ALL
SELECT 'Failed: ' || SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END)
FROM ML.MODEL_VALIDATION_SUMMARY
UNION ALL
SELECT '============================================================';

-- Show all validation results
SELECT 
    validation_check,
    status,
    details,
    checked_at
FROM ML.MODEL_VALIDATION_SUMMARY
ORDER BY 
    CASE status
        WHEN 'FAIL' THEN 1
        WHEN 'WARN' THEN 2
        WHEN 'PASS' THEN 3
    END,
    validation_check;

-- Final status
SELECT 
    CASE 
        WHEN status = 'PASS' THEN 'MODELS READY FOR PRODUCTION'
        WHEN status = 'WARN' THEN 'MODELS ACCEPTABLE - REVIEW WARNINGS'
        ELSE 'MODELS NOT READY - FIX FAILURES'
    END AS final_status
FROM ML.MODEL_VALIDATION_SUMMARY
WHERE validation_check = 'OVERALL_STATUS';

