-- ============================================================================
-- PHASE 6: OPERATIONS & AUTOMATION - STREAM DEFINITIONS
-- Global Supply Chain Spoilage and Resource Allocation Forecasting
-- ============================================================================
-- Purpose: Define Snowflake Streams for incremental change tracking
-- Prerequisites: Phases 1-5 complete, 06_ops_tasks.sql executed
-- ============================================================================

USE DATABASE GLOBAL_SPOILAGE_DB;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================================
-- PART 1: CREATE STREAMS ON RAW TABLES
-- ============================================================================

-- Stream on FEDFUNDS_MONTHLY (detects new economic data)
CREATE OR REPLACE STREAM OPS.STREAM_RAW_FEDFUNDS
    ON TABLE RAW.FEDFUNDS_MONTHLY
    COMMENT = 'Captures inserts/updates to federal funds rate data';

-- Stream on RSXFS (retail sales)
CREATE OR REPLACE STREAM OPS.STREAM_RAW_RETAIL
    ON TABLE RAW.RSXFS
    COMMENT = 'Captures inserts/updates to retail sales data';

-- Stream on RECESSION_PERIODS
CREATE OR REPLACE STREAM OPS.STREAM_RAW_RECESSION
    ON TABLE RAW.RECESSION_PERIODS
    COMMENT = 'Captures inserts/updates to recession indicator data';

-- Stream on SP500_INDEX
CREATE OR REPLACE STREAM OPS.STREAM_RAW_SP500
    ON TABLE RAW.SP500_INDEX
    COMMENT = 'Captures inserts/updates to S&P 500 data';

SELECT 'RAW streams created' AS status;

-- ============================================================================
-- PART 2: CREATE STREAMS ON CORE TABLES
-- ============================================================================

-- Stream on ECONOMIC_MASTER (detects changes in master table)
CREATE OR REPLACE STREAM OPS.STREAM_CORE_ECONOMIC
    ON TABLE CORE.ECONOMIC_MASTER
    COMMENT = 'Captures inserts/updates to economic master table';

-- Stream on RETAIL_SALES
CREATE OR REPLACE STREAM OPS.STREAM_CORE_RETAIL
    ON TABLE CORE.RETAIL_SALES
    COMMENT = 'Captures inserts/updates to retail sales';

SELECT 'CORE streams created' AS status;

-- ============================================================================
-- PART 3: CREATE STREAMS ON FEAT TABLES
-- ============================================================================

-- Stream on MASTER_FEATURES (detects feature updates)
CREATE OR REPLACE STREAM OPS.STREAM_FEAT_MASTER
    ON TABLE FEAT.MASTER_FEATURES
    COMMENT = 'Captures inserts/updates to master features table';

SELECT 'FEAT streams created' AS status;

-- ============================================================================
-- PART 4: INCREMENTAL PROCESSING PROCEDURES
-- ============================================================================

-- Procedure: Process incremental FEDFUNDS changes
CREATE OR REPLACE PROCEDURE OPS.SP_PROCESS_FEDFUNDS_STREAM()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    rows_processed NUMBER := 0;
    start_time TIMESTAMP_NTZ := CURRENT_TIMESTAMP();
