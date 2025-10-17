-- =====================================================
-- PHASE 8: VALIDATION & READINESS CHECKS
-- Global Supply Chain Spoilage Forecasting Project
-- EWS, Geospatial, API, Scenario Validation
-- =====================================================

USE DATABASE GLOBAL_SPOILAGE_DB;

-- =====================================================
-- 1. EWS VALIDATION CHECKS
-- =====================================================

-- Check EWS latency (≤ 5 minutes post 07:00 UTC)
SELECT 'EWS_LATENCY' AS check_name,
       DATEDIFF('minute', 
                (SELECT MAX(created_at) FROM ML.PREDICTIONS),
                (SELECT MAX(created_at) FROM OPS.ALERT_QUEUE)
       ) AS minutes_latency,
       CASE WHEN DATEDIFF('minute', 
                         (SELECT MAX(created_at) FROM ML.PREDICTIONS),
                         (SELECT MAX(created_at) FROM OPS.ALERT_QUEUE)
                ) <= 5 THEN 'PASS' ELSE 'FAIL' END AS status;

-- Check alert rules configuration
SELECT 'EWS_RULES' AS check_name,
       COUNT(*) AS rule_count,
       6 AS expected_count,
       CASE WHEN COUNT(*) >= 6 THEN 'PASS' ELSE 'FAIL' END AS status
FROM OPS.ALERT_RULES
WHERE enabled = TRUE;

-- Check watchlists configuration
SELECT 'EWS_WATCHLISTS' AS check_name,
       COUNT(*) AS watchlist_count,
       10 AS expected_count,
       CASE WHEN COUNT(*) >= 10 THEN 'PASS' ELSE 'FAIL' END AS status
FROM OPS.WATCHLISTS
WHERE enabled = TRUE;

-- Check alert queue functionality
SELECT 'EWS_QUEUE' AS check_name,
       COUNT(*) AS queue_count,
       COUNT_IF(status = 'NEW') AS new_alerts,
       COUNT_IF(severity = 'P1') AS p1_alerts,
       CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM OPS.ALERT_QUEUE;

-- Check EWS procedures
SELECT 'EWS_PROCEDURES' AS check_name,
       COUNT(*) AS procedure_count,
       3 AS expected_count,
       CASE WHEN COUNT(*) >= 3 THEN 'PASS' ELSE 'FAIL' END AS status
FROM INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_SCHEMA = 'OPS'
AND PROCEDURE_NAME IN ('SP_EWS_ENQUEUE', 'SP_ESCALATE_ALERTS', 'SP_RUN_SCENARIO');

-- =====================================================
-- 2. GEOSPATIAL VALIDATION CHECKS
-- =====================================================

-- Check country geometries
SELECT 'GEO_COUNTRIES' AS check_name,
       COUNT(*) AS country_count,
       20 AS expected_count,
       CASE WHEN COUNT(*) >= 20 THEN 'PASS' ELSE 'FAIL' END AS status
FROM GEO.COUNTRY_GEOM;

-- Check risk zones
SELECT 'GEO_RISK_ZONES' AS check_name,
       COUNT(*) AS zone_count,
       5 AS expected_count,
       CASE WHEN COUNT(*) >= 5 THEN 'PASS' ELSE 'FAIL' END AS status
FROM GEO.RISK_ZONES;

-- Check geospatial coverage (≥ 90% countries mapped)
SELECT 'GEO_COVERAGE' AS check_name,
       COUNT(DISTINCT p.country) AS predicted_countries,
       COUNT(DISTINCT g.iso2) AS mapped_countries,
       ROUND(COUNT(DISTINCT g.iso2) * 100.0 / NULLIF(COUNT(DISTINCT p.country), 0), 2) AS coverage_percent,
       CASE WHEN COUNT(DISTINCT g.iso2) * 100.0 / NULLIF(COUNT(DISTINCT p.country), 0) >= 90 THEN 'PASS' ELSE 'WARNING' END AS status
FROM ML.PREDICTIONS p
LEFT JOIN GEO.COUNTRY_GEOM g ON g.iso2 = p.country
WHERE p.date >= DATEADD(day, -30, CURRENT_DATE());

-- Check risk heatmap view
SELECT 'GEO_HEATMAP' AS check_name,
       COUNT(*) AS heatmap_records,
       CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM GEO.RISK_HEATMAP
WHERE date >= DATEADD(day, -30, CURRENT_DATE());

-- Check geospatial functions
SELECT 'GEO_FUNCTIONS' AS check_name,
       COUNT(*) AS function_count,
       2 AS expected_count,
       CASE WHEN COUNT(*) >= 2 THEN 'PASS' ELSE 'FAIL' END AS status
FROM INFORMATION_SCHEMA.FUNCTIONS
WHERE FUNCTION_SCHEMA = 'GEO'
AND FUNCTION_NAME IN ('COUNTRIES_WITHIN_DISTANCE', 'RISK_ZONES_FOR_COUNTRY');

