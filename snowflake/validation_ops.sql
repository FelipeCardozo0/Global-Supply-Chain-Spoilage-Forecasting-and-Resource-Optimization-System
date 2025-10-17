-- ============================================================================
-- PHASE 6: OPERATIONS VALIDATION
-- Global Supply Chain Spoilage and Resource Allocation Forecasting
-- ============================================================================
-- Purpose: Validate automated operations, monitoring, and optimization
-- Run after: Phase 6 deployment
-- ============================================================================

USE DATABASE GLOBAL_SPOILAGE_DB;
USE SCHEMA OPS;
USE WAREHOUSE COMPUTE_WH;

-- Create validation summary table
CREATE TABLE IF NOT EXISTS OPS.OPS_VALIDATION_SUMMARY (
    validation_id NUMBER AUTOINCREMENT,
    validation_check STRING NOT NULL,
    status STRING NOT NULL,  -- 'PASS', 'WARN', 'FAIL'
    details STRING,
    threshold_value FLOAT,
    actual_value FLOAT,
    checked_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_ops_validation PRIMARY KEY (validation_id)
);

-- Clear previous validation results
TRUNCATE TABLE OPS.OPS_VALIDATION_SUMMARY;

SELECT 'OPS VALIDATION - START' AS validation_section;

-- ============================================================================
-- CHECK 1: TASK DEFINITIONS EXIST
-- ============================================================================

INSERT INTO OPS.OPS_VALIDATION_SUMMARY (validation_check, status, details, actual_value)
SELECT 
    'Tasks Defined' AS validation_check,
    CASE 
        WHEN COUNT(*) >= 4 THEN 'PASS'
        WHEN COUNT(*) >= 2 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Found ' || COUNT(*) || ' tasks (expected 6: 4 scheduled + 2 stream-triggered)' AS details,
    COUNT(*) AS actual_value
FROM INFORMATION_SCHEMA.TASKS
WHERE TASK_SCHEMA = 'OPS';

-- ============================================================================
-- CHECK 2: STREAM DEFINITIONS EXIST
-- ============================================================================

INSERT INTO OPS.OPS_VALIDATION_SUMMARY (validation_check, status, details, actual_value)
SELECT 
    'Streams Defined' AS validation_check,
    CASE 
        WHEN COUNT(*) >= 7 THEN 'PASS'
        WHEN COUNT(*) >= 3 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Found ' || COUNT(*) || ' streams (expected 7)' AS details,
    COUNT(*) AS actual_value
FROM INFORMATION_SCHEMA.STREAMS
WHERE TABLE_SCHEMA = 'OPS';

-- ============================================================================
-- CHECK 3: TASK EXECUTION HISTORY
-- ============================================================================

INSERT INTO OPS.OPS_VALIDATION_SUMMARY (validation_check, status, details, actual_value)
SELECT 
    'Tasks Executed' AS validation_check,
    CASE 
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'WARN'
    END AS status,
    'Found ' || COUNT(*) || ' task execution records' AS details,
    COUNT(*) AS actual_value
FROM OPS.TASK_RUNS;

-- ============================================================================
-- CHECK 4: TASK SUCCESS RATE
-- ============================================================================

INSERT INTO OPS.OPS_VALIDATION_SUMMARY (validation_check, status, details, threshold_value, actual_value)
SELECT 
    'Task Success Rate' AS validation_check,
    CASE 
        WHEN success_rate >= 90 THEN 'PASS'
        WHEN success_rate >= 75 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Success rate: ' || ROUND(success_rate, 2) || '% (' || successful || '/' || total || ')' AS details,
    90.0 AS threshold_value,
    success_rate AS actual_value
FROM (
    SELECT 
        COUNT(*) AS total,
        SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) AS successful,
        (SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS success_rate
    FROM OPS.TASK_RUNS
    WHERE execution_start >= DATEADD(day, -7, CURRENT_DATE())
);

-- ============================================================================
-- CHECK 5: ALLOCATION TABLES EXIST AND POPULATED
-- ============================================================================