BEGIN
    -- Check if stream has data
    IF (SELECT COUNT(*) FROM OPS.STREAM_RAW_FEDFUNDS) > 0 THEN
        
        -- Merge stream data into CORE
        MERGE INTO CORE.FEDFUNDS tgt
        USING (
            SELECT 
                TO_DATE(DATE) AS date,
                VALUE AS rate,
                CURRENT_TIMESTAMP() AS load_timestamp,
                METADATA$ACTION AS action,
                METADATA$ISUPDATE AS is_update
            FROM OPS.STREAM_RAW_FEDFUNDS
        ) src
        ON tgt.date = src.date
        WHEN MATCHED AND src.action = 'INSERT' AND src.is_update = TRUE THEN 
            UPDATE SET 
                tgt.rate = src.rate,
                tgt.load_timestamp = src.load_timestamp
        WHEN NOT MATCHED AND src.action = 'INSERT' THEN 
            INSERT (date, rate, load_timestamp)
            VALUES (src.date, src.rate, src.load_timestamp);
        
        rows_processed := SQLROWCOUNT;
        
        -- Update stream status
        MERGE INTO OPS.STREAM_STATUS tgt
        USING (
            SELECT 
                'STREAM_RAW_FEDFUNDS' AS stream_name,
                'RAW.FEDFUNDS_MONTHLY' AS source_table,
                rows_processed AS rows_inserted,
                CURRENT_TIMESTAMP() AS last_processed
        ) src
        ON tgt.stream_name = src.stream_name
        WHEN MATCHED THEN UPDATE SET
            tgt.rows_inserted = tgt.rows_inserted + src.rows_inserted,
            tgt.last_processed = src.last_processed
        WHEN NOT MATCHED THEN INSERT (stream_name, source_table, rows_inserted, last_processed)
            VALUES (src.stream_name, src.source_table, src.rows_inserted, src.last_processed);
        
        -- Log to audit
        INSERT INTO OPS.LOAD_AUDIT (phase, component, execution_timestamp, runtime_seconds, rows_processed, status, details)
        VALUES (
            'Phase 6',
            'SP_PROCESS_FEDFUNDS_STREAM',
            start_time,
            DATEDIFF(second, start_time, CURRENT_TIMESTAMP()),
            rows_processed,
            'SUCCESS',
            'Processed incremental FEDFUNDS changes via stream'
        );
        
        RETURN 'SUCCESS: Processed ' || rows_processed || ' rows from stream';
    ELSE
        RETURN 'NO_DATA: Stream is empty';
    END IF;
END;
$$;

-- Procedure: Process incremental RETAIL changes
CREATE OR REPLACE PROCEDURE OPS.SP_PROCESS_RETAIL_STREAM()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    rows_processed NUMBER := 0;
BEGIN
    IF (SELECT COUNT(*) FROM OPS.STREAM_RAW_RETAIL) > 0 THEN
        
        MERGE INTO CORE.RETAIL_SALES tgt
        USING (
            SELECT 
                TO_DATE(DATE) AS date,
                RETAIL_SALES_INDEX AS sales_index,
                CURRENT_TIMESTAMP() AS load_timestamp
            FROM OPS.STREAM_RAW_RETAIL
            WHERE METADATA$ACTION = 'INSERT'
        ) src
        ON tgt.date = src.date
        WHEN MATCHED THEN UPDATE SET 
            tgt.sales_index = src.sales_index,
            tgt.load_timestamp = src.load_timestamp
        WHEN NOT MATCHED THEN INSERT (date, sales_index, load_timestamp)
            VALUES (src.date, src.sales_index, src.load_timestamp);
        
        rows_processed := SQLROWCOUNT;
        
        MERGE INTO OPS.STREAM_STATUS tgt
        USING (SELECT 'STREAM_RAW_RETAIL' AS stream_name, 'RAW.RSXFS' AS source_table) src
        ON tgt.stream_name = src.stream_name
        WHEN MATCHED THEN UPDATE SET
            tgt.rows_inserted = tgt.rows_inserted + rows_processed,
            tgt.last_processed = CURRENT_TIMESTAMP()
        WHEN NOT MATCHED THEN INSERT (stream_name, source_table, rows_inserted, last_processed)
            VALUES (src.stream_name, src.source_table, rows_processed, CURRENT_TIMESTAMP());
        
        RETURN 'SUCCESS: Processed ' || rows_processed || ' rows from stream';
    ELSE
        RETURN 'NO_DATA: Stream is empty';
    END IF;
END;
$$;

SELECT 'Stream processing procedures created' AS status;

-- ============================================================================
-- PART 5: STREAM-TRIGGERED TASKS
-- ============================================================================