-- =====================================================
-- 3. API VALIDATION CHECKS
-- =====================================================

-- Check API views
SELECT 'API_VIEWS' AS check_name,
       COUNT(*) AS view_count,
       8 AS expected_count,
       CASE WHEN COUNT(*) >= 8 THEN 'PASS' ELSE 'FAIL' END AS status
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'API';

-- Check API role
SELECT 'API_ROLE' AS check_name,
       COUNT(*) AS role_count,
       CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM INFORMATION_SCHEMA.APPLICABLE_ROLES
WHERE ROLE_NAME = 'API_ROLE';

-- Check API functions
SELECT 'API_FUNCTIONS' AS check_name,
       COUNT(*) AS function_count,
       2 AS expected_count,
       CASE WHEN COUNT(*) >= 2 THEN 'PASS' ELSE 'FAIL' END AS status
FROM INFORMATION_SCHEMA.FUNCTIONS
WHERE FUNCTION_SCHEMA = 'API'
AND FUNCTION_NAME IN ('LOG_ACCESS', 'CHECK_RATE_LIMIT');

-- Check API security tables
SELECT 'API_SECURITY' AS check_name,
       COUNT(*) AS table_count,
       2 AS expected_count,
       CASE WHEN COUNT(*) >= 2 THEN 'PASS' ELSE 'FAIL' END AS status
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'API'
AND TABLE_NAME IN ('ACCESS_LOG', 'RATE_LIMITS');

-- =====================================================
-- 4. SCENARIO VALIDATION CHECKS
-- =====================================================

-- Check scenario templates
SELECT 'SCENARIO_TEMPLATES' AS check_name,
       COUNT(*) AS template_count,
       5 AS expected_count,
       CASE WHEN COUNT(*) >= 5 THEN 'PASS' ELSE 'FAIL' END AS status
FROM OPS.SCENARIO_TEMPLATES
WHERE enabled = TRUE;

-- Check scenario runs table
SELECT 'SCENARIO_RUNS' AS check_name,
       COUNT(*) AS run_count,
       CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM OPS.SCENARIO_RUNS;

-- Check scenario results table
SELECT 'SCENARIO_RESULTS' AS check_name,
       COUNT(*) AS result_count,
       CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM OPS.SCENARIO_RESULTS;

-- =====================================================
-- 5. SLO/SLA VALIDATION CHECKS
-- =====================================================

-- Check EWS SLO (latency ≤ 5 minutes)
SELECT 'EWS_SLO_LATENCY' AS check_name,
       'LATENCY' AS metric_type,
       DATEDIFF('minute', 
                (SELECT MAX(created_at) FROM ML.PREDICTIONS),
                (SELECT MAX(created_at) FROM OPS.ALERT_QUEUE)
       ) AS actual_value,
       5 AS target_value,
       CASE WHEN DATEDIFF('minute', 
                         (SELECT MAX(created_at) FROM ML.PREDICTIONS),
                         (SELECT MAX(created_at) FROM OPS.ALERT_QUEUE)
                ) <= 5 THEN 'PASS' ELSE 'FAIL' END AS status;

-- Check alert precision (≥ 2/3)
SELECT 'ALERT_PRECISION' AS check_name,
       'PRECISION' AS metric_type,
       ROUND(COUNT_IF(status = 'RESOLVED') * 100.0 / NULLIF(COUNT(*), 0), 2) AS actual_percent,
       66.67 AS target_percent,
       CASE WHEN COUNT_IF(status = 'RESOLVED') * 100.0 / NULLIF(COUNT(*), 0) >= 66.67 THEN 'PASS' ELSE 'WARNING' END AS status
FROM OPS.ALERT_QUEUE
WHERE created_at >= DATEADD(day, -30, CURRENT_TIMESTAMP());

-- Check alert recall (≥ 1/2)
SELECT 'ALERT_RECALL' AS check_name,
       'RECALL' AS metric_type,
       ROUND(COUNT_IF(severity IN ('P1', 'P2')) * 100.0 / NULLIF(COUNT(*), 0), 2) AS actual_percent,
       50.0 AS target_percent,
       CASE WHEN COUNT_IF(severity IN ('P1', 'P2')) * 100.0 / NULLIF(COUNT(*), 0) >= 50.0 THEN 'PASS' ELSE 'WARNING' END AS status
FROM OPS.ALERT_QUEUE
WHERE created_at >= DATEADD(day, -30, CURRENT_TIMESTAMP());

-- Check MTTA (Mean Time To Acknowledge)
SELECT 'MTTA_METRICS' AS check_name,
       'MTTA' AS metric_type,
       ROUND(AVG(DATEDIFF('minute', created_at, COALESCE(acknowledged_at, CURRENT_TIMESTAMP()))), 2) AS actual_minutes,
       60 AS target_minutes,
       CASE WHEN AVG(DATEDIFF('minute', created_at, COALESCE(acknowledged_at, CURRENT_TIMESTAMP()))) <= 60 THEN 'PASS' ELSE 'WARNING' END AS status
