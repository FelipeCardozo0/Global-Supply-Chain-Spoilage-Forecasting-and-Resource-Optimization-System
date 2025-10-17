-- ============================================================================
-- PHASE 5: MODEL TRAINING SCHEMA & RESULTS STORAGE
-- Global Supply Chain Spoilage and Resource Allocation Forecasting
-- ============================================================================
-- Purpose: Create tables for storing ML model results, predictions, and metadata
-- Prerequisites: Phase 4 complete (ML preparation tables exist)
-- Note: Model training is done via Snowpark Python (ml_model_training.py)
-- ============================================================================

USE DATABASE GLOBAL_SPOILAGE_DB;
USE SCHEMA ML;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================================
-- PART 1: MODEL RESULTS TABLE
-- ============================================================================

CREATE OR REPLACE TABLE ML.MODEL_RESULTS (
    model_id NUMBER AUTOINCREMENT,
    model_name STRING NOT NULL,
    task STRING NOT NULL,  -- 'regression' or 'classification'
    
    -- Regression metrics
    train_rmse FLOAT,
    val_rmse FLOAT,
    train_mae FLOAT,
    val_mae FLOAT,
    train_r2 FLOAT,
    val_r2 FLOAT,
    cv_rmse FLOAT,
    
    -- Classification metrics
    train_accuracy FLOAT,
    val_accuracy FLOAT,
    train_f1 FLOAT,
    val_f1 FLOAT,
    train_precision FLOAT,
    val_precision FLOAT,
    train_recall FLOAT,
    val_recall FLOAT,
    train_auc FLOAT,
    val_auc FLOAT,
    cv_f1 FLOAT,
    
    -- Cross-validation statistics
    cv_std FLOAT,
    
    -- Metadata
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    CONSTRAINT pk_model_results PRIMARY KEY (model_id)
);

CREATE INDEX idx_model_results_name ON ML.MODEL_RESULTS(model_name);
CREATE INDEX idx_model_results_task ON ML.MODEL_RESULTS(task);

SELECT 'MODEL_RESULTS table created' AS status;

-- ============================================================================
-- PART 2: MODEL METADATA TABLE
-- ============================================================================

CREATE OR REPLACE TABLE ML.MODEL_METADATA (
    metadata_id NUMBER AUTOINCREMENT,
    model_name STRING NOT NULL,
    model_type STRING,  -- 'DecisionTree', 'RandomForest', 'XGBoost'
    task STRING,
    
    -- Hyperparameters (stored as JSON or individual columns)
    n_estimators NUMBER,
    max_depth NUMBER,
    learning_rate FLOAT,
    min_samples_split NUMBER,
    min_samples_leaf NUMBER,
    
    -- Training info
    n_features NUMBER,
    n_train_samples NUMBER,
    n_val_samples NUMBER,
    training_duration_seconds FLOAT,
    
    -- Model storage (for Snowflake ML models)
    model_file_path STRING,
    model_version STRING,
    
    -- Metadata
    trained_by STRING DEFAULT CURRENT_USER(),
    trained_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    CONSTRAINT pk_model_metadata PRIMARY KEY (metadata_id)
);

SELECT 'MODEL_METADATA table created' AS status;

-- ============================================================================
-- PART 3: FEATURE IMPORTANCE TABLE
-- ============================================================================

CREATE OR REPLACE TABLE ML.FEATURE_IMPORTANCE (
    importance_id NUMBER AUTOINCREMENT,
    model_name STRING NOT NULL,
    feature_name STRING NOT NULL,
    importance_score FLOAT NOT NULL,
    importance_rank NUMBER,
    importance_type STRING,  -- 'gini', 'gain', 'shap'
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    CONSTRAINT pk_feature_importance PRIMARY KEY (importance_id)
);

CREATE INDEX idx_feature_importance_model ON ML.FEATURE_IMPORTANCE(model_name);
CREATE INDEX idx_feature_importance_feature ON ML.FEATURE_IMPORTANCE(feature_name);

SELECT 'FEATURE_IMPORTANCE table created' AS status;

-- ============================================================================
-- PART 4: SHAP VALUES SUMMARY TABLE
-- ============================================================================

CREATE OR REPLACE TABLE ML.SHAP_SUMMARY (
    shap_id NUMBER AUTOINCREMENT,
    model_name STRING NOT NULL,
    feature_name STRING NOT NULL,
    mean_abs_shap FLOAT NOT NULL,
    shap_rank NUMBER,
    base_value FLOAT,
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    CONSTRAINT pk_shap_summary PRIMARY KEY (shap_id)
);

CREATE INDEX idx_shap_model ON ML.SHAP_SUMMARY(model_name);