-- Task: Process FEDFUNDS stream when data available
CREATE OR REPLACE TASK OPS.TASK_STREAM_FEDFUNDS
    WAREHOUSE = 'COMPUTE_WH'
    SCHEDULE = '5 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('OPS.STREAM_RAW_FEDFUNDS')
    COMMENT = 'Processes FEDFUNDS stream when new data detected'
AS
DECLARE
    result STRING;
BEGIN
    result := (CALL OPS.SP_PROCESS_FEDFUNDS_STREAM());
    
    INSERT INTO OPS.TASK_RUNS (task_name, execution_start, execution_end, status, warehouse_used)
    VALUES (
        'TASK_STREAM_FEDFUNDS',
        CURRENT_TIMESTAMP(),
        CURRENT_TIMESTAMP(),
        CASE WHEN result LIKE 'SUCCESS%' THEN 'SUCCESS' ELSE 'NO_DATA' END,
        'COMPUTE_WH'
    );
END;

-- Task: Process RETAIL stream when data available
CREATE OR REPLACE TASK OPS.TASK_STREAM_RETAIL
    WAREHOUSE = 'COMPUTE_WH'
    SCHEDULE = '5 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('OPS.STREAM_RAW_RETAIL')
    COMMENT = 'Processes retail stream when new data detected'
AS
DECLARE
    result STRING;
BEGIN
    result := (CALL OPS.SP_PROCESS_RETAIL_STREAM());
    
    INSERT INTO OPS.TASK_RUNS (task_name, execution_start, execution_end, status, warehouse_used)
    VALUES (
        'TASK_STREAM_RETAIL',
        CURRENT_TIMESTAMP(),
        CURRENT_TIMESTAMP(),
        CASE WHEN result LIKE 'SUCCESS%' THEN 'SUCCESS' ELSE 'NO_DATA' END,
        'COMPUTE_WH'
    );
END;

SELECT 'Stream-triggered tasks created (suspended by default)' AS status;

-- ============================================================================
-- PART 6: STREAM MONITORING VIEWS
-- ============================================================================

-- View: Stream activity summary
CREATE OR REPLACE VIEW OPS.STREAM_ACTIVITY AS
SELECT 
    stream_name,
    source_table,
    rows_inserted + rows_updated + rows_deleted AS total_changes,
    rows_inserted,
    rows_updated,
    rows_deleted,
    last_processed,
    DATEDIFF(hour, last_processed, CURRENT_TIMESTAMP()) AS hours_since_last_process
FROM OPS.STREAM_STATUS
ORDER BY last_processed DESC;

-- View: Check which streams have pending data
CREATE OR REPLACE VIEW OPS.STREAM_DATA_PENDING AS
SELECT 
    'STREAM_RAW_FEDFUNDS' AS stream_name,
    SYSTEM$STREAM_HAS_DATA('OPS.STREAM_RAW_FEDFUNDS') AS has_data,
    (SELECT COUNT(*) FROM OPS.STREAM_RAW_FEDFUNDS) AS pending_rows
UNION ALL
SELECT 
    'STREAM_RAW_RETAIL',
    SYSTEM$STREAM_HAS_DATA('OPS.STREAM_RAW_RETAIL'),
    (SELECT COUNT(*) FROM OPS.STREAM_RAW_RETAIL)
UNION ALL
SELECT 
    'STREAM_RAW_RECESSION',
    SYSTEM$STREAM_HAS_DATA('OPS.STREAM_RAW_RECESSION'),
    (SELECT COUNT(*) FROM OPS.STREAM_RAW_RECESSION)
UNION ALL
SELECT 
    'STREAM_RAW_SP500',
    SYSTEM$STREAM_HAS_DATA('OPS.STREAM_RAW_SP500'),
    (SELECT COUNT(*) FROM OPS.STREAM_RAW_SP500)
UNION ALL
SELECT 
    'STREAM_CORE_ECONOMIC',
    SYSTEM$STREAM_HAS_DATA('OPS.STREAM_CORE_ECONOMIC'),
    (SELECT COUNT(*) FROM OPS.STREAM_CORE_ECONOMIC)
