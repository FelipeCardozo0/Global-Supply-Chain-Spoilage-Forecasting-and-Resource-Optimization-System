-- =====================================================
-- PHASE 8: API VIEWS & SECURITY
-- Global Supply Chain Spoilage Forecasting Project
-- Hardened views for API surface with security controls
-- =====================================================

USE DATABASE GLOBAL_SPOILAGE_DB;

-- =====================================================
-- 1. CREATE API SCHEMA
-- =====================================================

CREATE SCHEMA IF NOT EXISTS API;

-- =====================================================
-- 2. PREDICTIONS API VIEW
-- =====================================================

-- Secure predictions view for API consumption
CREATE OR REPLACE VIEW API.PREDICTIONS_V AS
SELECT 
    date,
    country,
    sector,
    product,
    risk_score,
    probability,
    model_version,
    created_at,
    -- Add computed fields for API
    CASE 
        WHEN probability >= 0.80 THEN 'CRITICAL'
        WHEN probability >= 0.60 THEN 'HIGH'
        WHEN probability >= 0.40 THEN 'MEDIUM'
        ELSE 'LOW'
    END as risk_level,
    -- Add confidence intervals (simplified)
    GREATEST(0, probability - 0.05) as confidence_lower,
    LEAST(1, probability + 0.05) as confidence_upper
FROM ML.PREDICTIONS
WHERE risk_score IS NOT NULL
AND probability IS NOT NULL
AND date >= DATEADD(year, -2, CURRENT_DATE())  -- Last 2 years only
ORDER BY date DESC, risk_score DESC;

-- =====================================================
-- 3. ALERTS API VIEW
-- =====================================================

-- Secure alerts view for API consumption
CREATE OR REPLACE VIEW API.ALERTS_V AS
SELECT 
    alert_id,
    date,
    country,
    sector,
    product,
    risk_score,
    probability,
    severity,
    status,
    created_at,
    acknowledged_at,
    resolved_at,
    -- Add computed fields
    DATEDIFF('hour', created_at, COALESCE(acknowledged_at, CURRENT_TIMESTAMP())) as hours_to_acknowledge,
    DATEDIFF('hour', created_at, COALESCE(resolved_at, CURRENT_TIMESTAMP())) as hours_to_resolve,
    CASE 
        WHEN status = 'RESOLVED' THEN 'CLOSED'
        WHEN status = 'FALSE_POSITIVE' THEN 'CLOSED'
        WHEN acknowledged_at IS NOT NULL THEN 'IN_PROGRESS'
        ELSE 'OPEN'
    END as alert_status
FROM OPS.ALERT_QUEUE
WHERE created_at >= DATEADD(month, -6, CURRENT_TIMESTAMP())  -- Last 6 months
ORDER BY created_at DESC;

-- =====================================================
-- 4. INCIDENTS API VIEW
-- =====================================================

-- Secure incidents view for API consumption
CREATE OR REPLACE VIEW API.INCIDENTS_V AS
SELECT 
    incident_id,
    opened_ts,
    closed_ts,
    severity,
    title,
    description,
    affected_countries,
    affected_sectors,
    status,
    assigned_to,
    -- Add computed fields
    DATEDIFF('hour', opened_ts, COALESCE(closed_ts, CURRENT_TIMESTAMP())) as duration_hours,
    CASE 
        WHEN closed_ts IS NOT NULL THEN 'RESOLVED'
        WHEN assigned_to IS NOT NULL THEN 'IN_PROGRESS'
        ELSE 'OPEN'
    END as incident_status,
    ARRAY_SIZE(affected_countries) as country_count,
    ARRAY_SIZE(affected_sectors) as sector_count
FROM OPS.INCIDENTS
WHERE opened_ts >= DATEADD(month, -12, CURRENT_TIMESTAMP())  -- Last 12 months
ORDER BY opened_ts DESC;

-- =====================================================
-- 5. SCENARIOS API VIEW
-- =====================================================

-- Secure scenario results view for API consumption
CREATE OR REPLACE VIEW API.SCENARIOS_V AS
SELECT 
    sr.run_id,
    sr.name as scenario_name,
    sr.description,
    sr.created_at,
    sr.created_by,
    sr.horizon_months,
    sr.status,
    sr.params,
    sr.completed_at,
    -- Add computed fields
    DATEDIFF('hour', sr.started_at, COALESCE(sr.completed_at, CURRENT_TIMESTAMP())) as execution_hours,
    COUNT(sr2.result_id) as result_count,
    AVG(sr2.delta_vs_base) as avg_delta,
    MAX(sr2.delta_vs_base) as max_delta,
    MIN(sr2.delta_vs_base) as min_delta
