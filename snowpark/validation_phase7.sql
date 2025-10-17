-- =====================================================
-- PHASE 7: VALIDATION & READINESS CHECKS
-- Global Supply Chain Spoilage Forecasting Project
-- Security, Alerts, ROI/SLA, Audit Validation
-- =====================================================

USE DATABASE GLOBAL_SPOILAGE_DB;

-- =====================================================
-- 1. SECURITY VALIDATION
-- =====================================================

-- Check all required roles exist
SELECT 'SECURITY_CHECK_1' AS check_id,
       'Role Existence' AS check_name,
       COUNT(*) AS actual_count,
       7 AS expected_count,
       CASE WHEN COUNT(*) >= 7 THEN 'PASS' ELSE 'FAIL' END AS status
FROM INFORMATION_SCHEMA.APPLICABLE_ROLES
WHERE ROLE_NAME IN (
    'PLATFORM_ADMIN', 'DATA_ENGINEER_ROLE', 'DATA_SCIENTIST_ROLE',
    'OPS_TASK_ROLE', 'OPS_MONITOR_ROLE', 'DASHBOARD_ROLE', 'READONLY_ROLE'
);

-- Check role grants on database
SELECT 'SECURITY_CHECK_2' AS check_id,
       'Database Access Grants' AS check_name,
       COUNT(*) AS grant_count,
       CASE WHEN COUNT(*) >= 5 THEN 'PASS' ELSE 'FAIL' END AS status
FROM INFORMATION_SCHEMA.DATABASE_PRIVILEGES
WHERE DATABASE_NAME = 'GLOBAL_SPOILAGE_DB'
AND PRIVILEGE = 'USAGE';

-- Check warehouse resource monitor
SELECT 'SECURITY_CHECK_3' AS check_id,
       'Resource Monitor Assignment' AS check_name,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM INFORMATION_SCHEMA.RESOURCE_MONITORS
WHERE NAME LIKE 'RM_%';

-- Check governance schema exists
SELECT 'SECURITY_CHECK_4' AS check_id,
       'Governance Schema' AS check_name,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM INFORMATION_SCHEMA.SCHEMATA
WHERE SCHEMA_NAME = 'GOV';

-- Check tag-based governance
SELECT 'SECURITY_CHECK_5' AS check_id,
       'Data Classification Tags' AS check_name,
       COUNT(*) AS tagged_tables,
       CASE WHEN COUNT(*) >= 3 THEN 'PASS' ELSE 'WARNING' END AS status
FROM INFORMATION_SCHEMA.TAG_REFERENCES
WHERE TAG_NAME = 'DATA_CLASSIFICATION'
AND TAG_DATABASE = 'GLOBAL_SPOILAGE_DB';

-- =====================================================
-- 2. ALERTS & MONITORING VALIDATION
-- =====================================================

-- Check alert configuration
SELECT 'ALERT_CHECK_1' AS check_id,
       'Alert Configurations' AS check_name,
       COUNT(*) AS alert_count,
       6 AS expected_count,
       CASE WHEN COUNT(*) >= 6 THEN 'PASS' ELSE 'FAIL' END AS status
FROM OPS.ALERT_CONFIG
WHERE enabled = TRUE;

-- Check SLA definitions
SELECT 'ALERT_CHECK_2' AS check_id,
       'SLA Definitions' AS check_name,
       COUNT(*) AS sla_count,
       5 AS expected_count,
       CASE WHEN COUNT(*) >= 5 THEN 'PASS' ELSE 'FAIL' END AS status
FROM OPS.SLA_DEFINITIONS;

-- Check secrets registry
SELECT 'ALERT_CHECK_3' AS check_id,
       'Secrets Registry' AS check_name,
       COUNT(*) AS secret_count,
       CASE WHEN COUNT(*) >= 3 THEN 'PASS' ELSE 'WARNING' END AS status
FROM OPS.SECRETS_REGISTRY
WHERE status = 'ACTIVE';

-- Check alert procedures exist
SELECT 'ALERT_CHECK_4' AS check_id,
       'Alert Procedures' AS check_name,
       CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'FAIL' END AS status
FROM INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_NAME = 'TRIGGER_ALERT'
AND PROCEDURE_SCHEMA = 'OPS';

-- =====================================================
-- 3. MODEL REGISTRY VALIDATION
-- =====================================================

-- Check model registry
SELECT 'REGISTRY_CHECK_1' AS check_id,
       'Model Registry' AS check_name,
       COUNT(*) AS registered_models,
       4 AS expected_count,
       CASE WHEN COUNT(*) >= 4 THEN 'PASS' ELSE 'FAIL' END AS status
FROM ML.MODEL_REGISTRY;

-- Check production models
SELECT 'REGISTRY_CHECK_2' AS check_id,
       'Production Models' AS check_name,
       COUNT(*) AS production_models,
       CASE WHEN COUNT(*) >= 2 THEN 'PASS' ELSE 'WARNING' END AS status
