-- ============================================================================
-- PHASE 6: OPERATIONS & AUTOMATION - TASK DEFINITIONS
-- Global Supply Chain Spoilage and Resource Allocation Forecasting
-- ============================================================================
-- Purpose: Define Snowflake Tasks for automated pipeline execution
-- Prerequisites: Phases 1-5 complete
-- ============================================================================

USE DATABASE GLOBAL_SPOILAGE_DB;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================================
-- PART 1: CREATE OPS SCHEMA TABLES
-- ============================================================================

-- Task execution audit
CREATE OR REPLACE TABLE OPS.TASK_RUNS (
    run_id NUMBER AUTOINCREMENT,
    task_name STRING NOT NULL,
    execution_start TIMESTAMP_NTZ NOT NULL,
    execution_end TIMESTAMP_NTZ,
    status STRING NOT NULL,  -- 'RUNNING', 'SUCCESS', 'FAILED'
    rows_affected NUMBER,
    error_message STRING,
    duration_seconds NUMBER,
    warehouse_used STRING,
    credits_consumed FLOAT,
    
    CONSTRAINT pk_task_runs PRIMARY KEY (run_id)
);

-- Stream change tracking status
CREATE OR REPLACE TABLE OPS.STREAM_STATUS (
    stream_id NUMBER AUTOINCREMENT,
    stream_name STRING NOT NULL,
    source_table STRING NOT NULL,
    last_offset STRING,
    rows_inserted NUMBER DEFAULT 0,
    rows_updated NUMBER DEFAULT 0,
    rows_deleted NUMBER DEFAULT 0,
    last_processed TIMESTAMP_NTZ,
    
    CONSTRAINT pk_stream_status PRIMARY KEY (stream_id)
);

-- Consolidated audit log
CREATE OR REPLACE TABLE OPS.LOAD_AUDIT (
    audit_id NUMBER AUTOINCREMENT,
    phase STRING NOT NULL,
    component STRING NOT NULL,
    execution_timestamp TIMESTAMP_NTZ NOT NULL,
    runtime_seconds NUMBER,
    rows_processed NUMBER,
    status STRING NOT NULL,
    details STRING,
    
    CONSTRAINT pk_load_audit PRIMARY KEY (audit_id)
);

SELECT 'OPS schema tables created' AS status;

-- ============================================================================
-- PART 2: STORED PROCEDURES FOR TASK EXECUTION
-- ============================================================================

-- Procedure: Incremental data refresh (RAW → CORE)
CREATE OR REPLACE PROCEDURE OPS.SP_REFRESH_CORE_DATA()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    start_time TIMESTAMP_NTZ := CURRENT_TIMESTAMP();
    rows_updated NUMBER := 0;
    exec_status STRING := 'SUCCESS';
    error_msg STRING := NULL;
BEGIN
    -- Refresh FEDFUNDS
    MERGE INTO CORE.FEDFUNDS tgt
    USING (
        SELECT 
            TO_DATE(DATE) AS date,
            VALUE AS rate,
            CURRENT_TIMESTAMP() AS load_timestamp
        FROM RAW.FEDFUNDS_MONTHLY
        WHERE DATE >= DATEADD(month, -3, CURRENT_DATE())  -- Last 3 months only
    ) src
    ON tgt.date = src.date
    WHEN MATCHED THEN UPDATE SET 
        tgt.rate = src.rate,
        tgt.load_timestamp = src.load_timestamp
    WHEN NOT MATCHED THEN INSERT (date, rate, load_timestamp)
        VALUES (src.date, src.rate, src.load_timestamp);
    
    rows_updated := rows_updated + SQLROWCOUNT;
    
    -- Refresh RETAIL_SALES
    MERGE INTO CORE.RETAIL_SALES tgt
    USING (
        SELECT 
            TO_DATE(DATE) AS date,
            RETAIL_SALES_INDEX AS sales_index,
            CURRENT_TIMESTAMP() AS load_timestamp
        FROM RAW.RSXFS
        WHERE DATE >= DATEADD(month, -3, CURRENT_DATE())
    ) src
    ON tgt.date = src.date
    WHEN MATCHED THEN UPDATE SET 
        tgt.sales_index = src.sales_index,
        tgt.load_timestamp = src.load_timestamp
    WHEN NOT MATCHED THEN INSERT (date, sales_index, load_timestamp)
        VALUES (src.date, src.sales_index, src.load_timestamp);
    
    rows_updated := rows_updated + SQLROWCOUNT;
    
    -- Log execution
    INSERT INTO OPS.LOAD_AUDIT (phase, component, execution_timestamp, runtime_seconds, rows_processed, status, details)
    VALUES (
        'Phase 2',
        'SP_REFRESH_CORE_DATA',
        start_time,
        DATEDIFF(second, start_time, CURRENT_TIMESTAMP()),
        rows_updated,
        exec_status,
        'Incremental CORE data refresh completed'
    );
    
    RETURN 'SUCCESS: Refreshed ' || rows_updated || ' rows in CORE schema';
    