SELECT 'SHAP_SUMMARY table created' AS status;

-- ============================================================================
-- PART 5: PREDICTIONS TABLE (UNIFIED)
-- ============================================================================

CREATE OR REPLACE TABLE ML.PREDICTIONS (
    prediction_id NUMBER AUTOINCREMENT,
    date DATE NOT NULL,
    
    -- Regression predictions (continuous spoilage_rate)
    decisiontreeregressor_pred FLOAT,
    randomforestregressor_pred FLOAT,
    xgbregressor_pred FLOAT,
    
    -- Classification predictions (binary risk_flag)
    decisiontreeclassifier_pred NUMBER,
    decisiontreeclassifier_proba FLOAT,
    randomforestclassifier_pred NUMBER,
    randomforestclassifier_proba FLOAT,
    xgbclassifier_pred NUMBER,
    xgbclassifier_proba FLOAT,
    
    -- Ensemble/averaged predictions
    avg_regression_pred FLOAT,
    avg_classification_proba FLOAT,
    ensemble_risk_flag NUMBER,
    
    -- Metadata
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    prediction_run_id STRING,
    
    CONSTRAINT pk_predictions PRIMARY KEY (prediction_id)
);

CREATE INDEX idx_predictions_date ON ML.PREDICTIONS(date);

SELECT 'PREDICTIONS table created' AS status;

-- ============================================================================
-- PART 6: PREDICTIONS REGRESSION (DETAILED)
-- ============================================================================

CREATE OR REPLACE TABLE ML.PREDICTIONS_REGRESSION (
    prediction_id NUMBER AUTOINCREMENT,
    date DATE NOT NULL,
    model_name STRING NOT NULL,
    predicted_spoilage_rate FLOAT NOT NULL,
    actual_spoilage_rate FLOAT,
    prediction_error FLOAT,
    
    -- Confidence intervals (if available)
    lower_bound FLOAT,
    upper_bound FLOAT,
    
    -- Metadata
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    prediction_run_id STRING,
    
    CONSTRAINT pk_predictions_regression PRIMARY KEY (prediction_id)
);

CREATE INDEX idx_pred_reg_date ON ML.PREDICTIONS_REGRESSION(date);
CREATE INDEX idx_pred_reg_model ON ML.PREDICTIONS_REGRESSION(model_name);

SELECT 'PREDICTIONS_REGRESSION table created' AS status;

-- ============================================================================
-- PART 7: PREDICTIONS CLASSIFICATION (DETAILED)
-- ============================================================================

CREATE OR REPLACE TABLE ML.PREDICTIONS_CLASSIFICATION (
    prediction_id NUMBER AUTOINCREMENT,
    date DATE NOT NULL,
    model_name STRING NOT NULL,
    predicted_risk_flag NUMBER NOT NULL,
    prediction_probability FLOAT NOT NULL,
    actual_risk_flag NUMBER,
    
    -- Prediction metadata
    prediction_correct BOOLEAN,
    confidence_level STRING,  -- 'high', 'medium', 'low'
    
    -- Metadata
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    prediction_run_id STRING,
    
    CONSTRAINT pk_predictions_classification PRIMARY KEY (prediction_id)
);

CREATE INDEX idx_pred_cls_date ON ML.PREDICTIONS_CLASSIFICATION(date);
CREATE INDEX idx_pred_cls_model ON ML.PREDICTIONS_CLASSIFICATION(model_name);

SELECT 'PREDICTIONS_CLASSIFICATION table created' AS status;

-- ============================================================================
-- PART 8: PREDICTION SUMMARY (UNIFIED VIEW)
-- ============================================================================

CREATE OR REPLACE TABLE ML.PREDICTION_SUMMARY AS
SELECT 
    date,
    
    -- Best regression prediction (use ensemble average or best model)
    NULL AS predicted_spoilage_rate,
    
    -- Best classification prediction
    NULL AS predicted_risk_flag,
    NULL AS prediction_probability,
    
    -- Actual values (if available)
    NULL AS actual_spoilage_rate,
    NULL AS actual_risk_flag,
    
    -- Metadata
    NULL AS model_used,
    CURRENT_TIMESTAMP() AS created_at,
    NULL AS prediction_run_id
    
FROM ML.TEST_SET
WHERE 1=0;  -- Empty table, will be populated by Python script

SELECT 'PREDICTION_SUMMARY table created (template)' AS status;

-- ============================================================================
-- PART 9: MODEL VALIDATION SUMMARY
-- ============================================================================

CREATE OR REPLACE TABLE ML.MODEL_VALIDATION_SUMMARY (
    validation_id NUMBER AUTOINCREMENT,
    validation_check STRING NOT NULL,
    status STRING NOT NULL,  -- 'PASS', 'WARN', 'FAIL'
    details STRING,
    threshold_value FLOAT,
    actual_value FLOAT,
    checked_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    
    CONSTRAINT pk_model_validation PRIMARY KEY (validation_id)
);

