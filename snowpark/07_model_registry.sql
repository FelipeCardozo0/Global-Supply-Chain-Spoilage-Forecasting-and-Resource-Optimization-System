-- =====================================================
-- PHASE 7: MODEL REGISTRY & ARTIFACT STORE
-- Global Supply Chain Spoilage Forecasting Project
-- Model Versioning, Artifact Management, Promotion/Demotion
-- =====================================================

USE DATABASE GLOBAL_SPOILAGE_DB;
USE SCHEMA ML;

-- =====================================================
-- 1. MODEL REGISTRY TABLES
-- =====================================================

-- Create model registry catalog
CREATE OR REPLACE TABLE ML.MODEL_REGISTRY (
    model_id STRING DEFAULT UUID_STRING(),
    model_name STRING NOT NULL,
    model_version STRING NOT NULL,
    model_type STRING,  -- REGRESSION, CLASSIFICATION, CLUSTERING, etc.
    algorithm STRING,  -- RandomForest, XGBoost, DecisionTree, etc.
    framework STRING,  -- SKLEARN, XGBOOST, TENSORFLOW, PYTORCH
    created_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    created_by STRING,
    training_dataset STRING,
    training_start_timestamp TIMESTAMP,
    training_end_timestamp TIMESTAMP,
    training_duration_seconds FLOAT,
    hyperparameters VARIANT,
    feature_list ARRAY,
    target_variable STRING,
    model_size_bytes NUMBER,
    artifact_path STRING,
    artifact_hash STRING,  -- SHA256 hash for integrity
    status STRING,  -- TRAINING, STAGING, PRODUCTION, ARCHIVED, DEPRECATED
    environment STRING,  -- DEV, STG, PRD
    approval_status STRING,  -- PENDING, APPROVED, REJECTED
    approved_by STRING,
    approved_timestamp TIMESTAMP,
    tags VARIANT,
    description STRING,
    PRIMARY KEY (model_id),
    UNIQUE (model_name, model_version)
);

-- Create model performance metrics
CREATE OR REPLACE TABLE ML.MODEL_PERFORMANCE_METRICS (
    metric_id STRING DEFAULT UUID_STRING(),
    model_id STRING NOT NULL,
    model_version STRING,
    evaluation_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    dataset_type STRING,  -- TRAIN, VALIDATION, TEST, PRODUCTION
    metric_name STRING,  -- ACCURACY, PRECISION, RECALL, F1, RMSE, MAE, R2, AUC
    metric_value FLOAT,
    sample_size NUMBER,
    evaluation_period_start TIMESTAMP,
    evaluation_period_end TIMESTAMP,
    confidence_interval VARIANT,
    PRIMARY KEY (metric_id),
    FOREIGN KEY (model_id) REFERENCES ML.MODEL_REGISTRY(model_id)
);

-- Create model lineage tracking
CREATE OR REPLACE TABLE ML.MODEL_LINEAGE (
    lineage_id STRING DEFAULT UUID_STRING(),
    model_id STRING NOT NULL,
    parent_model_id STRING,
    lineage_type STRING,  -- TRAINED_FROM, FINE_TUNED_FROM, RETRAINED_FROM, DERIVED_FROM
    relationship_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    relationship_metadata VARIANT,
    PRIMARY KEY (lineage_id),
    FOREIGN KEY (model_id) REFERENCES ML.MODEL_REGISTRY(model_id)
);

-- Create model deployment history
CREATE OR REPLACE TABLE ML.MODEL_DEPLOYMENT_HISTORY (
    deployment_id STRING DEFAULT UUID_STRING(),
    model_id STRING NOT NULL,
    model_version STRING,
    deployment_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    deployment_type STRING,  -- INITIAL, UPGRADE, ROLLBACK, CANARY, BLUE_GREEN
    source_environment STRING,
    target_environment STRING,
    deployed_by STRING,
    deployment_config VARIANT,
    status STRING,  -- DEPLOYING, DEPLOYED, FAILED, ROLLED_BACK
    health_check_status STRING,
    rollback_model_id STRING,
    deployment_notes STRING,
    PRIMARY KEY (deployment_id),
    FOREIGN KEY (model_id) REFERENCES ML.MODEL_REGISTRY(model_id)
);

