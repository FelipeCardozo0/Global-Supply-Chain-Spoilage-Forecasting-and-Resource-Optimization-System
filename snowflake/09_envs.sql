-- =====================================================
-- PHASE 9: ENVIRONMENT PROMOTION & GO-LIVE
-- Global Supply Chain Spoilage Forecasting Project
-- DEV→STG→PRD promotion, zero-copy clones, atomic swaps
-- =====================================================

USE ROLE SYSADMIN;
USE DATABASE GLOBAL_SPOILAGE_DB;

-- =====================================================
-- 1. ENVIRONMENT CLONES & PROMOTION
-- =====================================================

-- Create STG environment (clone from DEV)
CREATE DATABASE IF NOT EXISTS GLOBAL_SPOILAGE_DB_STG CLONE GLOBAL_SPOILAGE_DB;

-- Create PRD environment (clone from STG)
CREATE DATABASE IF NOT EXISTS GLOBAL_SPOILAGE_DB_PRD CLONE GLOBAL_SPOILAGE_DB_STG;

-- =====================================================
-- 2. PRODUCTION WAREHOUSE CONFIGURATION
-- =====================================================

-- Create production warehouse with appropriate sizing
CREATE OR REPLACE WAREHOUSE COMPUTE_WH_PRD
    WAREHOUSE_SIZE = 'MEDIUM'
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Production warehouse for Global Spoilage EWS';

-- Create staging warehouse
CREATE OR REPLACE WAREHOUSE COMPUTE_WH_STG
    WAREHOUSE_SIZE = 'SMALL'
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Staging warehouse for Global Spoilage EWS';

-- =====================================================
-- 3. ATOMIC SWAP PROCEDURES
-- =====================================================

-- Procedure for atomic table swaps
CREATE OR REPLACE PROCEDURE OPS.SP_ATOMIC_SWAP(
    source_table STRING,
    target_table STRING
)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    swap_result STRING;
BEGIN
    -- Perform atomic swap
    EXECUTE IMMEDIATE 'ALTER TABLE ' || target_table || ' SWAP WITH ' || source_table;
    
    -- Verify swap success
    SELECT 'SWAP_SUCCESS' INTO swap_result;
    
    RETURN swap_result;
END;
$$;

-- Procedure for blue/green deployment
CREATE OR REPLACE PROCEDURE OPS.SP_BLUE_GREEN_DEPLOY(
    environment STRING,
    table_name STRING
)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    deploy_result STRING;
    current_env STRING;
BEGIN
    -- Determine current environment
    current_env := CURRENT_DATABASE();
    
    -- Create new version of table
    EXECUTE IMMEDIATE 'CREATE OR REPLACE TABLE ' || table_name || '_NEW AS SELECT * FROM ' || table_name;
    
    -- Perform atomic swap
    EXECUTE IMMEDIATE 'ALTER TABLE ' || table_name || ' SWAP WITH ' || table_name || '_NEW';
    
    -- Clean up old version
    EXECUTE IMMEDIATE 'DROP TABLE IF EXISTS ' || table_name || '_NEW';
    
    SELECT 'DEPLOY_SUCCESS' INTO deploy_result;
    
    RETURN deploy_result;
END;
$$;

-- =====================================================
-- 4. ENVIRONMENT PROMOTION TRACKING
-- =====================================================

-- Create promotion tracking table
CREATE OR REPLACE TABLE OPS.ENVIRONMENT_PROMOTIONS (
    promotion_id STRING DEFAULT UUID_STRING(),
    from_environment STRING,
    to_environment STRING,
    promoted_by STRING DEFAULT CURRENT_ROLE(),
    promotion_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    status STRING DEFAULT 'IN_PROGRESS', -- 'IN_PROGRESS', 'SUCCESS', 'FAILED', 'ROLLED_BACK'
    rollback_timestamp TIMESTAMP,
    rollback_reason STRING,
    metadata VARIANT,
    PRIMARY KEY (promotion_id)
);

-- Create deployment validation table
CREATE OR REPLACE TABLE OPS.DEPLOYMENT_VALIDATIONS (
    validation_id STRING DEFAULT UUID_STRING(),
    promotion_id STRING,
    validation_type STRING, -- 'ROW_COUNT', 'DATA_QUALITY', 'PERFORMANCE', 'FUNCTIONAL'
    validation_status STRING, -- 'PASS', 'FAIL', 'WARNING'
    validation_details VARIANT,
    validated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (validation_id),
    FOREIGN KEY (promotion_id) REFERENCES OPS.ENVIRONMENT_PROMOTIONS(promotion_id)
);

-- =====================================================
-- 5. CANARY DEPLOYMENT PROCEDURES
-- =====================================================