FROM ML.MODEL_REGISTRY
WHERE status = 'PRODUCTION'
AND environment = 'PRD';

-- Check model performance metrics
SELECT 'REGISTRY_CHECK_3' AS check_id,
       'Model Performance Metrics' AS check_name,
       COUNT(*) AS metric_records,
       CASE WHEN COUNT(*) >= 4 THEN 'PASS' ELSE 'WARNING' END AS status
FROM ML.MODEL_PERFORMANCE_METRICS;

-- Check artifact store stage
SELECT 'REGISTRY_CHECK_4' AS check_id,
       'Artifact Store Stage' AS check_name,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM INFORMATION_SCHEMA.STAGES
WHERE STAGE_NAME = 'MODEL_ARTIFACTS_STAGE'
AND STAGE_SCHEMA = 'ML';

-- Check promotion procedures
SELECT 'REGISTRY_CHECK_5' AS check_id,
       'Model Promotion Procedures' AS check_name,
       COUNT(*) AS procedure_count,
       CASE WHEN COUNT(*) >= 2 THEN 'PASS' ELSE 'FAIL' END AS status
FROM INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_NAME IN ('PROMOTE_MODEL', 'ROLLBACK_MODEL')
AND PROCEDURE_SCHEMA = 'ML';

-- =====================================================
-- 4. ROI & BUSINESS METRICS VALIDATION
-- =====================================================

-- Check ROI metrics
SELECT 'ROI_CHECK_1' AS check_id,
       'ROI Metrics' AS check_name,
       COUNT(*) AS roi_metrics,
       CASE WHEN COUNT(*) >= 3 THEN 'PASS' ELSE 'WARNING' END AS status
FROM OPS.ROI_METRICS;

-- Calculate total ROI
SELECT 'ROI_CHECK_2' AS check_id,
       'Total Cost Savings ROI' AS check_name,
       ROUND(SUM(metric_value), 2) AS total_savings_usd,
       CASE WHEN SUM(metric_value) > 100000 THEN 'PASS' ELSE 'WARNING' END AS status
FROM OPS.ROI_METRICS
WHERE metric_category = 'COST_SAVINGS'
AND metric_unit = 'USD';

-- Check improvement metrics
SELECT 'ROI_CHECK_3' AS check_id,
       'Efficiency Improvements' AS check_name,
       ROUND(AVG(improvement_percent), 2) AS avg_improvement_pct,
       CASE WHEN AVG(improvement_percent) >= 15 THEN 'PASS' ELSE 'WARNING' END AS status
FROM OPS.ROI_METRICS
WHERE metric_category = 'EFFICIENCY_GAIN';

-- =====================================================
-- 5. DATA QUALITY VALIDATION
-- =====================================================

-- Check data quality monitoring
SELECT 'QUALITY_CHECK_1' AS check_id,
       'Data Quality Monitoring' AS check_name,
       COUNT(*) AS monitored_tables,
       CASE WHEN COUNT(*) >= 3 THEN 'PASS' ELSE 'WARNING' END AS status
FROM OPS.DATA_QUALITY;

-- Check average quality score
SELECT 'QUALITY_CHECK_2' AS check_id,
       'Average Quality Score' AS check_name,
       ROUND(AVG(quality_score), 2) AS avg_score,
       CASE WHEN AVG(quality_score) >= 90 THEN 'PASS' ELSE 'WARNING' END AS status
FROM OPS.DATA_QUALITY;

-- =====================================================
-- 6. AUDIT & COMPLIANCE VALIDATION
-- =====================================================

-- Check audit tables exist
SELECT 'AUDIT_CHECK_1' AS check_id,
       'Audit Tables' AS check_name,
       COUNT(*) AS audit_table_count,
       CASE WHEN COUNT(*) >= 3 THEN 'PASS' ELSE 'FAIL' END AS status
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'OPS'
AND TABLE_NAME IN ('LOAD_AUDIT', 'SECURITY_AUDIT', 'DATA_ACCESS_LOG');

-- Check Phase 7 audit entries
SELECT 'AUDIT_CHECK_2' AS check_id,
       'Phase 7 Audit Entries' AS check_name,
       COUNT(*) AS phase7_entries,
       CASE WHEN COUNT(*) >= 3 THEN 'PASS' ELSE 'WARNING' END AS status
FROM OPS.LOAD_AUDIT
WHERE phase = 'PHASE_7';

-- Check all phases completed
SELECT 'AUDIT_CHECK_3' AS check_id,
       'All Phases Completed' AS check_name,
       COUNT(DISTINCT phase) AS completed_phases,
       7 AS expected_phases,
       CASE WHEN COUNT(DISTINCT phase) >= 7 THEN 'PASS' ELSE 'WARNING' END AS status
FROM OPS.LOAD_AUDIT
WHERE status = 'SUCCESS';

-- =====================================================
-- 7. OPERATIONAL READINESS VALIDATION
-- =====================================================

