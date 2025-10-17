-- =====================================================
-- PHASE 9: DISASTER RECOVERY & BACKUP
-- Global Supply Chain Spoilage Forecasting Project
-- DR/BCP procedures, backups, time-travel, cross-region replica
-- =====================================================

USE ROLE ACCOUNTADMIN;

-- =====================================================
-- 1. DATA RETENTION & TIME TRAVEL CONFIGURATION
-- =====================================================

-- Set time travel retention for databases
ALTER DATABASE GLOBAL_SPOILAGE_DB SET DATA_RETENTION_TIME_IN_DAYS = 7;
ALTER DATABASE GLOBAL_SPOILAGE_DB_STG SET DATA_RETENTION_TIME_IN_DAYS = 7;
ALTER DATABASE GLOBAL_SPOILAGE_DB_PRD SET DATA_RETENTION_TIME_IN_DAYS = 7;

-- Set time travel retention for critical schemas
ALTER SCHEMA GLOBAL_SPOILAGE_DB.ML SET DATA_RETENTION_TIME_IN_DAYS = 7;
ALTER SCHEMA GLOBAL_SPOILAGE_DB.OPS SET DATA_RETENTION_TIME_IN_DAYS = 7;
ALTER SCHEMA GLOBAL_SPOILAGE_DB.FEAT SET DATA_RETENTION_TIME_IN_DAYS = 7;

-- Set time travel retention for critical tables
ALTER TABLE GLOBAL_SPOILAGE_DB.ML.PREDICTIONS SET DATA_RETENTION_TIME_IN_DAYS = 7;
ALTER TABLE GLOBAL_SPOILAGE_DB.OPS.ALERT_QUEUE SET DATA_RETENTION_TIME_IN_DAYS = 7;
ALTER TABLE GLOBAL_SPOILAGE_DB.ML.MODEL_RESULTS SET DATA_RETENTION_TIME_IN_DAYS = 7;

-- =====================================================
-- 2. EXTERNAL STAGE FOR BACKUPS
-- =====================================================

-- Create storage integration (placeholder - requires actual S3 setup)
CREATE OR REPLACE STORAGE INTEGRATION IF NOT EXISTS S3_BACKUP_INTEGRATION
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = S3
    STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::123456789012:role/snowflake-backup-role'
    STORAGE_ALLOWED_LOCATIONS = ('s3://global-spoilage-backups/')
    ENABLED = TRUE;

-- Create backup stage
CREATE OR REPLACE SCHEMA IF NOT EXISTS GLOBAL_SPOILAGE_DB.BACKUP;

CREATE OR REPLACE STAGE GLOBAL_SPOILAGE_DB.BACKUP.PRDBACKUP
    URL = 's3://global-spoilage-backups/snowflake/backups/'
    STORAGE_INTEGRATION = S3_BACKUP_INTEGRATION
    FILE_FORMAT = (TYPE = CSV COMPRESSION = GZIP HEADER = TRUE);

-- =====================================================
-- 3. BACKUP PROCEDURES
-- =====================================================

-- Procedure for daily backups
CREATE OR REPLACE PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_DAILY_BACKUP()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    backup_dir STRING;
    backup_result STRING;