UNION ALL
SELECT 
    'STREAM_FEAT_MASTER',
    SYSTEM$STREAM_HAS_DATA('OPS.STREAM_FEAT_MASTER'),
    (SELECT COUNT(*) FROM OPS.STREAM_FEAT_MASTER);

SELECT 'Stream monitoring views created' AS status;

-- ============================================================================
-- PART 7: STREAM MANAGEMENT COMMANDS
-- ============================================================================

-- To start stream-triggered tasks:
-- ALTER TASK OPS.TASK_STREAM_FEDFUNDS RESUME;
-- ALTER TASK OPS.TASK_STREAM_RETAIL RESUME;

-- To suspend stream-triggered tasks:
-- ALTER TASK OPS.TASK_STREAM_FEDFUNDS SUSPEND;
-- ALTER TASK OPS.TASK_STREAM_RETAIL SUSPEND;

-- Check stream offsets and metadata
SELECT 
    'STREAM_RAW_FEDFUNDS' AS stream_name,
    (SELECT COUNT(*) FROM OPS.STREAM_RAW_FEDFUNDS) AS rows_in_stream,
    SYSTEM$STREAM_HAS_DATA('OPS.STREAM_RAW_FEDFUNDS') AS has_data;

-- View stream contents (for debugging)
-- SELECT * FROM OPS.STREAM_RAW_FEDFUNDS LIMIT 10;
-- SELECT * FROM OPS.STREAM_RAW_RETAIL LIMIT 10;

-- ============================================================================
-- PART 8: STREAM RESET (USE WITH CAUTION)
-- ============================================================================

-- If you need to reset a stream (recreate to clear offset):
-- DROP STREAM IF EXISTS OPS.STREAM_RAW_FEDFUNDS;
-- CREATE STREAM OPS.STREAM_RAW_FEDFUNDS ON TABLE RAW.FEDFUNDS_MONTHLY;

-- ============================================================================
-- PART 9: TESTING STREAMS
-- ============================================================================

-- Test: Insert test data to trigger stream
/*
-- Insert test row into RAW table
INSERT INTO RAW.FEDFUNDS_MONTHLY (DATE, VALUE)
VALUES ('2025-01-01', 5.25);

-- Check stream detects change
SELECT COUNT(*) AS pending_changes FROM OPS.STREAM_RAW_FEDFUNDS;

-- Process stream manually
CALL OPS.SP_PROCESS_FEDFUNDS_STREAM();

-- Verify stream is now empty
SELECT COUNT(*) AS pending_changes FROM OPS.STREAM_RAW_FEDFUNDS;

-- Check CORE table updated
SELECT * FROM CORE.FEDFUNDS WHERE date = '2025-01-01';
*/

-- ============================================================================
-- FINAL SUMMARY
-- ============================================================================

SELECT 
    '================================================' AS summary
UNION ALL
SELECT 'PHASE 6: STREAM DEFINITIONS COMPLETE'
UNION ALL
SELECT '================================================'
UNION ALL
SELECT 'Streams Created: 7'
UNION ALL
SELECT '  RAW Schema: 4 streams'
UNION ALL
SELECT '  CORE Schema: 2 streams'
UNION ALL
SELECT '  FEAT Schema: 1 stream'
UNION ALL
SELECT '================================================'
UNION ALL
SELECT 'Stream-Triggered Tasks: 2'
UNION ALL
SELECT '  - TASK_STREAM_FEDFUNDS (5 min interval)'
UNION ALL
SELECT '  - TASK_STREAM_RETAIL (5 min interval)'
UNION ALL
SELECT '================================================'
UNION ALL
SELECT 'Stream Processing Procedures: 2'
UNION ALL
SELECT 'Monitoring Views: 2'
UNION ALL
SELECT '================================================'
UNION ALL
SELECT 'To activate: ALTER TASK <task_name> RESUME;'
UNION ALL
SELECT 'Check status: SELECT * FROM OPS.STREAM_DATA_PENDING;'
UNION ALL
SELECT '================================================';

-- Display current stream status
SELECT * FROM OPS.STREAM_DATA_PENDING;