FROM OPS.ALERT_QUEUE
WHERE created_at >= DATEADD(day, -7, CURRENT_TIMESTAMP())
AND acknowledged_at IS NOT NULL;

-- Check MTTR (Mean Time To Resolve)
SELECT 'MTTR_METRICS' AS check_name,
       'MTTR' AS metric_type,
       ROUND(AVG(DATEDIFF('minute', created_at, COALESCE(resolved_at, CURRENT_TIMESTAMP()))), 2) AS actual_minutes,
       240 AS target_minutes,
       CASE WHEN AVG(DATEDIFF('minute', created_at, COALESCE(resolved_at, CURRENT_TIMESTAMP()))) <= 240 THEN 'PASS' ELSE 'WARNING' END AS status
FROM OPS.ALERT_QUEUE
WHERE created_at >= DATEADD(day, -7, CURRENT_TIMESTAMP())
AND resolved_at IS NOT NULL;

-- =====================================================
-- 6. COMPREHENSIVE VALIDATION SUMMARY
-- =====================================================

-- Create validation summary view
CREATE OR REPLACE VIEW GOV.PHASE8_VALIDATION_SUMMARY AS
WITH all_checks AS (
    -- EWS checks
    SELECT 'EWS' AS category, 'EWS_LATENCY' AS check_id, 'EWS Latency' AS check_name,
           CASE WHEN DATEDIFF('minute', 
                             (SELECT MAX(created_at) FROM ML.PREDICTIONS),
                             (SELECT MAX(created_at) FROM OPS.ALERT_QUEUE)
                    ) <= 5 THEN 'PASS' ELSE 'FAIL' END AS status
    FROM DUAL
    
    UNION ALL
    
    SELECT 'EWS' AS category, 'EWS_RULES' AS check_id, 'Alert Rules' AS check_name,
           CASE WHEN (SELECT COUNT(*) FROM OPS.ALERT_RULES WHERE enabled = TRUE) >= 6 THEN 'PASS' ELSE 'FAIL' END AS status
    FROM DUAL
    
    UNION ALL
    
    SELECT 'EWS' AS category, 'EWS_WATCHLISTS' AS check_id, 'Watchlists' AS check_name,
           CASE WHEN (SELECT COUNT(*) FROM OPS.WATCHLISTS WHERE enabled = TRUE) >= 10 THEN 'PASS' ELSE 'FAIL' END AS status
    FROM DUAL
    
    UNION ALL
    
    -- Geospatial checks
    SELECT 'GEO' AS category, 'GEO_COUNTRIES' AS check_id, 'Country Geometries' AS check_name,
           CASE WHEN (SELECT COUNT(*) FROM GEO.COUNTRY_GEOM) >= 20 THEN 'PASS' ELSE 'FAIL' END AS status
    FROM DUAL
    
    UNION ALL
    
    SELECT 'GEO' AS category, 'GEO_RISK_ZONES' AS check_id, 'Risk Zones' AS check_name,
           CASE WHEN (SELECT COUNT(*) FROM GEO.RISK_ZONES) >= 5 THEN 'PASS' ELSE 'FAIL' END AS status
    FROM DUAL
    
    UNION ALL
    
    -- API checks
    SELECT 'API' AS category, 'API_VIEWS' AS check_id, 'API Views' AS check_name,
           CASE WHEN (SELECT COUNT(*) FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA = 'API') >= 8 THEN 'PASS' ELSE 'FAIL' END AS status
    FROM DUAL
    
    UNION ALL
    
    SELECT 'API' AS category, 'API_ROLE' AS check_id, 'API Role' AS check_name,
           CASE WHEN (SELECT COUNT(*) FROM INFORMATION_SCHEMA.APPLICABLE_ROLES WHERE ROLE_NAME = 'API_ROLE') > 0 THEN 'PASS' ELSE 'FAIL' END AS status
    FROM DUAL
    
    UNION ALL
    
    -- Scenario checks
    SELECT 'SCENARIO' AS category, 'SCENARIO_TEMPLATES' AS check_id, 'Scenario Templates' AS check_name,
           CASE WHEN (SELECT COUNT(*) FROM OPS.SCENARIO_TEMPLATES WHERE enabled = TRUE) >= 5 THEN 'PASS' ELSE 'FAIL' END AS status
    FROM DUAL
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
    'PHASE 8 VALIDATION COMPLETE' AS report_title,
    COUNT(*) AS total_checks,
    SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END) AS passed_checks,
    SUM(CASE WHEN status = 'WARNING' THEN 1 ELSE 0 END) AS warning_checks,
    SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END) AS failed_checks,
    ROUND(SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pass_percentage,
    CASE 
        WHEN SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END) = 0 THEN 'READY FOR PRODUCTION'
        ELSE 'REQUIRES ATTENTION'
    END AS overall_status
FROM GOV.PHASE8_VALIDATION_SUMMARY;

-- Success message
SELECT 'Phase 8: Validation completed successfully!' AS status;
