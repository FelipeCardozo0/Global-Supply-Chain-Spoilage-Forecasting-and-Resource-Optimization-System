-- ============================================================================
-- PHASE 6 READINESS VERIFICATION SQL
-- Global Supply Chain Spoilage and Resource Allocation Forecasting
-- ============================================================================
-- Purpose: Comprehensive SQL-based readiness checks before Phase 7
-- Prerequisites: Phase 6 implementation complete
-- ============================================================================

USE DATABASE GLOBAL_SPOILAGE_DB;
USE SCHEMA OPS;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================================
-- READINESS CHECK SUMMARY TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS OPS.READINESS_CHECKS (
    check_id NUMBER AUTOINCREMENT,
    check_category STRING NOT NULL,
    check_name STRING NOT NULL,
    status STRING NOT NULL,  -- 'PASS', 'WARN', 'FAIL'
    expected_value STRING,
    actual_value STRING,
    details STRING,
    severity STRING,  -- 'CRITICAL', 'HIGH', 'MEDIUM', 'LOW'
    checked_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_readiness PRIMARY KEY (check_id)
);

TRUNCATE TABLE OPS.READINESS_CHECKS;

SELECT '============================================================' AS message
UNION ALL SELECT 'PHASE 6 READINESS VERIFICATION'
UNION ALL SELECT 'Started: ' || CURRENT_TIMESTAMP()::STRING
UNION ALL SELECT '============================================================';

-- ============================================================================
-- CATEGORY 1: TASK INFRASTRUCTURE
-- ============================================================================

SELECT 'CATEGORY 1: Task Infrastructure' AS category;

-- Check 1.1: All tasks exist
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Task Infrastructure' AS check_category,
    'Task Definitions Exist' AS check_name,
    CASE 
        WHEN COUNT(*) >= 6 THEN 'PASS'
        WHEN COUNT(*) >= 4 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    '6' AS expected_value,
    COUNT(*)::STRING AS actual_value,
    'Found ' || COUNT(*) || ' tasks (expected: CORE, FEAT, PREDICT, RETRAIN, 2x STREAM)' AS details,
    'CRITICAL' AS severity
FROM INFORMATION_SCHEMA.TASKS
WHERE task_schema = 'OPS';

-- Check 1.2: All tasks are started
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Task Infrastructure',
    'Tasks Enabled',
    CASE 
        WHEN started_count = total_count AND total_count >= 6 THEN 'PASS'
        WHEN started_count >= total_count * 0.5 THEN 'WARN'
        ELSE 'FAIL'
    END,
    'All tasks started',
    started_count || '/' || total_count || ' started',
    'Tasks in started state: ' || started_count || ' of ' || total_count,
    'CRITICAL'
FROM (
    SELECT 
        COUNT(*) AS total_count,
        SUM(CASE WHEN state = 'started' THEN 1 ELSE 0 END) AS started_count
    FROM INFORMATION_SCHEMA.TASKS
    WHERE task_schema = 'OPS'
);

-- Check 1.3: Task execution history exists
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Task Infrastructure',
    'Task Execution History',
    CASE 
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'WARN'
    END,
    '>0 executions',
    COUNT(*)::STRING,
    'Found ' || COUNT(*) || ' task execution records',
    'HIGH'
FROM OPS.TASK_RUNS;

-- Check 1.4: Recent task success rate
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Task Infrastructure',
    'Task Success Rate (7d)',
    CASE 
        WHEN success_rate >= 90 THEN 'PASS'
        WHEN success_rate >= 80 THEN 'WARN'
        ELSE 'FAIL'
    END,
    '>=90%',
    ROUND(success_rate, 2) || '%',
    'Success rate: ' || ROUND(success_rate, 2) || '% (' || successful || '/' || total || ' runs)',
    'HIGH'
FROM (
    SELECT 
        COUNT(*) AS total,
        SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) AS successful,
        (SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0)) AS success_rate
    FROM OPS.TASK_RUNS
    WHERE execution_start >= DATEADD(day, -7, CURRENT_DATE())
);

-- ============================================================================
-- CATEGORY 2: STREAM INFRASTRUCTURE
-- ============================================================================

SELECT 'CATEGORY 2: Stream Infrastructure' AS category;