-- Create artifact store metadata
CREATE OR REPLACE TABLE ML.ARTIFACT_STORE (
    artifact_id STRING DEFAULT UUID_STRING(),
    model_id STRING,
    artifact_name STRING NOT NULL,
    artifact_type STRING,  -- MODEL_BINARY, FEATURE_TRANSFORMER, SCALER, ENCODER, CONFIG
    artifact_version STRING,
    artifact_size_bytes NUMBER,
    artifact_format STRING,  -- PICKLE, JOBLIB, ONNX, H5, PT
    artifact_path STRING,
    artifact_hash STRING,  -- SHA256 hash
    checksum_algorithm STRING DEFAULT 'SHA256',
    storage_location STRING,  -- STAGE, S3, GCS, AZURE_BLOB
    created_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    created_by STRING,
    compression_type STRING,
    encryption_status STRING,  -- ENCRYPTED, UNENCRYPTED
    retention_days NUMBER,
    expiration_date DATE,
    tags VARIANT,
    metadata VARIANT,
    PRIMARY KEY (artifact_id),
    FOREIGN KEY (model_id) REFERENCES ML.MODEL_REGISTRY(model_id)
);

-- Create model approval workflow
CREATE OR REPLACE TABLE ML.MODEL_APPROVAL_WORKFLOW (
    approval_id STRING DEFAULT UUID_STRING(),
    model_id STRING NOT NULL,
    model_version STRING,
    submission_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    submitted_by STRING,
    target_environment STRING,
    approval_status STRING,  -- PENDING, IN_REVIEW, APPROVED, REJECTED, WITHDRAWN
    reviewer_role STRING,
    reviewed_by STRING,
    review_timestamp TIMESTAMP,
    review_comments STRING,
    approval_criteria VARIANT,
    test_results VARIANT,
    PRIMARY KEY (approval_id),
    FOREIGN KEY (model_id) REFERENCES ML.MODEL_REGISTRY(model_id)
);

-- Create model experiments tracking
CREATE OR REPLACE TABLE ML.MODEL_EXPERIMENTS (
    experiment_id STRING DEFAULT UUID_STRING(),
    experiment_name STRING NOT NULL,
    experiment_description STRING,
    created_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    created_by STRING,
    status STRING,  -- RUNNING, COMPLETED, FAILED, CANCELLED
    start_timestamp TIMESTAMP,
    end_timestamp TIMESTAMP,
    parameters VARIANT,
    metrics VARIANT,
    artifacts VARIANT,
    tags VARIANT,
    notes STRING,
    PRIMARY KEY (experiment_id)
);

-- =====================================================
-- 2. STAGE FOR MODEL ARTIFACTS
-- =====================================================

-- Create stage for model artifacts
CREATE OR REPLACE STAGE ML.MODEL_ARTIFACTS_STAGE
    DIRECTORY = (ENABLE = TRUE)
    FILE_FORMAT = (TYPE = 'BINARY')
    COMMENT = 'Stage for storing model artifacts and binaries';

-- Grant permissions
GRANT READ, WRITE ON STAGE ML.MODEL_ARTIFACTS_STAGE TO ROLE DATA_SCIENTIST_ROLE;
GRANT READ, WRITE ON STAGE ML.MODEL_ARTIFACTS_STAGE TO ROLE OPS_TASK_ROLE;
GRANT READ ON STAGE ML.MODEL_ARTIFACTS_STAGE TO ROLE OPS_MONITOR_ROLE;

-- =====================================================
-- 3. MODEL PROMOTION PROCEDURES
-- =====================================================

-- Create procedure to promote model
CREATE OR REPLACE PROCEDURE ML.PROMOTE_MODEL(
    p_model_id STRING,
    p_source_env STRING,
    p_target_env STRING,
    p_promoted_by STRING
)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    -- Validate model exists
    LET model_exists NUMBER := (
        SELECT COUNT(*) FROM ML.MODEL_REGISTRY WHERE model_id = :p_model_id
    );
    
    IF (model_exists = 0) THEN
        RETURN 'ERROR: Model not found: ' || :p_model_id;
    END IF;
    
    -- Check if model is approved for target environment
    LET is_approved NUMBER := (
        SELECT COUNT(*) 
        FROM ML.MODEL_APPROVAL_WORKFLOW 
        WHERE model_id = :p_model_id 
        AND target_environment = :p_target_env
        AND approval_status = 'APPROVED'
    );
    
    IF (is_approved = 0 AND :p_target_env = 'PRD') THEN
        RETURN 'ERROR: Model not approved for production deployment';
    END IF;
    
    -- Get current production model (if any) for rollback
    LET current_prod_model_id STRING := (
        SELECT model_id 
        FROM ML.MODEL_REGISTRY 
        WHERE status = 'PRODUCTION' 
        AND environment = :p_target_env
        LIMIT 1
    );
    
    -- Demote current production model
    IF (:current_prod_model_id IS NOT NULL) THEN
        UPDATE ML.MODEL_REGISTRY
        SET status = 'ARCHIVED',
            environment = :p_source_env
        WHERE model_id = :current_prod_model_id;
    END IF;
    
    -- Promote new model
    UPDATE ML.MODEL_REGISTRY
    SET status = 'PRODUCTION',
        environment = :p_target_env,
        approved_by = :p_promoted_by,
        approved_timestamp = CURRENT_TIMESTAMP()
    WHERE model_id = :p_model_id;
    
    -- Log deployment
    INSERT INTO ML.MODEL_DEPLOYMENT_HISTORY (
        model_id, 
        deployment_type, 
        source_environment, 
        target_environment,
        deployed_by,
        status,
        rollback_model_id
    )
    SELECT 
        :p_model_id,
        'UPGRADE',
        :p_source_env,
        :p_target_env,
        :p_promoted_by,
        'DEPLOYED',
        :current_prod_model_id;
    
    RETURN 'SUCCESS: Model promoted to ' || :p_target_env;