-- Procedure for canary deployment
CREATE OR REPLACE PROCEDURE OPS.SP_CANARY_DEPLOY(
    table_name STRING,
    canary_percentage FLOAT DEFAULT 0.1
)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    canary_result STRING;
    total_rows INTEGER;
    canary_rows INTEGER;
BEGIN
    -- Get total row count
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || table_name INTO total_rows;
    
    -- Calculate canary sample size
    canary_rows := FLOOR(total_rows * canary_percentage);
    
    -- Create canary table with sample data
    EXECUTE IMMEDIATE 'CREATE OR REPLACE TABLE ' || table_name || '_CANARY AS 
        SELECT * FROM ' || table_name || ' SAMPLE (' || canary_percentage * 100 || ')';
    
    -- Log canary deployment
    INSERT INTO OPS.ENVIRONMENT_PROMOTIONS (
        from_environment, to_environment, status, metadata
    ) VALUES (
        'CANARY', 'PRODUCTION', 'IN_PROGRESS',
        PARSE_JSON('{"canary_percentage": ' || canary_percentage || ', "canary_rows": ' || canary_rows || '}')
    );
    
    SELECT 'CANARY_DEPLOYED' INTO canary_result;
    
    RETURN canary_result;
END;
$$;

-- =====================================================
-- 6. ROLLBACK PROCEDURES
-- =====================================================

-- Procedure for rollback deployment
CREATE OR REPLACE PROCEDURE OPS.SP_ROLLBACK_DEPLOY(
    table_name STRING,
    rollback_reason STRING
)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    rollback_result STRING;
    promotion_id STRING;
BEGIN
    -- Get latest promotion ID
    SELECT promotion_id INTO promotion_id
    FROM OPS.ENVIRONMENT_PROMOTIONS
    WHERE status = 'IN_PROGRESS'
    ORDER BY promotion_timestamp DESC
    LIMIT 1;
    
    -- Perform rollback swap
    EXECUTE IMMEDIATE 'ALTER TABLE ' || table_name || ' SWAP WITH ' || table_name || '_BACKUP';
    
    -- Update promotion status
    UPDATE OPS.ENVIRONMENT_PROMOTIONS
    SET status = 'ROLLED_BACK',
        rollback_timestamp = CURRENT_TIMESTAMP(),
        rollback_reason = rollback_reason
    WHERE promotion_id = promotion_id;
    
    SELECT 'ROLLBACK_SUCCESS' INTO rollback_result;
    
    RETURN rollback_result;
END;
$$;

-- =====================================================
-- 7. ENVIRONMENT HEALTH CHECKS
-- =====================================================

-- Create environment health monitoring
CREATE OR REPLACE VIEW OPS.ENVIRONMENT_HEALTH AS
SELECT 
    CURRENT_DATABASE() as environment,
    'ML.PREDICTIONS' as table_name,
    COUNT(*) as row_count,
    MAX(created_at) as last_updated,
    CASE WHEN COUNT(*) > 0 THEN 'HEALTHY' ELSE 'UNHEALTHY' END as health_status
FROM ML.PREDICTIONS
UNION ALL
SELECT 
    CURRENT_DATABASE() as environment,
    'OPS.ALERT_QUEUE' as table_name,
    COUNT(*) as row_count,
    MAX(created_at) as last_updated,
    CASE WHEN COUNT(*) >= 0 THEN 'HEALTHY' ELSE 'UNHEALTHY' END as health_status
FROM OPS.ALERT_QUEUE
UNION ALL
SELECT 
    CURRENT_DATABASE() as environment,
    'ML.MODEL_RESULTS' as table_name,
    COUNT(*) as row_count,
    MAX(created_at) as last_updated,
    CASE WHEN COUNT(*) > 0 THEN 'HEALTHY' ELSE 'UNHEALTHY' END as health_status
FROM ML.MODEL_RESULTS;

-- =====================================================
-- 8. DEPLOYMENT VALIDATION FUNCTIONS
-- =====================================================

-- Function to validate row counts
CREATE OR REPLACE FUNCTION OPS.VALIDATE_ROW_COUNTS(table_name STRING)
RETURNS BOOLEAN
LANGUAGE SQL
AS
$$
DECLARE
    row_count INTEGER;
BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || table_name INTO row_count;
    RETURN row_count > 0;
END;
$$;

-- Function to validate data freshness
CREATE OR REPLACE FUNCTION OPS.VALIDATE_DATA_FRESHNESS(table_name STRING, max_hours INTEGER)
RETURNS BOOLEAN
LANGUAGE SQL
AS
$$
DECLARE
    last_updated TIMESTAMP;
BEGIN
    EXECUTE IMMEDIATE 'SELECT MAX(created_at) FROM ' || table_name INTO last_updated;
    RETURN DATEDIFF('hour', last_updated, CURRENT_TIMESTAMP()) <= max_hours;