-- Check 2.1: Stream definitions exist
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Stream Infrastructure',
    'Stream Definitions',
    CASE 
        WHEN COUNT(*) >= 7 THEN 'PASS'
        WHEN COUNT(*) >= 3 THEN 'WARN'
        ELSE 'FAIL'
    END,
    '7 streams',
    COUNT(*)::STRING,
    'Found ' || COUNT(*) || ' streams (RAW:4, CORE:2, FEAT:1)',
    'HIGH'
FROM INFORMATION_SCHEMA.STREAMS
WHERE table_schema = 'OPS';

-- Check 2.2: Stream offset freshness (<24h)
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Stream Infrastructure',
    'Stream Freshness',
    CASE 
        WHEN stale_count = 0 THEN 'PASS'
        WHEN stale_count <= 2 THEN 'WARN'
        ELSE 'FAIL'
    END,
    '0 stale streams',
    stale_count::STRING,
    'Streams with offset >24h old: ' || stale_count,
    'HIGH'
FROM (
    SELECT 
        COUNT(*) AS stale_count
    FROM OPS.STREAM_STATUS
    WHERE DATEDIFF(hour, last_processed, CURRENT_TIMESTAMP()) > 24
);

-- Check 2.3: Stream processing activity
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Stream Infrastructure',
    'Stream Activity',
    CASE 
        WHEN active_count >= 2 THEN 'PASS'
        WHEN active_count >= 1 THEN 'WARN'
        ELSE 'FAIL'
    END,
    '>=2 active streams',
    active_count::STRING,
    'Streams with processing activity: ' || active_count,
    'MEDIUM'
FROM (
    SELECT 
        COUNT(*) AS active_count
    FROM OPS.STREAM_STATUS
    WHERE rows_inserted + rows_updated + rows_deleted > 0
);

-- ============================================================================
-- CATEGORY 3: OPTIMIZATION & ALLOCATION
-- ============================================================================

SELECT 'CATEGORY 3: Optimization & Allocation' AS category;

-- Check 3.1: Optimization runs exist
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Optimization',
    'Optimization Execution',
    CASE 
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL'
    END,
    '>0 runs',
    COUNT(*)::STRING,
    'Found ' || COUNT(*) || ' optimization runs',
    'CRITICAL'
FROM OPS.OPTIMIZATION_LOGS;

-- Check 3.2: Latest optimization succeeded
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Optimization',
    'Latest Run Status',
    CASE 
        WHEN status = 'SUCCESS' THEN 'PASS'
        ELSE 'FAIL'
    END,
    'SUCCESS',
    status,
    'Latest optimization status: ' || status || ' (Method: ' || method || ')',
    'CRITICAL'
FROM OPS.OPTIMIZATION_LOGS
ORDER BY created_at DESC
LIMIT 1;

-- Check 3.3: Spoilage reduction achieved
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Optimization',
    'Spoilage Reduction',
    CASE 
        WHEN spoilage_reduction_pct >= 30 THEN 'PASS'
        WHEN spoilage_reduction_pct >= 15 THEN 'WARN'
        ELSE 'FAIL'
    END,
    '>=30%',
    ROUND(spoilage_reduction_pct, 2) || '%',
    'Reduction: ' || ROUND(spoilage_reduction_pct, 2) || '% ($' || 
    ROUND(total_spoilage_reduction, 0) || ')',
    'HIGH'
FROM OPS.OPTIMIZATION_LOGS
ORDER BY created_at DESC
LIMIT 1;

-- Check 3.4: ROI Guardrail (savings >= 1.5× spend)
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Optimization',
    'ROI Guardrail',
    CASE 
        WHEN roi_ratio >= 1.5 THEN 'PASS'
        WHEN roi_ratio >= 1.0 THEN 'WARN'
        ELSE 'FAIL'
    END,
    '>=1.5×',
    ROUND(roi_ratio, 2) || '×',
    'ROI: ' || ROUND(roi_ratio, 2) || '× (Savings $' || ROUND(total_spoilage_reduction, 0) || 
    ' / Spend $' || ROUND(budget_used, 0) || ')',
    'CRITICAL'
FROM (
    SELECT 
        total_spoilage_reduction,
        budget_used,
        (total_spoilage_reduction / NULLIF(budget_used, 0)) AS roi_ratio
    FROM OPS.OPTIMIZATION_LOGS
    ORDER BY created_at DESC
    LIMIT 1
);