FROM OPS.SCENARIO_RUNS sr
LEFT JOIN OPS.SCENARIO_RESULTS sr2 ON sr.run_id = sr2.run_id
WHERE sr.created_at >= DATEADD(month, -6, CURRENT_TIMESTAMP())  -- Last 6 months
GROUP BY sr.run_id, sr.name, sr.description, sr.created_at, sr.created_by, 
         sr.horizon_months, sr.status, sr.params, sr.completed_at, sr.started_at
ORDER BY sr.created_at DESC;

-- =====================================================
-- 6. SCENARIO RESULTS API VIEW
-- =====================================================

-- Secure scenario results view for API consumption
CREATE OR REPLACE VIEW API.SCENARIO_RESULTS_V AS
SELECT 
    sr.run_id,
    sr.name as scenario_name,
    sr2.date,
    sr2.country,
    sr2.sector,
    sr2.product,
    sr2.base_risk_score,
    sr2.scenario_risk_score,
    sr2.delta_vs_base,
    sr2.confidence_interval_lower,
    sr2.confidence_interval_upper,
    sr2.model_version,
    sr2.created_at,
    -- Add computed fields
    CASE 
        WHEN sr2.delta_vs_base > 0.1 THEN 'SIGNIFICANT_INCREASE'
        WHEN sr2.delta_vs_base > 0.05 THEN 'MODERATE_INCREASE'
        WHEN sr2.delta_vs_base > -0.05 THEN 'STABLE'
        WHEN sr2.delta_vs_base > -0.1 THEN 'MODERATE_DECREASE'
        ELSE 'SIGNIFICANT_DECREASE'
    END as impact_level,
    ABS(sr2.delta_vs_base) as impact_magnitude
FROM OPS.SCENARIO_RUNS sr
JOIN OPS.SCENARIO_RESULTS sr2 ON sr.run_id = sr2.run_id
WHERE sr.created_at >= DATEADD(month, -6, CURRENT_TIMESTAMP())  -- Last 6 months
ORDER BY sr.created_at DESC, sr2.date DESC, sr2.delta_vs_base DESC;

-- =====================================================
-- 7. GEOSPATIAL API VIEWS
-- =====================================================

-- Country risk heatmap for API
CREATE OR REPLACE VIEW API.COUNTRY_RISK_V AS
SELECT 
    rh.date,
    rh.country,
    rh.country_name,
    rh.iso2,
    rh.region,
    rh.subregion,
    rh.income_group,
    rh.risk_score,
    rh.probability,
    rh.risk_level,
    rh.centroid_lat,
    rh.centroid_lon,
    rh.area_km2,
    rh.population,
    rh.last_updated
FROM GEO.RISK_HEATMAP rh
WHERE rh.date >= DATEADD(month, -3, CURRENT_DATE())  -- Last 3 months
ORDER BY rh.date DESC, rh.risk_score DESC;

-- Regional risk aggregation for API
CREATE OR REPLACE VIEW API.REGIONAL_RISK_V AS
SELECT 
    rr.date,
    rr.region,
    rr.country_count,
    rr.avg_risk_score,
    rr.max_risk_score,
    rr.min_risk_score,
    rr.avg_probability,
    rr.critical_count,
    rr.high_risk_count,
    rr.medium_risk_count,
    rr.centroid_lat,
    rr.centroid_lon,
    rr.area_km2,
    -- Add computed fields
    rr.critical_count * 100.0 / NULLIF(rr.country_count, 0) as critical_percentage,
    rr.high_risk_count * 100.0 / NULLIF(rr.country_count, 0) as high_risk_percentage
FROM GEO.REGIONAL_RISK rr
WHERE rr.date >= DATEADD(month, -1, CURRENT_DATE())  -- Last month
ORDER BY rr.date DESC, rr.avg_risk_score DESC;

-- =====================================================
-- 8. DASHBOARD METRICS API VIEWS
-- =====================================================