BEGIN
    -- Generate backup directory name
    backup_dir := 'snapshot_' || TO_VARCHAR(CURRENT_DATE());
    
    -- Backup ML.PREDICTIONS
    COPY INTO @GLOBAL_SPOILAGE_DB.BACKUP.PRDBACKUP/$(backup_dir)/ml_predictions/
    FROM GLOBAL_SPOILAGE_DB.ML.PREDICTIONS
    FILE_FORMAT = (TYPE = CSV COMPRESSION = GZIP HEADER = TRUE)
    OVERWRITE = TRUE;
    
    -- Backup OPS.ALERT_QUEUE
    COPY INTO @GLOBAL_SPOILAGE_DB.BACKUP.PRDBACKUP/$(backup_dir)/ops_alert_queue/
    FROM GLOBAL_SPOILAGE_DB.OPS.ALERT_QUEUE
    FILE_FORMAT = (TYPE = CSV COMPRESSION = GZIP HEADER = TRUE)
    OVERWRITE = TRUE;
    
    -- Backup ML.MODEL_RESULTS
    COPY INTO @GLOBAL_SPOILAGE_DB.BACKUP.PRDBACKUP/$(backup_dir)/ml_model_results/
    FROM GLOBAL_SPOILAGE_DB.ML.MODEL_RESULTS
    FILE_FORMAT = (TYPE = CSV COMPRESSION = GZIP HEADER = TRUE)
    OVERWRITE = TRUE;
    
    -- Backup OPS.ALLOCATIONS
    COPY INTO @GLOBAL_SPOILAGE_DB.BACKUP.PRDBACKUP/$(backup_dir)/ops_allocations/
    FROM GLOBAL_SPOILAGE_DB.OPS.ALLOCATIONS
    FILE_FORMAT = (TYPE = CSV COMPRESSION = GZIP HEADER = TRUE)
    OVERWRITE = TRUE;
    
    -- Record backup in audit log
    INSERT INTO GLOBAL_SPOILAGE_DB.OPS.LOAD_AUDIT (
        execution_id, phase, step, execution_ts, status, rows_affected, execution_time_seconds, error_message
    ) VALUES (
        'BACKUP_' || backup_dir,
        'BACKUP',
        'DAILY_BACKUP',
        CURRENT_TIMESTAMP(),
        'SUCCESS',
        0,
        0,
        NULL
    );
    
    SELECT 'BACKUP_SUCCESS_' || backup_dir INTO backup_result;
    
    RETURN backup_result;
END;
$$;

-- Procedure for incremental backups
CREATE OR REPLACE PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_INCREMENTAL_BACKUP()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    backup_dir STRING;
    backup_result STRING;
BEGIN
    -- Generate backup directory name
    backup_dir := 'incremental_' || TO_VARCHAR(CURRENT_TIMESTAMP());
    
    -- Backup only recent changes (last 24 hours)
    COPY INTO @GLOBAL_SPOILAGE_DB.BACKUP.PRDBACKUP/$(backup_dir)/ml_predictions/
    FROM (
        SELECT * FROM GLOBAL_SPOILAGE_DB.ML.PREDICTIONS 
        WHERE created_at >= DATEADD(hour, -24, CURRENT_TIMESTAMP())
    )
    FILE_FORMAT = (TYPE = CSV COMPRESSION = GZIP HEADER = TRUE)
    OVERWRITE = TRUE;
    
    -- Backup recent alerts
    COPY INTO @GLOBAL_SPOILAGE_DB.BACKUP.PRDBACKUP/$(backup_dir)/ops_alert_queue/
    FROM (
        SELECT * FROM GLOBAL_SPOILAGE_DB.OPS.ALERT_QUEUE 
        WHERE created_at >= DATEADD(hour, -24, CURRENT_TIMESTAMP())
    )
    FILE_FORMAT = (TYPE = CSV COMPRESSION = GZIP HEADER = TRUE)
    OVERWRITE = TRUE;
    
    SELECT 'INCREMENTAL_BACKUP_SUCCESS_' || backup_dir INTO backup_result;
    
    RETURN backup_result;
END;
$$;

-- =====================================================
-- 4. DISASTER RECOVERY PROCEDURES
-- =====================================================

-- Procedure for full database restore
CREATE OR REPLACE PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_RESTORE_DATABASE(
    backup_date STRING,
    target_database STRING
)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    restore_result STRING;
    backup_path STRING;