-- Check 3.5: Budget utilization
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Optimization',
    'Budget Utilization',
    CASE 
        WHEN budget_util_pct BETWEEN 70 AND 100 THEN 'PASS'
        WHEN budget_util_pct BETWEEN 50 AND 100 THEN 'WARN'
        ELSE 'FAIL'
    END,
    '70-100%',
    ROUND(budget_util_pct, 2) || '%',
    'Budget used: ' || ROUND(budget_util_pct, 2) || '% ($' || 
    ROUND(budget_used, 0) || '/$' || ROUND(total_budget, 0) || ')',
    'MEDIUM'
FROM (
    SELECT 
        total_budget,
        budget_used,
        (budget_used / NULLIF(total_budget, 0)) * 100 AS budget_util_pct
    FROM OPS.OPTIMIZATION_LOGS
    ORDER BY created_at DESC
    LIMIT 1
);

-- Check 3.6: Allocations generated
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Optimization',
    'Allocation Records',
    CASE 
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL'
    END,
    '>0 records',
    COUNT(*)::STRING,
    'Found ' || COUNT(*) || ' allocation records',
    'CRITICAL'
FROM OPS.ALLOCATIONS;

-- Check 3.7: Allocation value consistency
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Optimization',
    'Allocation Validity',
    CASE 
        WHEN invalid_count = 0 THEN 'PASS'
        ELSE 'FAIL'
    END,
    '0 invalid',
    invalid_count::STRING,
    'Invalid allocations (outside [0,1] or negative resources): ' || invalid_count,
    'CRITICAL'
FROM (
    SELECT COUNT(*) AS invalid_count
    FROM OPS.ALLOCATIONS
    WHERE optimal_allocation < 0 OR optimal_allocation > 1 OR resource_allocated < 0
);

-- ============================================================================
-- CATEGORY 4: POLICY EVALUATION
-- ============================================================================

SELECT 'CATEGORY 4: Policy Evaluation' AS category;

-- Check 4.1: Policy evaluations exist
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Policy Evaluation',
    'Policies Evaluated',
    CASE 
        WHEN COUNT(*) >= 4 THEN 'PASS'
        WHEN COUNT(*) >= 2 THEN 'WARN'
        ELSE 'FAIL'
    END,
    '>=4 policies',
    COUNT(*)::STRING,
    'Evaluated policies: ' || COUNT(*) || ' (expected: baseline, equal, proportional, optimal, +variants)',
    'HIGH'
FROM (
    SELECT DISTINCT policy_name 
    FROM OPS.POLICY_EVALUATION
    WHERE evaluation_timestamp = (SELECT MAX(evaluation_timestamp) FROM OPS.POLICY_EVALUATION)
);

-- Check 4.2: Optimal policy is best
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Policy Evaluation',
    'Optimal Policy Best',
    CASE 
        WHEN optimal_rank = 1 THEN 'PASS'
        WHEN optimal_rank <= 2 THEN 'WARN'
        ELSE 'FAIL'
    END,
    'Rank 1',
    'Rank ' || optimal_rank::STRING,
    'Optimal policy ranked ' || optimal_rank || ' by total cost',
    'HIGH'
FROM (
    SELECT 
        RANK() OVER (ORDER BY total_cost) AS cost_rank,
        policy_name
    FROM OPS.POLICY_EVALUATION
    WHERE evaluation_timestamp = (SELECT MAX(evaluation_timestamp) FROM OPS.POLICY_EVALUATION)
)
WHERE policy_name LIKE '%Optimal%'
  AND cost_rank = (SELECT cost_rank AS optimal_rank FROM (
      SELECT 
          RANK() OVER (ORDER BY total_cost) AS cost_rank,
          policy_name
      FROM OPS.POLICY_EVALUATION
      WHERE evaluation_timestamp = (SELECT MAX(evaluation_timestamp) FROM OPS.POLICY_EVALUATION)
  ) WHERE policy_name LIKE '%Optimal%');

-- ============================================================================
-- CATEGORY 5: MONITORING & ALERTS
-- ============================================================================

SELECT 'CATEGORY 5: Monitoring & Alerts' AS category;