-- System health metrics for API
CREATE OR REPLACE VIEW API.SYSTEM_HEALTH_V AS
SELECT 
    CURRENT_TIMESTAMP() as timestamp,
    'EWS_SYSTEM' as system_name,
    COUNT(DISTINCT aq.alert_id) as total_alerts,
    COUNT_IF(aq.status = 'NEW') as new_alerts,
    COUNT_IF(aq.status = 'ACKNOWLEDGED') as acknowledged_alerts,
    COUNT_IF(aq.status = 'RESOLVED') as resolved_alerts,
    COUNT_IF(aq.severity = 'P1') as p1_alerts,
    COUNT_IF(aq.severity = 'P2') as p2_alerts,
    COUNT_IF(aq.severity = 'P3') as p3_alerts,
    AVG(DATEDIFF('minute', aq.created_at, COALESCE(aq.acknowledged_at, CURRENT_TIMESTAMP()))) as avg_mtta_minutes,
    AVG(DATEDIFF('minute', aq.created_at, COALESCE(aq.resolved_at, CURRENT_TIMESTAMP()))) as avg_mttr_minutes
FROM OPS.ALERT_QUEUE aq
WHERE aq.created_at >= DATEADD(day, -7, CURRENT_TIMESTAMP());  -- Last 7 days

-- Model performance metrics for API
CREATE OR REPLACE VIEW API.MODEL_PERFORMANCE_V AS
SELECT 
    CURRENT_TIMESTAMP() as timestamp,
    'ML_MODELS' as system_name,
    COUNT(DISTINCT mr.model_id) as total_models,
    COUNT_IF(mr.status = 'PRODUCTION') as production_models,
    COUNT_IF(mr.status = 'STAGING') as staging_models,
    AVG(mpm.metric_value) as avg_accuracy,
    MAX(mpm.metric_value) as max_accuracy,
    MIN(mpm.metric_value) as min_accuracy
FROM ML.MODEL_REGISTRY mr
LEFT JOIN ML.MODEL_PERFORMANCE_METRICS mpm ON mr.model_id = mpm.model_id 
    AND mpm.metric_name = 'accuracy'
WHERE mr.created_timestamp >= DATEADD(month, -3, CURRENT_TIMESTAMP());  -- Last 3 months

-- =====================================================
-- 9. EXPLAINABILITY API VIEWS
-- =====================================================

-- Model explainability for API
CREATE OR REPLACE VIEW API.MODEL_EXPLAIN_V AS
SELECT 
    p.date,
    p.country,
    p.sector,
    p.product,
    p.risk_score,
    p.probability,
    p.model_version,
    -- Feature importance (simplified)
    CASE 
        WHEN p.fedfunds_rate > 0.05 THEN 'HIGH_INTEREST_RATE'
        WHEN p.retail_sales < 0 THEN 'DECLINING_RETAIL'
        WHEN p.treasury_10y_rate > 0.04 THEN 'HIGH_YIELD_CURVE'
        ELSE 'NORMAL_CONDITIONS'
    END as primary_driver,
    -- Risk factors
    CASE 
        WHEN p.probability >= 0.80 THEN 'CRITICAL_MULTIPLE_FACTORS'
        WHEN p.probability >= 0.60 THEN 'HIGH_ECONOMIC_PRESSURE'
        WHEN p.probability >= 0.40 THEN 'MODERATE_CONCERNS'
        ELSE 'LOW_RISK_PROFILE'
    END as risk_profile
FROM ML.PREDICTIONS p
WHERE p.date >= DATEADD(month, -1, CURRENT_DATE())  -- Last month
ORDER BY p.probability DESC;

-- =====================================================
-- 10. API SECURITY CONTROLS
-- =====================================================

-- Create API access log table
CREATE OR REPLACE TABLE API.ACCESS_LOG (
    access_id STRING DEFAULT UUID_STRING(),
    endpoint STRING,
    method STRING,
    user_id STRING,
    ip_address STRING,
    user_agent STRING,
    request_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    response_code INTEGER,
    response_time_ms INTEGER,
    rows_returned INTEGER,
    PRIMARY KEY (access_id)
);

-- Create API rate limiting table
CREATE OR REPLACE TABLE API.RATE_LIMITS (
    user_id STRING,
    endpoint STRING,
    request_count INTEGER DEFAULT 0,
    window_start TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    blocked_until TIMESTAMP,
    PRIMARY KEY (user_id, endpoint)
);

-- =====================================================
-- 11. API USAGE ANALYTICS
-- =====================================================

-- API usage analytics view
CREATE OR REPLACE VIEW API.USAGE_ANALYTICS_V AS
SELECT 
    DATE(access_timestamp) as usage_date,
    endpoint,
    COUNT(*) as request_count,
    COUNT(DISTINCT user_id) as unique_users,
    AVG(response_time_ms) as avg_response_time,
    COUNT_IF(response_code >= 400) as error_count,
    SUM(rows_returned) as total_rows_returned