INSERT INTO OPS.OPS_VALIDATION_SUMMARY (validation_check, status, details, actual_value)
SELECT 
    'Allocations Generated' AS validation_check,
    CASE 
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'WARN'
    END AS status,
    'Found ' || COUNT(*) || ' allocation records' AS details,
    COUNT(*) AS actual_value
FROM OPS.ALLOCATIONS;

-- ============================================================================
-- CHECK 6: OPTIMIZATION LOGS EXIST
-- ============================================================================

INSERT INTO OPS.OPS_VALIDATION_SUMMARY (validation_check, status, details, actual_value)
SELECT 
    'Optimization Runs Logged' AS validation_check,
    CASE 
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'WARN'
    END AS status,
    'Found ' || COUNT(*) || ' optimization run records' AS details,
    COUNT(*) AS actual_value
FROM OPS.OPTIMIZATION_LOGS;

-- ============================================================================
-- CHECK 7: OPTIMIZATION SUCCESS STATUS
-- ============================================================================

INSERT INTO OPS.OPS_VALIDATION_SUMMARY (validation_check, status, details)
SELECT 
    'Latest Optimization Status' AS validation_check,
    CASE 
        WHEN status = 'SUCCESS' THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Status: ' || status || ', Method: ' || method AS details
FROM OPS.OPTIMIZATION_LOGS
ORDER BY created_at DESC
LIMIT 1;

-- ============================================================================
-- CHECK 8: SPOILAGE REDUCTION ACHIEVED
-- ============================================================================

INSERT INTO OPS.OPS_VALIDATION_SUMMARY (validation_check, status, details, threshold_value, actual_value)
SELECT 
    'Spoilage Reduction Percentage' AS validation_check,
    CASE 
        WHEN spoilage_reduction_pct >= 30 THEN 'PASS'
        WHEN spoilage_reduction_pct >= 15 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Reduction: ' || ROUND(spoilage_reduction_pct, 2) || '% (expected >= 30%)' AS details,
    30.0 AS threshold_value,
    spoilage_reduction_pct AS actual_value
FROM OPS.OPTIMIZATION_LOGS
ORDER BY created_at DESC
LIMIT 1;

-- ============================================================================
-- CHECK 9: BUDGET UTILIZATION
-- ============================================================================