-- Check 5.1: Monitoring summary exists
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Monitoring',
    'Monitoring Execution',
    CASE 
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'WARN'
    END,
    '>0 records',
    COUNT(*)::STRING,
    'Found ' || COUNT(*) || ' monitoring records',
    'MEDIUM'
FROM OPS.MONITORING_SUMMARY;

-- Check 5.2: Drift detection results
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Monitoring',
    'Feature Drift',
    CASE 
        WHEN drift_count = 0 THEN 'PASS'
        WHEN drift_count <= 2 THEN 'WARN'
        ELSE 'FAIL'
    END,
    '0 features',
    drift_count::STRING,
    'Features with drift detected: ' || drift_count,
    'MEDIUM'
FROM (
    SELECT COUNT(*) AS drift_count
    FROM OPS.MONITORING_SUMMARY
    WHERE has_drift = TRUE
      AND checked_at >= DATEADD(day, -7, CURRENT_DATE())
);

-- Check 5.3: Alert infrastructure
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Monitoring',
    'Alert System',
    CASE 
        WHEN table_exists = 1 THEN 'PASS'
        ELSE 'WARN'
    END,
    'Table exists',
    CASE WHEN table_exists = 1 THEN 'Yes' ELSE 'No' END,
    'Alerts table: ' || CASE WHEN table_exists = 1 THEN 'Created' ELSE 'Not found' END,
    'LOW'
FROM (
    SELECT COUNT(*) AS table_exists
    FROM INFORMATION_SCHEMA.TABLES
    WHERE table_schema = 'OPS' AND table_name = 'ALERTS'
);

-- ============================================================================
-- CATEGORY 6: DATA COMPLETENESS
-- ============================================================================

SELECT 'CATEGORY 6: Data Completeness' AS category;

-- Check 6.1: Predictions available
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Data Completeness',
    'Predictions Generated',
    CASE 
        WHEN COUNT(*) >= 100 THEN 'PASS'
        WHEN COUNT(*) >= 10 THEN 'WARN'
        ELSE 'FAIL'
    END,
    '>=100 predictions',
    COUNT(*)::STRING,
    'Available predictions: ' || COUNT(*),
    'CRITICAL'
FROM ML.PREDICTIONS;

-- Check 6.2: Recent predictions
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Data Completeness',
    'Prediction Freshness',
    CASE 
        WHEN days_old <= 7 THEN 'PASS'
        WHEN days_old <= 30 THEN 'WARN'
        ELSE 'FAIL'
    END,
    '<=7 days',
    days_old::STRING || ' days',
    'Latest prediction date: ' || max_date::STRING || ' (' || days_old || ' days old)',
    'HIGH'
FROM (
    SELECT 
        MAX(date) AS max_date,
        DATEDIFF(day, MAX(date), CURRENT_DATE()) AS days_old
    FROM ML.PREDICTIONS
);

-- Check 6.3: Model results
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Data Completeness',
    'Models Trained',
    CASE 
        WHEN COUNT(*) >= 6 THEN 'PASS'
        WHEN COUNT(*) >= 3 THEN 'WARN'
        ELSE 'FAIL'
    END,
    '6 models',
    COUNT(*)::STRING,
    'Trained models: ' || COUNT(*) || ' (3 regression, 3 classification)',
    'CRITICAL'
FROM ML.MODEL_RESULTS;

-- Check 6.4: Feature importance
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Data Completeness',
    'Feature Importance',
    CASE 
        WHEN COUNT(DISTINCT feature_name) >= 10 THEN 'PASS'
        WHEN COUNT(DISTINCT feature_name) >= 5 THEN 'WARN'
        ELSE 'FAIL'
    END,
    '>=10 features',
    COUNT(DISTINCT feature_name)::STRING,
    'Features tracked: ' || COUNT(DISTINCT feature_name),
    'MEDIUM'
FROM ML.FEATURE_IMPORTANCE;

-- ============================================================================
-- CATEGORY 7: AUDIT & COMPLIANCE
-- ============================================================================

SELECT 'CATEGORY 7: Audit & Compliance' AS category;

-- Check 7.1: Audit trail completeness
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Audit & Compliance',
    'Audit Trail',
    CASE 
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL'
    END,
    '>0 records',
    COUNT(*)::STRING,
    'Audit records: ' || COUNT(*),
    'HIGH'
FROM OPS.LOAD_AUDIT;