END;
$$;

-- Create procedure to demote/rollback model
CREATE OR REPLACE PROCEDURE ML.ROLLBACK_MODEL(
    p_model_id STRING,
    p_rollback_to_model_id STRING,
    p_rolled_back_by STRING
)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    -- Validate models exist
    LET model_exists NUMBER := (
        SELECT COUNT(*) FROM ML.MODEL_REGISTRY 
        WHERE model_id IN (:p_model_id, :p_rollback_to_model_id)
    );
    
    IF (model_exists < 2) THEN
        RETURN 'ERROR: One or both models not found';
    END IF;
    
    -- Get current environment
    LET current_env STRING := (
        SELECT environment FROM ML.MODEL_REGISTRY WHERE model_id = :p_model_id
    );
    
    -- Demote current model
    UPDATE ML.MODEL_REGISTRY
    SET status = 'DEPRECATED',
        environment = 'DEV'
    WHERE model_id = :p_model_id;
    
    -- Restore previous model
    UPDATE ML.MODEL_REGISTRY
    SET status = 'PRODUCTION',
        environment = :current_env
    WHERE model_id = :p_rollback_to_model_id;
    
    -- Log rollback
    INSERT INTO ML.MODEL_DEPLOYMENT_HISTORY (
        model_id,
        deployment_type,
        target_environment,
        deployed_by,
        status,
        rollback_model_id
    )
    VALUES (
        :p_rollback_to_model_id,
        'ROLLBACK',
        :current_env,
        :p_rolled_back_by,
        'DEPLOYED',
        :p_model_id
    );
    
    RETURN 'SUCCESS: Model rolled back';
END;
$$;

-- =====================================================
-- 4. ARTIFACT MANAGEMENT PROCEDURES
-- =====================================================

-- Create procedure to register artifact
CREATE OR REPLACE PROCEDURE ML.REGISTER_ARTIFACT(
    p_model_id STRING,
    p_artifact_name STRING,
    p_artifact_type STRING,
    p_artifact_path STRING,
    p_artifact_hash STRING
)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    INSERT INTO ML.ARTIFACT_STORE (
        model_id,
        artifact_name,
        artifact_type,
        artifact_path,
        artifact_hash,
        storage_location,
        created_by
    )
    VALUES (
        :p_model_id,
        :p_artifact_name,
        :p_artifact_type,
        :p_artifact_path,
        :p_artifact_hash,
        'STAGE',
        CURRENT_USER()
    );
    
    RETURN 'SUCCESS: Artifact registered';
END;
$$;

-- =====================================================
-- 5. POPULATE INITIAL REGISTRY DATA
-- =====================================================