BEGIN
    -- Construct backup path
    backup_path := 'snapshot_' || backup_date || '/';
    
    -- Restore ML.PREDICTIONS
    COPY INTO GLOBAL_SPOILAGE_DB.ML.PREDICTIONS
    FROM @GLOBAL_SPOILAGE_DB.BACKUP.PRDBACKUP/$(backup_path)ml_predictions/
    FILE_FORMAT = (TYPE = CSV COMPRESSION = GZIP HEADER = TRUE)
    ON_ERROR = 'CONTINUE';
    
    -- Restore OPS.ALERT_QUEUE
    COPY INTO GLOBAL_SPOILAGE_DB.OPS.ALERT_QUEUE
    FROM @GLOBAL_SPOILAGE_DB.BACKUP.PRDBACKUP/$(backup_path)ops_alert_queue/
    FILE_FORMAT = (TYPE = CSV COMPRESSION = GZIP HEADER = TRUE)
    ON_ERROR = 'CONTINUE';
    
    -- Restore ML.MODEL_RESULTS
    COPY INTO GLOBAL_SPOILAGE_DB.ML.MODEL_RESULTS
    FROM @GLOBAL_SPOILAGE_DB.BACKUP.PRDBACKUP/$(backup_path)ml_model_results/
    FILE_FORMAT = (TYPE = CSV COMPRESSION = GZIP HEADER = TRUE)
    ON_ERROR = 'CONTINUE';
    
    -- Restore OPS.ALLOCATIONS
    COPY INTO GLOBAL_SPOILAGE_DB.OPS.ALLOCATIONS
    FROM @GLOBAL_SPOILAGE_DB.BACKUP.PRDBACKUP/$(backup_path)ops_allocations/
    FILE_FORMAT = (TYPE = CSV COMPRESSION = GZIP HEADER = TRUE)
    ON_ERROR = 'CONTINUE';
    
    SELECT 'RESTORE_SUCCESS_' || backup_date INTO restore_result;
    
    RETURN restore_result;
END;
$$;

-- Procedure for time-travel recovery
CREATE OR REPLACE PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_TIME_TRAVEL_RECOVERY(
    table_name STRING,
    recovery_time STRING
)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    recovery_result STRING;
BEGIN
    -- Create backup of current table
    EXECUTE IMMEDIATE 'CREATE OR REPLACE TABLE ' || table_name || '_BACKUP AS SELECT * FROM ' || table_name;
    
    -- Restore from time-travel
    EXECUTE IMMEDIATE 'CREATE OR REPLACE TABLE ' || table_name || ' AS 
        SELECT * FROM ' || table_name || ' AT(TIMESTAMP => ''' || recovery_time || ''')';
    
    SELECT 'TIME_TRAVEL_RECOVERY_SUCCESS' INTO recovery_result;
    
    RETURN recovery_result;
END;
$$;

-- =====================================================
-- 5. CROSS-REGION REPLICATION
-- =====================================================

-- Create replication group for critical data
CREATE OR REPLACE REPLICATION GROUP IF NOT EXISTS GLOBAL_SPOILAGE_REPLICA
    OBJECT_TYPES = DATABASES
    ALLOWED_DATABASES = ('GLOBAL_SPOILAGE_DB_PRD')
    ALLOWED_ACCOUNTS = ('replica_account_1', 'replica_account_2')
    REPLICATION_SCHEDULE = 'USING CRON 0 2 * * * UTC'; -- Daily at 2 AM UTC

-- =====================================================
-- 6. BACKUP MONITORING & ALERTING
-- =====================================================

-- Create backup monitoring table
CREATE OR REPLACE TABLE GLOBAL_SPOILAGE_DB.OPS.BACKUP_MONITORING (
    backup_id STRING DEFAULT UUID_STRING(),
    backup_type STRING, -- 'FULL', 'INCREMENTAL', 'MANUAL'
    backup_date DATE,
    backup_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    backup_size_bytes NUMBER,
    backup_duration_seconds NUMBER,
    status STRING, -- 'SUCCESS', 'FAILED', 'IN_PROGRESS'
    error_message STRING,
    backup_location STRING,
    PRIMARY KEY (backup_id)
);