SELECT 'MODEL_VALIDATION_SUMMARY table created' AS status;

-- ============================================================================
-- PART 10: MODEL COMPARISON VIEW
-- ============================================================================

CREATE OR REPLACE VIEW ML.MODEL_COMPARISON AS
SELECT 
    model_name,
    task,
    
    -- Performance metrics
    CASE WHEN task = 'regression' THEN val_r2 ELSE NULL END AS r2_score,
    CASE WHEN task = 'regression' THEN val_rmse ELSE NULL END AS rmse,
    CASE WHEN task = 'classification' THEN val_f1 ELSE NULL END AS f1_score,
    CASE WHEN task = 'classification' THEN val_auc ELSE NULL END AS auc_score,
    
    -- Cross-validation metrics
    CASE WHEN task = 'regression' THEN cv_rmse ELSE NULL END AS cv_rmse,
    CASE WHEN task = 'classification' THEN cv_f1 ELSE NULL END AS cv_f1,
    cv_std,
    
    -- Rank models by performance
    CASE 
        WHEN task = 'regression' 
        THEN RANK() OVER (PARTITION BY task ORDER BY val_r2 DESC)
        ELSE RANK() OVER (PARTITION BY task ORDER BY val_f1 DESC)
    END AS performance_rank,
    
    created_at
    
FROM ML.MODEL_RESULTS
ORDER BY task, performance_rank;

SELECT 'MODEL_COMPARISON view created' AS status;

-- ============================================================================
-- PART 11: TOP FEATURES VIEW
-- ============================================================================

CREATE OR REPLACE VIEW ML.TOP_FEATURES AS
SELECT 
    model_name,
    feature_name,
    importance_score,
    RANK() OVER (PARTITION BY model_name ORDER BY importance_score DESC) AS feature_rank
FROM ML.FEATURE_IMPORTANCE
QUALIFY feature_rank <= 15;

SELECT 'TOP_FEATURES view created' AS status;

-- ============================================================================
-- PART 12: PREDICTION ACCURACY VIEW
-- ============================================================================

CREATE OR REPLACE VIEW ML.PREDICTION_ACCURACY AS
SELECT 
    model_name,
    COUNT(*) AS total_predictions,
    
    -- Regression accuracy
    AVG(ABS(prediction_error)) AS mae,
    SQRT(AVG(POWER(prediction_error, 2))) AS rmse,
    CORR(predicted_spoilage_rate, actual_spoilage_rate) AS correlation,
    
    created_at
    
FROM ML.PREDICTIONS_REGRESSION
WHERE actual_spoilage_rate IS NOT NULL
GROUP BY model_name, created_at;

SELECT 'PREDICTION_ACCURACY view created' AS status;

-- ============================================================================
-- PART 13: UPDATE LOAD AUDIT
-- ============================================================================

INSERT INTO ML.LOAD_AUDIT (table_name, rows_loaded, load_timestamp, status)
VALUES 
    ('MODEL_RESULTS', 0, CURRENT_TIMESTAMP(), 'SCHEMA_CREATED'),
    ('MODEL_METADATA', 0, CURRENT_TIMESTAMP(), 'SCHEMA_CREATED'),
    ('FEATURE_IMPORTANCE', 0, CURRENT_TIMESTAMP(), 'SCHEMA_CREATED'),
    ('PREDICTIONS', 0, CURRENT_TIMESTAMP(), 'SCHEMA_CREATED');

-- ============================================================================
-- FINAL SUMMARY
-- ============================================================================

SELECT 
    '================================================' AS summary
UNION ALL
SELECT 'PHASE 5: MODEL TRAINING SCHEMA COMPLETE'
UNION ALL
SELECT '================================================'
UNION ALL
SELECT 'Tables Created: ' || COUNT(DISTINCT TABLE_NAME)
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'ML'
  AND TABLE_TYPE = 'BASE TABLE'
  AND TABLE_NAME IN (
      'MODEL_RESULTS', 'MODEL_METADATA', 'FEATURE_IMPORTANCE', 
      'SHAP_SUMMARY', 'PREDICTIONS', 'PREDICTIONS_REGRESSION',
      'PREDICTIONS_CLASSIFICATION', 'PREDICTION_SUMMARY',
      'MODEL_VALIDATION_SUMMARY'
  );

-- Show all ML tables
SELECT 
    TABLE_NAME,
    ROW_COUNT,
    BYTES / 1024 / 1024 AS SIZE_MB
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'ML'
  AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;