EXCEPTION
    WHEN OTHER THEN
        error_msg := SQLERRM;
        exec_status := 'FAILED';
        
        INSERT INTO OPS.LOAD_AUDIT (phase, component, execution_timestamp, runtime_seconds, rows_processed, status, details)
        VALUES (
            'Phase 2',
            'SP_REFRESH_CORE_DATA',
            start_time,
            DATEDIFF(second, start_time, CURRENT_TIMESTAMP()),
            0,
            exec_status,
            'ERROR: ' || error_msg
        );
        
        RETURN 'FAILED: ' || error_msg;
END;
$$;

-- Procedure: Recompute features (CORE → FEAT)
CREATE OR REPLACE PROCEDURE OPS.SP_REFRESH_FEATURES()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    start_time TIMESTAMP_NTZ := CURRENT_TIMESTAMP();
    rows_updated NUMBER := 0;
BEGIN
    -- Recompute rolling features for recent periods
    DELETE FROM FEAT.ROLLING_ECONOMIC_FEATURES 
    WHERE date >= DATEADD(month, -12, CURRENT_DATE());
    
    INSERT INTO FEAT.ROLLING_ECONOMIC_FEATURES
    SELECT 
        date,
        AVG(fedfunds_rate) OVER (ORDER BY date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS fedfunds_ma3,
        AVG(fedfunds_rate) OVER (ORDER BY date ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS fedfunds_ma6,
        AVG(fedfunds_rate) OVER (ORDER BY date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS fedfunds_ma12,
        AVG(retail_sales) OVER (ORDER BY date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS retail_ma3,
        AVG(retail_sales) OVER (ORDER BY date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS retail_ma12,
        STDDEV(retail_sales) OVER (ORDER BY date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS retail_volatility_12m,
        CURRENT_TIMESTAMP() AS created_at
    FROM CORE.ECONOMIC_MASTER
    WHERE date >= DATEADD(month, -13, CURRENT_DATE());
    
    rows_updated := SQLROWCOUNT;
    
    -- Log execution
    INSERT INTO OPS.LOAD_AUDIT (phase, component, execution_timestamp, runtime_seconds, rows_processed, status, details)
    VALUES (
        'Phase 3',
        'SP_REFRESH_FEATURES',
        start_time,
        DATEDIFF(second, start_time, CURRENT_TIMESTAMP()),
        rows_updated,
        'SUCCESS',
        'Incremental feature recomputation completed'
    );
    
    RETURN 'SUCCESS: Recomputed ' || rows_updated || ' rows in FEAT schema';
END;
$$;

-- Procedure: Trigger model retraining
CREATE OR REPLACE PROCEDURE OPS.SP_RETRAIN_MODELS()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    start_time TIMESTAMP_NTZ := CURRENT_TIMESTAMP();
BEGIN
    -- Log retraining request
    INSERT INTO OPS.LOAD_AUDIT (phase, component, execution_timestamp, runtime_seconds, rows_processed, status, details)
    VALUES (
        'Phase 5',
        'SP_RETRAIN_MODELS',
        start_time,
        0,
        0,
        'TRIGGERED',
        'Model retraining initiated - execute via Snowpark Python'
    );
    
    -- In production, this would call external procedure or trigger Snowpark job
    -- For now, we log the trigger
    
    RETURN 'SUCCESS: Model retraining triggered (execute ml_model_training.py)';
END;
$$;

-- Procedure: Refresh predictions
CREATE OR REPLACE PROCEDURE OPS.SP_REFRESH_PREDICTIONS()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    start_time TIMESTAMP_NTZ := CURRENT_TIMESTAMP();
BEGIN
    -- Log prediction refresh
    INSERT INTO OPS.LOAD_AUDIT (phase, component, execution_timestamp, runtime_seconds, rows_processed, status, details)
    VALUES (
        'Phase 5',
        'SP_REFRESH_PREDICTIONS',
        start_time,
        0,
        0,
        'TRIGGERED',
        'Prediction refresh initiated - execute via Snowpark Python'
    );
    
    RETURN 'SUCCESS: Prediction refresh triggered';
END;
$$;

SELECT 'Stored procedures created' AS status;

-- ============================================================================
-- PART 3: DEFINE SNOWFLAKE TASKS
-- ============================================================================

-- Task 1: Daily CORE data refresh (runs at 1 AM UTC daily)
CREATE OR REPLACE TASK OPS.TASK_DAILY_CORE_REFRESH
    WAREHOUSE = 'COMPUTE_WH'
    SCHEDULE = 'USING CRON 0 1 * * * UTC'
    COMMENT = 'Daily incremental refresh of CORE schema from RAW data'
AS
DECLARE
    task_start TIMESTAMP_NTZ := CURRENT_TIMESTAMP();
    result STRING;
BEGIN
    -- Record task start
    INSERT INTO OPS.TASK_RUNS (task_name, execution_start, status, warehouse_used)
    VALUES ('TASK_DAILY_CORE_REFRESH', task_start, 'RUNNING', 'COMPUTE_WH');
    
    -- Execute refresh
    result := (CALL OPS.SP_REFRESH_CORE_DATA());
    
    -- Record completion
    UPDATE OPS.TASK_RUNS
    SET 
        execution_end = CURRENT_TIMESTAMP(),
        status = CASE WHEN result LIKE 'SUCCESS%' THEN 'SUCCESS' ELSE 'FAILED' END,
        duration_seconds = DATEDIFF(second, task_start, CURRENT_TIMESTAMP())
    WHERE task_name = 'TASK_DAILY_CORE_REFRESH'
      AND execution_start = task_start;
END;

-- Task 2: Daily feature recomputation (runs at 2 AM UTC daily, after CORE refresh)
CREATE OR REPLACE TASK OPS.TASK_DAILY_FEATURE_REFRESH
    WAREHOUSE = 'COMPUTE_WH'
    AFTER OPS.TASK_DAILY_CORE_REFRESH
    COMMENT = 'Daily incremental feature recomputation'
AS
DECLARE
    task_start TIMESTAMP_NTZ := CURRENT_TIMESTAMP();
    result STRING;
BEGIN
    INSERT INTO OPS.TASK_RUNS (task_name, execution_start, status, warehouse_used)
    VALUES ('TASK_DAILY_FEATURE_REFRESH', task_start, 'RUNNING', 'COMPUTE_WH');
    
    result := (CALL OPS.SP_REFRESH_FEATURES());
    
    UPDATE OPS.TASK_RUNS
    SET 
        execution_end = CURRENT_TIMESTAMP(),
        status = CASE WHEN result LIKE 'SUCCESS%' THEN 'SUCCESS' ELSE 'FAILED' END,
        duration_seconds = DATEDIFF(second, task_start, CURRENT_TIMESTAMP())
    WHERE task_name = 'TASK_DAILY_FEATURE_REFRESH'
      AND execution_start = task_start;
END;

-- Task 3: Weekly model retraining (runs Monday at 6 AM UTC)
CREATE OR REPLACE TASK OPS.TASK_WEEKLY_MODEL_RETRAIN
    WAREHOUSE = 'COMPUTE_WH'
    SCHEDULE = 'USING CRON 0 6 * * 1 UTC'
    COMMENT = 'Weekly model retraining and validation'
AS
DECLARE
    task_start TIMESTAMP_NTZ := CURRENT_TIMESTAMP();
    result STRING;
BEGIN
    INSERT INTO OPS.TASK_RUNS (task_name, execution_start, status, warehouse_used)
    VALUES ('TASK_WEEKLY_MODEL_RETRAIN', task_start, 'RUNNING', 'COMPUTE_WH');
    
    result := (CALL OPS.SP_RETRAIN_MODELS());
    
    UPDATE OPS.TASK_RUNS
    SET 
        execution_end = CURRENT_TIMESTAMP(),
        status = 'SUCCESS',
        duration_seconds = DATEDIFF(second, task_start, CURRENT_TIMESTAMP())
    WHERE task_name = 'TASK_WEEKLY_MODEL_RETRAIN'
      AND execution_start = task_start;
END;

-- Task 4: Daily prediction refresh (runs at 7 AM UTC daily)
CREATE OR REPLACE TASK OPS.TASK_DAILY_PREDICTION_REFRESH
    WAREHOUSE = 'COMPUTE_WH'
    SCHEDULE = 'USING CRON 0 7 * * * UTC'
    COMMENT = 'Daily prediction generation from latest models'
AS
DECLARE
    task_start TIMESTAMP_NTZ := CURRENT_TIMESTAMP();
    result STRING;
BEGIN
    INSERT INTO OPS.TASK_RUNS (task_name, execution_start, status, warehouse_used)
    VALUES ('TASK_DAILY_PREDICTION_REFRESH', task_start, 'RUNNING', 'COMPUTE_WH');
    
    result := (CALL OPS.SP_REFRESH_PREDICTIONS());
    
    UPDATE OPS.TASK_RUNS
    SET 
        execution_end = CURRENT_TIMESTAMP(),
        status = 'SUCCESS',
        duration_seconds = DATEDIFF(second, task_start, CURRENT_TIMESTAMP())
    WHERE task_name = 'TASK_DAILY_PREDICTION_REFRESH'
      AND execution_start = task_start;
END;

SELECT 'Tasks created (suspended by default)' AS status;

-- ============================================================================
-- PART 4: TASK MANAGEMENT COMMANDS
-- ============================================================================

-- To start tasks, run:
-- ALTER TASK OPS.TASK_DAILY_PREDICTION_REFRESH RESUME;
-- ALTER TASK OPS.TASK_WEEKLY_MODEL_RETRAIN RESUME;
-- ALTER TASK OPS.TASK_DAILY_FEATURE_REFRESH RESUME;
-- ALTER TASK OPS.TASK_DAILY_CORE_REFRESH RESUME;

-- To suspend tasks:
-- ALTER TASK OPS.TASK_DAILY_CORE_REFRESH SUSPEND;
-- ALTER TASK OPS.TASK_DAILY_FEATURE_REFRESH SUSPEND;
-- ALTER TASK OPS.TASK_WEEKLY_MODEL_RETRAIN SUSPEND;
-- ALTER TASK OPS.TASK_DAILY_PREDICTION_REFRESH SUSPEND;

-- View task history
CREATE OR REPLACE VIEW OPS.TASK_HISTORY AS
SELECT 
    task_name,
    execution_start,
    execution_end,
    status,
    duration_seconds,
    CASE 
        WHEN status = 'SUCCESS' THEN 'PASS'
        WHEN status = 'FAILED' THEN 'FAIL'
        ELSE 'PENDING'
    END AS result
FROM OPS.TASK_RUNS
ORDER BY execution_start DESC;

-- Check task status
SELECT 
    name AS task_name,
    state,
    schedule,
    warehouse,
    created_on,
    CASE 
        WHEN state = 'started' THEN 'ACTIVE'
        ELSE 'SUSPENDED'
    END AS operational_status
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name LIKE 'TASK_%'
ORDER BY created_on DESC;

-- ============================================================================
-- PART 5: MANUAL TASK EXECUTION (for testing)
-- ============================================================================

-- Test stored procedures manually
-- CALL OPS.SP_REFRESH_CORE_DATA();
-- CALL OPS.SP_REFRESH_FEATURES();
-- CALL OPS.SP_RETRAIN_MODELS();
-- CALL OPS.SP_REFRESH_PREDICTIONS();

-- View execution logs
SELECT * FROM OPS.LOAD_AUDIT ORDER BY execution_timestamp DESC LIMIT 20;
SELECT * FROM OPS.TASK_RUNS ORDER BY execution_start DESC LIMIT 20;

-- ============================================================================
-- FINAL SUMMARY
-- ============================================================================

SELECT 
    '================================================' AS summary
UNION ALL
SELECT 'PHASE 6: AUTOMATION TASKS COMPLETE'
UNION ALL
SELECT '================================================'
UNION ALL
SELECT 'Tasks Created: 4'
UNION ALL
SELECT '  - TASK_DAILY_CORE_REFRESH (1 AM UTC daily)'
UNION ALL
SELECT '  - TASK_DAILY_FEATURE_REFRESH (after CORE refresh)'
UNION ALL
SELECT '  - TASK_WEEKLY_MODEL_RETRAIN (6 AM UTC Monday)'
UNION ALL
SELECT '  - TASK_DAILY_PREDICTION_REFRESH (7 AM UTC daily)'
UNION ALL
SELECT '================================================'
UNION ALL
SELECT 'Stored Procedures: 4'
UNION ALL
SELECT 'OPS Tables: 3 (TASK_RUNS, STREAM_STATUS, LOAD_AUDIT)'
UNION ALL
SELECT '================================================'
UNION ALL
SELECT 'To activate: ALTER TASK <task_name> RESUME;'
UNION ALL
SELECT '================================================';