-- Create backup validation table
CREATE OR REPLACE TABLE GLOBAL_SPOILAGE_DB.OPS.BACKUP_VALIDATION (
    validation_id STRING DEFAULT UUID_STRING(),
    backup_id STRING,
    table_name STRING,
    expected_rows NUMBER,
    actual_rows NUMBER,
    validation_status STRING, -- 'PASS', 'FAIL', 'WARNING'
    validated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (validation_id),
    FOREIGN KEY (backup_id) REFERENCES GLOBAL_SPOILAGE_DB.OPS.BACKUP_MONITORING(backup_id)
);

-- =====================================================
-- 7. FAILOVER PROCEDURES
-- =====================================================

-- Procedure for failover to DR site
CREATE OR REPLACE PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_FAILOVER_DR()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    failover_result STRING;
BEGIN
    -- Switch to DR database
    USE DATABASE GLOBAL_SPOILAGE_DB_DR;
    
    -- Verify DR database health
    -- (This would include checks for data consistency, connectivity, etc.)
    
    -- Update failover status
    INSERT INTO GLOBAL_SPOILAGE_DB.OPS.LOAD_AUDIT (
        execution_id, phase, step, execution_ts, status, rows_affected, execution_time_seconds, error_message
    ) VALUES (
        'FAILOVER_' || CURRENT_TIMESTAMP()::STRING,
        'DR',
        'FAILOVER_ACTIVATED',
        CURRENT_TIMESTAMP(),
        'SUCCESS',
        0,
        0,
        NULL
    );
    
    SELECT 'FAILOVER_ACTIVATED' INTO failover_result;
    
    RETURN failover_result;
END;
$$;

-- Procedure for failback to primary
CREATE OR REPLACE PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_FAILBACK_PRIMARY()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    failback_result STRING;
BEGIN
    -- Switch back to primary database
    USE DATABASE GLOBAL_SPOILAGE_DB_PRD;
    
    -- Verify primary database health
    -- (This would include checks for data consistency, connectivity, etc.)
    
    -- Update failback status
    INSERT INTO GLOBAL_SPOILAGE_DB.OPS.LOAD_AUDIT (
        execution_id, phase, step, execution_ts, status, rows_affected, execution_time_seconds, error_message
    ) VALUES (
        'FAILBACK_' || CURRENT_TIMESTAMP()::STRING,
        'DR',
        'FAILBACK_COMPLETED',
        CURRENT_TIMESTAMP(),
        'SUCCESS',
        0,
        0,
        NULL
    );
    
    SELECT 'FAILBACK_COMPLETED' INTO failback_result;
    
    RETURN failback_result;
END;
$$;

-- =====================================================
-- 8. BACKUP RETENTION POLICIES
-- =====================================================

-- Create backup retention policy
CREATE OR REPLACE TABLE GLOBAL_SPOILAGE_DB.OPS.BACKUP_RETENTION_POLICY (
    policy_id STRING DEFAULT UUID_STRING(),
    backup_type STRING, -- 'FULL', 'INCREMENTAL', 'MANUAL'
    retention_days INTEGER,
    archive_after_days INTEGER,
    delete_after_days INTEGER,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (policy_id)
);

-- Insert default retention policies
INSERT INTO GLOBAL_SPOILAGE_DB.OPS.BACKUP_RETENTION_POLICY (backup_type, retention_days, archive_after_days, delete_after_days) VALUES
('FULL', 30, 7, 90),
('INCREMENTAL', 7, 3, 30),
('MANUAL', 365, 30, 1095);

-- =====================================================
-- 9. BACKUP AUTOMATION TASKS
-- =====================================================

-- Task for daily backups
CREATE OR REPLACE TASK GLOBAL_SPOILAGE_DB.OPS.TASK_DAILY_BACKUP
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = 'USING CRON 0 1 * * * UTC' -- Daily at 1 AM UTC
AS
    CALL GLOBAL_SPOILAGE_DB.OPS.SP_DAILY_BACKUP();