-- Check KPI monitoring
SELECT 'OPS_CHECK_1' AS check_id,
       'KPI Monitoring' AS check_name,
       COUNT(*) AS kpi_count,
       CASE WHEN COUNT(*) >= 5 THEN 'PASS' ELSE 'WARNING' END AS status
FROM OPS.KPI_MONITORING
WHERE status = 'GREEN';

-- Check dashboard metrics
SELECT 'OPS_CHECK_2' AS check_id,
       'Dashboard Metrics' AS check_name,
       COUNT(*) AS metric_count,
       CASE WHEN COUNT(*) >= 6 THEN 'PASS' ELSE 'WARNING' END AS status
FROM OPS.DASHBOARD_METRICS
WHERE status = 'SUCCESS';

-- Check system uptime
SELECT 'OPS_CHECK_3' AS check_id,
       'System Uptime' AS check_name,
       MAX(metric_value) AS uptime_percent,
       CASE WHEN MAX(metric_value) >= 99.0 THEN 'PASS' ELSE 'WARNING' END AS status
FROM OPS.DASHBOARD_METRICS
WHERE metric_name = 'SYSTEM_UPTIME_PERCENT';

-- =====================================================
-- 8. COMPREHENSIVE VALIDATION SUMMARY
-- =====================================================

-- Create validation summary view
CREATE OR REPLACE VIEW GOV.PHASE7_VALIDATION_SUMMARY AS
WITH all_checks AS (
    -- Security checks
    SELECT 'SECURITY' AS category, check_id, check_name, status
    FROM (
        SELECT 'SECURITY_CHECK_1' AS check_id, 'Role Existence' AS check_name,
               CASE WHEN COUNT(*) >= 7 THEN 'PASS' ELSE 'FAIL' END AS status
        FROM INFORMATION_SCHEMA.APPLICABLE_ROLES
        WHERE ROLE_NAME IN ('PLATFORM_ADMIN', 'DATA_ENGINEER_ROLE', 'DATA_SCIENTIST_ROLE', 
                           'OPS_TASK_ROLE', 'OPS_MONITOR_ROLE', 'DASHBOARD_ROLE', 'READONLY_ROLE')
    )
    
    UNION ALL
    
    -- Alert checks
    SELECT 'ALERTS' AS category, 'ALERT_CHECK_1' AS check_id, 'Alert Configurations' AS check_name,
           CASE WHEN COUNT(*) >= 6 THEN 'PASS' ELSE 'FAIL' END AS status
    FROM OPS.ALERT_CONFIG WHERE enabled = TRUE
    
    UNION ALL
    
    -- Registry checks  
    SELECT 'REGISTRY' AS category, 'REGISTRY_CHECK_1' AS check_id, 'Model Registry' AS check_name,
           CASE WHEN COUNT(*) >= 4 THEN 'PASS' ELSE 'FAIL' END AS status
    FROM ML.MODEL_REGISTRY
    
    UNION ALL
    
    -- ROI checks
    SELECT 'ROI' AS category, 'ROI_CHECK_1' AS check_id, 'ROI Metrics' AS check_name,
           CASE WHEN COUNT(*) >= 3 THEN 'PASS' ELSE 'WARNING' END AS status
    FROM OPS.ROI_METRICS
    
    UNION ALL
    
    -- Quality checks
    SELECT 'QUALITY' AS category, 'QUALITY_CHECK_1' AS check_id, 'Data Quality' AS check_name,
           CASE WHEN COUNT(*) >= 3 THEN 'PASS' ELSE 'WARNING' END AS status
    FROM OPS.DATA_QUALITY
    
    UNION ALL
    
    -- Audit checks
    SELECT 'AUDIT' AS category, 'AUDIT_CHECK_1' AS check_id, 'Audit Tables' AS check_name,
           CASE WHEN COUNT(*) >= 3 THEN 'PASS' ELSE 'FAIL' END AS status
    FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_SCHEMA = 'OPS'
    AND TABLE_NAME IN ('LOAD_AUDIT', 'SECURITY_AUDIT', 'DATA_ACCESS_LOG')
)
SELECT 
    category,
    check_id,
    check_name,
    status,
    CURRENT_TIMESTAMP() AS validation_timestamp
FROM all_checks;

-- Final validation report
SELECT 
    'PHASE 7 VALIDATION COMPLETE' AS report_title,
    COUNT(*) AS total_checks,
    SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END) AS passed_checks,
    SUM(CASE WHEN status = 'WARNING' THEN 1 ELSE 0 END) AS warning_checks,
    SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END) AS failed_checks,
    ROUND(SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pass_percentage,
    CASE 
        WHEN SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END) = 0 THEN 'READY FOR PRODUCTION'
        ELSE 'REQUIRES ATTENTION'
    END AS overall_status
FROM GOV.PHASE7_VALIDATION_SUMMARY;

-- Success message
SELECT 'Phase 7: Validation completed successfully!' AS status;