-- Check 7.2: Recent activity
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
SELECT 
    'Audit & Compliance',
    'System Activity',
    CASE 
        WHEN hours_since <= 48 THEN 'PASS'
        WHEN hours_since <= 168 THEN 'WARN'
        ELSE 'FAIL'
    END,
    '<=48 hours',
    hours_since::STRING || ' hours',
    'Last activity: ' || hours_since || ' hours ago',
    'MEDIUM'
FROM (
    SELECT DATEDIFF(hour, MAX(execution_timestamp), CURRENT_TIMESTAMP()) AS hours_since
    FROM OPS.LOAD_AUDIT
);

-- ============================================================================
-- OVERALL READINESS ASSESSMENT
-- ============================================================================

SELECT 'OVERALL READINESS ASSESSMENT' AS section;

-- Overall status
INSERT INTO OPS.READINESS_CHECKS (check_category, check_name, status, expected_value, actual_value, details, severity)
WITH summary AS (
    SELECT 
        SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END) AS pass_count,
        SUM(CASE WHEN status = 'WARN' THEN 1 ELSE 0 END) AS warn_count,
        SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END) AS fail_count,
        SUM(CASE WHEN severity = 'CRITICAL' AND status != 'PASS' THEN 1 ELSE 0 END) AS critical_fails,
        COUNT(*) AS total_checks
    FROM OPS.READINESS_CHECKS
)
SELECT 
    'Overall' AS check_category,
    'PHASE_6_READINESS' AS check_name,
    CASE 
        WHEN critical_fails = 0 AND fail_count = 0 AND warn_count <= 3 THEN 'PASS'
        WHEN critical_fails = 0 AND fail_count = 0 THEN 'WARN'
        ELSE 'FAIL'
    END AS status,
    '0 critical fails, 0 fails, <=3 warns' AS expected_value,
    critical_fails || ' critical, ' || fail_count || ' fails, ' || warn_count || ' warns' AS actual_value,
    'Total checks: ' || total_checks || ' | Pass: ' || pass_count || 
    ', Warn: ' || warn_count || ', Fail: ' || fail_count AS details,
    'CRITICAL' AS severity
FROM summary;

-- ============================================================================
-- FINAL REPORT
-- ============================================================================

SELECT '============================================================' AS summary
UNION ALL SELECT 'READINESS CHECK COMPLETE'
UNION ALL SELECT '============================================================'
UNION ALL SELECT 'Pass: ' || SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END)::STRING
FROM OPS.READINESS_CHECKS
UNION ALL SELECT 'Warn: ' || SUM(CASE WHEN status = 'WARN' THEN 1 ELSE 0 END)::STRING
FROM OPS.READINESS_CHECKS
UNION ALL SELECT 'Fail: ' || SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END)::STRING
FROM OPS.READINESS_CHECKS
UNION ALL SELECT '============================================================'
UNION ALL SELECT CASE 
    WHEN (SELECT status FROM OPS.READINESS_CHECKS WHERE check_name = 'PHASE_6_READINESS') = 'PASS'
    THEN '✓ PHASE 6 READY FOR PRODUCTION'
    WHEN (SELECT status FROM OPS.READINESS_CHECKS WHERE check_name = 'PHASE_6_READINESS') = 'WARN'
    THEN '⚠ PHASE 6 READY WITH WARNINGS'
    ELSE '✗ PHASE 6 NOT READY - FIX CRITICAL ISSUES'
END
UNION ALL SELECT '============================================================';

-- Display all check results
SELECT 
    check_category,
    check_name,
    status,
    expected_value,
    actual_value,
    details,
    severity
FROM OPS.READINESS_CHECKS
ORDER BY 
    CASE severity
        WHEN 'CRITICAL' THEN 1
        WHEN 'HIGH' THEN 2
        WHEN 'MEDIUM' THEN 3
        WHEN 'LOW' THEN 4
    END,
    CASE status
        WHEN 'FAIL' THEN 1
        WHEN 'WARN' THEN 2
        WHEN 'PASS' THEN 3
    END,
    check_category,
    check_name;

-- Export readiness status for external systems
SELECT 
    CURRENT_TIMESTAMP() AS check_timestamp,
    check_name,
    status,
    details
FROM OPS.READINESS_CHECKS
WHERE check_name = 'PHASE_6_READINESS';