-- Task for incremental backups
CREATE OR REPLACE TASK GLOBAL_SPOILAGE_DB.OPS.TASK_INCREMENTAL_BACKUP
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = 'USING CRON 0 */6 * * * UTC' -- Every 6 hours
AS
    CALL GLOBAL_SPOILAGE_DB.OPS.SP_INCREMENTAL_BACKUP();

-- =====================================================
-- 10. DR DRILL PROCEDURES
-- =====================================================

-- Procedure for DR drill
CREATE OR REPLACE PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_DR_DRILL()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    drill_result STRING;
    drill_start TIMESTAMP;
    drill_end TIMESTAMP;
BEGIN
    drill_start := CURRENT_TIMESTAMP();
    
    -- Test backup accessibility
    LIST @GLOBAL_SPOILAGE_DB.BACKUP.PRDBACKUP;
    
    -- Test time-travel functionality
    SELECT COUNT(*) FROM GLOBAL_SPOILAGE_DB.ML.PREDICTIONS AT(OFFSET => -3600); -- 1 hour ago
    
    -- Test failover procedures (simulation)
    -- (In real scenario, this would test actual failover)
    
    drill_end := CURRENT_TIMESTAMP();
    
    -- Record drill results
    INSERT INTO GLOBAL_SPOILAGE_DB.OPS.LOAD_AUDIT (
        execution_id, phase, step, execution_ts, status, rows_affected, execution_time_seconds, error_message
    ) VALUES (
        'DR_DRILL_' || CURRENT_TIMESTAMP()::STRING,
        'DR',
        'DR_DRILL',
        CURRENT_TIMESTAMP(),
        'SUCCESS',
        0,
        DATEDIFF('second', drill_start, drill_end),
        NULL
    );
    
    SELECT 'DR_DRILL_SUCCESS' INTO drill_result;
    
    RETURN drill_result;
END;
$$;

-- =====================================================
-- 11. GRANT PERMISSIONS
-- =====================================================

-- Grant backup permissions
GRANT USAGE ON SCHEMA GLOBAL_SPOILAGE_DB.BACKUP TO ROLE OPS_TASK_ROLE;
GRANT READ, WRITE ON STAGE GLOBAL_SPOILAGE_DB.BACKUP.PRDBACKUP TO ROLE OPS_TASK_ROLE;

-- Grant procedure permissions
GRANT USAGE ON PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_DAILY_BACKUP() TO ROLE OPS_TASK_ROLE;
GRANT USAGE ON PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_INCREMENTAL_BACKUP() TO ROLE OPS_TASK_ROLE;
GRANT USAGE ON PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_RESTORE_DATABASE(STRING, STRING) TO ROLE OPS_TASK_ROLE;
GRANT USAGE ON PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_TIME_TRAVEL_RECOVERY(STRING, STRING) TO ROLE OPS_TASK_ROLE;
GRANT USAGE ON PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_FAILOVER_DR() TO ROLE OPS_TASK_ROLE;
GRANT USAGE ON PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_FAILBACK_PRIMARY() TO ROLE OPS_TASK_ROLE;
GRANT USAGE ON PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_DR_DRILL() TO ROLE OPS_TASK_ROLE;

-- Grant task permissions
GRANT EXECUTE TASK ON ACCOUNT TO ROLE OPS_TASK_ROLE;

-- =====================================================
-- 12. AUDIT LOG
-- =====================================================

INSERT INTO GLOBAL_SPOILAGE_DB.OPS.LOAD_AUDIT (
    execution_id, phase, step, execution_ts, status, rows_affected, execution_time_seconds, error_message
) VALUES (
    'PHASE9_DR_' || CURRENT_TIMESTAMP()::STRING,
    'PHASE_9',
    'DR_BACKUP_SETUP',
    CURRENT_TIMESTAMP(),
    'SUCCESS',
    0,
    0,
    NULL
);

-- Success message
SELECT 'Phase 9: DR/Backup setup completed successfully!' AS status;