FROM API.ACCESS_LOG
WHERE access_timestamp >= DATEADD(day, -30, CURRENT_TIMESTAMP())  -- Last 30 days
GROUP BY DATE(access_timestamp), endpoint
ORDER BY usage_date DESC, request_count DESC;

-- =====================================================
-- 12. API HEALTH CHECKS
-- =====================================================

-- API health check view
CREATE OR REPLACE VIEW API.HEALTH_CHECK_V AS
SELECT 
    CURRENT_TIMESTAMP() as check_timestamp,
    'API_SYSTEM' as system_name,
    COUNT(DISTINCT endpoint) as total_endpoints,
    COUNT_IF(response_code < 400) as successful_requests,
    COUNT_IF(response_code >= 400) as failed_requests,
    AVG(response_time_ms) as avg_response_time,
    MAX(response_time_ms) as max_response_time,
    COUNT(DISTINCT user_id) as active_users
FROM API.ACCESS_LOG
WHERE access_timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP());  -- Last hour

-- =====================================================
-- 13. GRANT API PERMISSIONS
-- =====================================================

-- Create API role
CREATE ROLE IF NOT EXISTS API_ROLE;

-- Grant schema access
GRANT USAGE ON SCHEMA API TO ROLE API_ROLE;

-- Grant view access
GRANT SELECT ON ALL VIEWS IN SCHEMA API TO ROLE API_ROLE;

-- Grant table access for logging
GRANT INSERT ON API.ACCESS_LOG TO ROLE API_ROLE;
GRANT SELECT, INSERT, UPDATE ON API.RATE_LIMITS TO ROLE API_ROLE;

-- Grant to existing roles
GRANT ROLE API_ROLE TO ROLE DASHBOARD_ROLE;
GRANT ROLE API_ROLE TO ROLE OPS_MONITOR_ROLE;

-- =====================================================
-- 14. CREATE API FUNCTIONS
-- =====================================================

-- Function to log API access
CREATE OR REPLACE FUNCTION API.LOG_ACCESS(
    p_endpoint STRING,
    p_method STRING,
    p_user_id STRING,
    p_ip_address STRING,
    p_user_agent STRING,
    p_response_code INTEGER,
    p_response_time_ms INTEGER,
    p_rows_returned INTEGER
)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    INSERT INTO API.ACCESS_LOG (
        endpoint, method, user_id, ip_address, user_agent,
        response_code, response_time_ms, rows_returned
    )
    VALUES (
        p_endpoint, p_method, p_user_id, p_ip_address, p_user_agent,
        p_response_code, p_response_time_ms, p_rows_returned
    );
    
    RETURN 'ACCESS_LOGGED';
END;
$$;

-- Function to check rate limits
CREATE OR REPLACE FUNCTION API.CHECK_RATE_LIMIT(
    p_user_id STRING,
    p_endpoint STRING,
    p_limit_per_hour INTEGER DEFAULT 1000
)
RETURNS BOOLEAN
LANGUAGE SQL
AS
$$
DECLARE
    v_request_count INTEGER;
    v_window_start TIMESTAMP;
BEGIN
    -- Get current request count for user/endpoint
    SELECT request_count, window_start
    INTO v_request_count, v_window_start
    FROM API.RATE_LIMITS
    WHERE user_id = p_user_id AND endpoint = p_endpoint;
    
    -- Reset if window has passed
    IF v_window_start < DATEADD(hour, -1, CURRENT_TIMESTAMP()) THEN
        UPDATE API.RATE_LIMITS
        SET request_count = 1, window_start = CURRENT_TIMESTAMP()
        WHERE user_id = p_user_id AND endpoint = p_endpoint;
        
        RETURN TRUE;
    END IF;
    
    -- Check if limit exceeded
    IF v_request_count >= p_limit_per_hour THEN
        RETURN FALSE;
    END IF;
    
    -- Increment counter
    UPDATE API.RATE_LIMITS
    SET request_count = request_count + 1
    WHERE user_id = p_user_id AND endpoint = p_endpoint;
    
    RETURN TRUE;
END;
$$;

-- =====================================================
-- 15. AUDIT LOG
-- =====================================================

INSERT INTO OPS.LOAD_AUDIT (
    execution_id, phase, step, execution_ts, status, rows_affected, execution_time_seconds, error_message
) VALUES (
    'PHASE8_API_' || CURRENT_TIMESTAMP()::STRING,
    'PHASE_8',
    'API_VIEWS_SETUP',
    CURRENT_TIMESTAMP(),
    'SUCCESS',
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA = 'API'),
    0,
    NULL
);

-- Success message
SELECT 'Phase 8: API views setup completed successfully!' AS status;