-- Register existing models from Phase 5
INSERT INTO ML.MODEL_REGISTRY (
    model_name,
    model_version,
    model_type,
    algorithm,
    framework,
    created_by,
    training_dataset,
    hyperparameters,
    feature_list,
    status,
    environment,
    approval_status
)
VALUES
    ('dt_reg', 'v1.0.0', 'REGRESSION', 'DecisionTree', 'SKLEARN', 'SYSTEM', 'ML.TRAIN_SET', 
     PARSE_JSON('{"max_depth": 10, "random_state": 42}'), 
     ARRAY_CONSTRUCT('FEDFUNDS_RATE', 'RETAIL_SALES', 'TREASURY_10Y_RATE'), 
     'PRODUCTION', 'PRD', 'APPROVED'),
    ('rf_reg', 'v1.0.0', 'REGRESSION', 'RandomForest', 'SKLEARN', 'SYSTEM', 'ML.TRAIN_SET',
     PARSE_JSON('{"n_estimators": 100, "max_depth": 10, "random_state": 42}'),
     ARRAY_CONSTRUCT('FEDFUNDS_RATE', 'RETAIL_SALES', 'TREASURY_10Y_RATE'),
     'PRODUCTION', 'PRD', 'APPROVED'),
    ('dt_clf', 'v1.0.0', 'CLASSIFICATION', 'DecisionTree', 'SKLEARN', 'SYSTEM', 'ML.TRAIN_SET',
     PARSE_JSON('{"max_depth": 10, "random_state": 42}'),
     ARRAY_CONSTRUCT('FEDFUNDS_RATE', 'RETAIL_SALES', 'TREASURY_10Y_RATE'),
     'PRODUCTION', 'PRD', 'APPROVED'),
    ('rf_clf', 'v1.0.0', 'CLASSIFICATION', 'RandomForest', 'SKLEARN', 'SYSTEM', 'ML.TRAIN_SET',
     PARSE_JSON('{"n_estimators": 100, "max_depth": 10, "random_state": 42}'),
     ARRAY_CONSTRUCT('FEDFUNDS_RATE', 'RETAIL_SALES', 'TREASURY_10Y_RATE'),
     'PRODUCTION', 'PRD', 'APPROVED');

-- Register model performance metrics
INSERT INTO ML.MODEL_PERFORMANCE_METRICS (
    model_id,
    model_version,
    dataset_type,
    metric_name,
    metric_value
)
SELECT 
    mr.model_id,
    mr.model_version,
    'VALIDATION',
    'ACCURACY',
    1.0
FROM ML.MODEL_REGISTRY mr
WHERE mr.model_type = 'CLASSIFICATION';

INSERT INTO ML.MODEL_PERFORMANCE_METRICS (
    model_id,
    model_version,
    dataset_type,
    metric_name,
    metric_value
)
SELECT 
    mr.model_id,
    mr.model_version,
    'VALIDATION',
    'R2',
    1.0
FROM ML.MODEL_REGISTRY mr
WHERE mr.model_type = 'REGRESSION';

-- Create initial deployment records
INSERT INTO ML.MODEL_DEPLOYMENT_HISTORY (
    model_id,
    model_version,
    deployment_type,
    source_environment,
    target_environment,
    deployed_by,
    status
)
SELECT 
    model_id,
    model_version,
    'INITIAL',
    'DEV',
    'PRD',
    'SYSTEM',
    'DEPLOYED'
FROM ML.MODEL_REGISTRY;

-- =====================================================
-- 6. GRANT PERMISSIONS
-- =====================================================

GRANT SELECT ON ALL TABLES IN SCHEMA ML TO ROLE READONLY_ROLE;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA ML TO ROLE DATA_SCIENTIST_ROLE;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ML TO ROLE OPS_TASK_ROLE;

GRANT USAGE ON PROCEDURE ML.PROMOTE_MODEL(STRING, STRING, STRING, STRING) TO ROLE DATA_SCIENTIST_ROLE;
GRANT USAGE ON PROCEDURE ML.PROMOTE_MODEL(STRING, STRING, STRING, STRING) TO ROLE OPS_TASK_ROLE;

GRANT USAGE ON PROCEDURE ML.ROLLBACK_MODEL(STRING, STRING, STRING) TO ROLE OPS_TASK_ROLE;
GRANT USAGE ON PROCEDURE ML.ROLLBACK_MODEL(STRING, STRING, STRING) TO ROLE PLATFORM_ADMIN;

GRANT USAGE ON PROCEDURE ML.REGISTER_ARTIFACT(STRING, STRING, STRING, STRING, STRING) TO ROLE DATA_SCIENTIST_ROLE;
GRANT USAGE ON PROCEDURE ML.REGISTER_ARTIFACT(STRING, STRING, STRING, STRING, STRING) TO ROLE OPS_TASK_ROLE;

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
    'PHASE7_MODEL_REGISTRY_' || CURRENT_TIMESTAMP()::STRING,
    'PHASE_7',
    'MODEL_REGISTRY_SETUP',
    CURRENT_TIMESTAMP(),
    'SUCCESS',
    (SELECT COUNT(*) FROM ML.MODEL_REGISTRY),
    0,
    NULL
);

-- Success message
SELECT 'Phase 7: Model Registry setup completed successfully!' AS status;