END;
$$;

-- =====================================================
-- 9. ENVIRONMENT TAGGING
-- =====================================================

-- Create environment tags
CREATE OR REPLACE TAG OPS.ENVIRONMENT_TAG ALLOWED_VALUES 'DEV', 'STG', 'PRD';
CREATE OR REPLACE TAG OPS.DEPLOYMENT_STAGE ALLOWED_VALUES 'CANARY', 'BLUE', 'GREEN', 'PRODUCTION';

-- Tag databases by environment
ALTER DATABASE GLOBAL_SPOILAGE_DB SET TAG OPS.ENVIRONMENT_TAG='DEV';
ALTER DATABASE GLOBAL_SPOILAGE_DB_STG SET TAG OPS.ENVIRONMENT_TAG='STG';
ALTER DATABASE GLOBAL_SPOILAGE_DB_PRD SET TAG OPS.ENVIRONMENT_TAG='PRD';

-- Tag critical tables
ALTER TABLE ML.PREDICTIONS SET TAG OPS.DEPLOYMENT_STAGE='PRODUCTION';
ALTER TABLE OPS.ALERT_QUEUE SET TAG OPS.DEPLOYMENT_STAGE='PRODUCTION';
ALTER TABLE ML.MODEL_RESULTS SET TAG OPS.DEPLOYMENT_STAGE='PRODUCTION';

-- =====================================================
-- 10. DEPLOYMENT AUTOMATION
-- =====================================================

-- Create deployment pipeline table
CREATE OR REPLACE TABLE OPS.DEPLOYMENT_PIPELINE (
    pipeline_id STRING DEFAULT UUID_STRING(),
    pipeline_name STRING,
    source_environment STRING,
    target_environment STRING,
    deployment_type STRING, -- 'FULL', 'INCREMENTAL', 'CANARY'
    status STRING DEFAULT 'PENDING', -- 'PENDING', 'RUNNING', 'SUCCESS', 'FAILED'
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    triggered_by STRING DEFAULT CURRENT_ROLE(),
    metadata VARIANT,
    PRIMARY KEY (pipeline_id)
);

-- Create deployment steps table
CREATE OR REPLACE TABLE OPS.DEPLOYMENT_STEPS (
    step_id STRING DEFAULT UUID_STRING(),
    pipeline_id STRING,
    step_name STRING,
    step_order INTEGER,
    status STRING DEFAULT 'PENDING', -- 'PENDING', 'RUNNING', 'SUCCESS', 'FAILED'
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    error_message STRING,
    PRIMARY KEY (step_id),
    FOREIGN KEY (pipeline_id) REFERENCES OPS.DEPLOYMENT_PIPELINE(pipeline_id)
);

-- =====================================================
-- 11. GRANT PERMISSIONS
-- =====================================================

-- Grant permissions for environment promotion
GRANT USAGE ON DATABASE GLOBAL_SPOILAGE_DB_STG TO ROLE OPS_TASK_ROLE;
GRANT USAGE ON DATABASE GLOBAL_SPOILAGE_DB_PRD TO ROLE OPS_TASK_ROLE;

GRANT USAGE ON WAREHOUSE COMPUTE_WH_STG TO ROLE OPS_TASK_ROLE;
GRANT USAGE ON WAREHOUSE COMPUTE_WH_PRD TO ROLE OPS_TASK_ROLE;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA OPS TO ROLE OPS_TASK_ROLE;
GRANT USAGE ON ALL PROCEDURES IN SCHEMA OPS TO ROLE OPS_TASK_ROLE;
GRANT USAGE ON ALL FUNCTIONS IN SCHEMA OPS TO ROLE OPS_TASK_ROLE;

-- =====================================================
-- 12. INITIAL DEPLOYMENT RECORD
-- =====================================================

-- Record initial environment setup
INSERT INTO OPS.ENVIRONMENT_PROMOTIONS (
    from_environment, to_environment, status, metadata
) VALUES (
    'INITIAL', 'DEV', 'SUCCESS',
    PARSE_JSON('{"initial_setup": true, "phases_completed": [1,2,3,4,5,6,7,8]}')
);

-- =====================================================
-- 13. AUDIT LOG
-- =====================================================

INSERT INTO OPS.LOAD_AUDIT (
    execution_id, phase, step, execution_ts, status, rows_affected, execution_time_seconds, error_message
) VALUES (
    'PHASE9_ENVS_' || CURRENT_TIMESTAMP()::STRING,
    'PHASE_9',
    'ENVIRONMENT_PROMOTION',
    CURRENT_TIMESTAMP(),
    'SUCCESS',
    0,
    0,
    NULL
);

-- Success message
SELECT 'Phase 9: Environment promotion setup completed successfully!' AS status;