INSERT INTO OPS.OPS_VALIDATION_SUMMARY (validation_check, status, details, actual_value)
SELECT 
    'Budget Utilization' AS validation_check,
    CASE 
        WHEN budget_util_pct BETWEEN 70 AND 100 THEN 'PASS'
        WHEN budget_util_pct BETWEEN 50 AND 70 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Utilized: ' || ROUND(budget_util_pct, 2) || '% ($' || 
    ROUND(budget_used, 0) || '/' || ROUND(total_budget, 0) || ')' AS details,
    budget_util_pct AS actual_value
FROM (
    SELECT 
        total_budget,
        budget_used,
        (budget_used / total_budget) * 100 AS budget_util_pct
    FROM OPS.OPTIMIZATION_LOGS
    ORDER BY created_at DESC
    LIMIT 1
);

-- ============================================================================
-- CHECK 10: POLICY EVALUATION EXISTS
-- ============================================================================

INSERT INTO OPS.OPS_VALIDATION_SUMMARY (validation_check, status, details, actual_value)
SELECT 
    'Policy Evaluations Performed' AS validation_check,
    CASE 
        WHEN COUNT(*) >= 4 THEN 'PASS'
        WHEN COUNT(*) >= 2 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Found ' || COUNT(*) || ' policy evaluations (expected >= 4)' AS details,
    COUNT(*) AS actual_value
FROM (
    SELECT DISTINCT policy_name 
    FROM OPS.POLICY_EVALUATION
    WHERE evaluation_timestamp = (SELECT MAX(evaluation_timestamp) FROM OPS.POLICY_EVALUATION)
);

-- ============================================================================
-- CHECK 11: STREAM ACTIVITY
-- ============================================================================

INSERT INTO OPS.OPS_VALIDATION_SUMMARY (validation_check, status, details, actual_value)
SELECT 
    'Stream Change Tracking' AS validation_check,
    CASE 
        WHEN COUNT(*) >= 2 THEN 'PASS'
        WHEN COUNT(*) >= 1 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Found ' || COUNT(*) || ' streams with activity' AS details,
    COUNT(*) AS actual_value
FROM OPS.STREAM_STATUS
WHERE rows_inserted + rows_updated + rows_deleted > 0;

-- ============================================================================
-- CHECK 12: AUDIT TRAIL COMPLETENESS
-- ============================================================================

INSERT INTO OPS.OPS_VALIDATION_SUMMARY (validation_check, status, details, actual_value)
SELECT 
    'Audit Trail Completeness' AS validation_check,
    CASE 
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Found ' || COUNT(*) || ' audit records' AS details,
    COUNT(*) AS actual_value
FROM OPS.LOAD_AUDIT;

-- ============================================================================
-- CHECK 13: RECENT ACTIVITY
-- ============================================================================

INSERT INTO OPS.OPS_VALIDATION_SUMMARY (validation_check, status, details)
SELECT 
    'Recent System Activity' AS validation_check,
    CASE 
        WHEN hours_since_activity < 48 THEN 'PASS'
        WHEN hours_since_activity < 168 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    'Last activity: ' || hours_since_activity || ' hours ago' AS details
FROM (
    SELECT DATEDIFF(hour, MAX(execution_timestamp), CURRENT_TIMESTAMP()) AS hours_since_activity
    FROM OPS.LOAD_AUDIT
);

-- ============================================================================
-- CHECK 14: ALLOCATION CONSISTENCY
-- ============================================================================

INSERT INTO OPS.OPS_VALIDATION_SUMMARY (validation_check, status, details)
SELECT 
    'Allocation Values Valid' AS validation_check,
    CASE 
        WHEN invalid_count = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status,
    'Invalid allocations: ' || invalid_count || ' (should be 0)' AS details
FROM (
    SELECT COUNT(*) AS invalid_count
    FROM OPS.ALLOCATIONS
    WHERE optimal_allocation < 0 OR optimal_allocation > 1
       OR resource_allocated < 0
);

-- ============================================================================
-- CHECK 15: OVERALL OPS HEALTH
-- ============================================================================

INSERT INTO OPS.OPS_VALIDATION_SUMMARY (validation_check, status, details)
WITH validation_counts AS (
    SELECT 
        SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END) AS pass_count,
        SUM(CASE WHEN status = 'WARN' THEN 1 ELSE 0 END) AS warn_count,
        SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END) AS fail_count,
        COUNT(*) AS total_checks
    FROM OPS.OPS_VALIDATION_SUMMARY
)
SELECT 
    'OVERALL_OPS_STATUS' AS validation_check,
    CASE 
        WHEN fail_count = 0 AND warn_count <= 3 THEN 'PASS'
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
SELECT 'PHASE 6 OPERATIONS VALIDATION COMPLETE'
UNION ALL
SELECT '============================================================'
UNION ALL
SELECT 'Total Validation Checks: ' || COUNT(*)
FROM OPS.OPS_VALIDATION_SUMMARY
UNION ALL
SELECT 'Passed: ' || SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END)
FROM OPS.OPS_VALIDATION_SUMMARY
UNION ALL
SELECT 'Warnings: ' || SUM(CASE WHEN status = 'WARN' THEN 1 ELSE 0 END)
FROM OPS.OPS_VALIDATION_SUMMARY
UNION ALL
SELECT 'Failed: ' || SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END)
FROM OPS.OPS_VALIDATION_SUMMARY
UNION ALL
SELECT '============================================================';

-- Show all validation results
SELECT 
    validation_check,
    status,
    details,
    checked_at
FROM OPS.OPS_VALIDATION_SUMMARY
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
        WHEN status = 'PASS' THEN 'OPS SYSTEM READY FOR PRODUCTION'
        WHEN status = 'WARN' THEN 'OPS SYSTEM ACCEPTABLE - REVIEW WARNINGS'
        ELSE 'OPS SYSTEM NOT READY - FIX FAILURES'
    END AS final_status
FROM OPS.OPS_VALIDATION_SUMMARY
WHERE validation_check = 'OVERALL_OPS_STATUS';

