-- =====================================================
-- PHASE 8: GLOBAL EARLY WARNING SYSTEM (EWS)
-- Global Supply Chain Spoilage Forecasting Project
-- EWS Tables, Rules, Queues, Alerts, and Automation
-- =====================================================

USE DATABASE GLOBAL_SPOILAGE_DB;

-- =====================================================
-- 1. EWS CORE TABLES
-- =====================================================

-- Alert rules configuration
CREATE OR REPLACE TABLE OPS.ALERT_RULES (
    rule_id STRING DEFAULT UUID_STRING(),
    name STRING NOT NULL,
    severity STRING,  -- 'P1', 'P2', 'P3'
    predicate_sql STRING,  -- SQL condition applied to ML.PREDICTIONS
    threshold FLOAT,
    cool_down_minutes INTEGER DEFAULT 60,
    owner STRING DEFAULT CURRENT_ROLE(),
    enabled BOOLEAN DEFAULT TRUE,
    escalation_policy STRING,  -- 'PAGER', 'SLACK', 'EMAIL'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (rule_id)
);

-- Watchlists for monitoring specific entities
CREATE OR REPLACE TABLE OPS.WATCHLISTS (
    watch_id STRING DEFAULT UUID_STRING(),
    scope STRING,  -- 'COUNTRY', 'SECTOR', 'PRODUCT', 'REGION'
    key STRING,  -- ISO2 code, sector name, product code, region name
    name STRING,  -- Human-readable name
    notes STRING,
    priority STRING DEFAULT 'MEDIUM',  -- 'HIGH', 'MEDIUM', 'LOW'
    enabled BOOLEAN DEFAULT TRUE,
    created_by STRING DEFAULT CURRENT_ROLE(),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (watch_id)
);

-- Alert queue for processing and routing
CREATE OR REPLACE TABLE OPS.ALERT_QUEUE (
    alert_id STRING DEFAULT UUID_STRING(),
    rule_id STRING,
    event_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    date DATE,
    country STRING,
    sector STRING,
    product STRING,
    risk_score FLOAT,
    probability FLOAT,
    severity STRING,  -- 'P1', 'P2', 'P3'
    status STRING DEFAULT 'NEW',  -- 'NEW', 'ACKNOWLEDGED', 'INVESTIGATING', 'RESOLVED', 'FALSE_POSITIVE'
    dedup_key STRING,  -- For deduplication
    routed_to STRING,  -- 'PAGER', 'SLACK', 'EMAIL', 'DASHBOARD'
    acknowledged_by STRING,
    acknowledged_at TIMESTAMP,
    resolved_by STRING,
    resolved_at TIMESTAMP,
    resolution_notes STRING,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (alert_id)
);

-- Incidents for tracking major events
CREATE OR REPLACE TABLE OPS.INCIDENTS (
    incident_id STRING DEFAULT UUID_STRING(),
    opened_ts TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    closed_ts TIMESTAMP,
    severity STRING,  -- 'P1', 'P2', 'P3'
    title STRING NOT NULL,
    description STRING,
    affected_countries ARRAY,
    affected_sectors ARRAY,
    mtta_seconds NUMBER,  -- Mean Time To Acknowledge
    mttr_seconds NUMBER,  -- Mean Time To Resolve
    status STRING DEFAULT 'OPEN',  -- 'OPEN', 'INVESTIGATING', 'RESOLVED', 'CLOSED'
    assigned_to STRING,
    created_by STRING DEFAULT CURRENT_ROLE(),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (incident_id)
);

-- Alert escalation history
CREATE OR REPLACE TABLE OPS.ALERT_ESCALATIONS (
    escalation_id STRING DEFAULT UUID_STRING(),
    alert_id STRING,
    escalation_level INTEGER,  -- 1, 2, 3
    escalated_to STRING,
    escalation_reason STRING,
    escalated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    acknowledged_at TIMESTAMP,
    PRIMARY KEY (escalation_id),
    FOREIGN KEY (alert_id) REFERENCES OPS.ALERT_QUEUE(alert_id)
);

-- =====================================================
-- 2. SCENARIO STRESS TESTING TABLES
-- =====================================================

-- Scenario run definitions
CREATE OR REPLACE TABLE OPS.SCENARIO_RUNS (
    run_id STRING DEFAULT UUID_STRING(),
    name STRING NOT NULL,
    description STRING,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    created_by STRING DEFAULT CURRENT_ROLE(),
    horizon_months INTEGER DEFAULT 12,
    status STRING DEFAULT 'RUNNING',  -- 'RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED'
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    completed_at TIMESTAMP,
    notes STRING,
    params VARIANT,  -- JSON parameters for the scenario
    base_model_version STRING,
    PRIMARY KEY (run_id)
);

-- Scenario results
CREATE OR REPLACE TABLE OPS.SCENARIO_RESULTS (
    result_id STRING DEFAULT UUID_STRING(),
    run_id STRING,
    date DATE,
    country STRING,
    sector STRING,
    product STRING,
    base_risk_score FLOAT,
    scenario_risk_score FLOAT,
    delta_vs_base FLOAT,
    confidence_interval_lower FLOAT,
    confidence_interval_upper FLOAT,
    model_version STRING,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (result_id),
    FOREIGN KEY (run_id) REFERENCES OPS.SCENARIO_RUNS(run_id)
);

-- Scenario templates for common stress tests
CREATE OR REPLACE TABLE OPS.SCENARIO_TEMPLATES (
    template_id STRING DEFAULT UUID_STRING(),
    name STRING NOT NULL,
    description STRING,
    category STRING,  -- 'ECONOMIC', 'CLIMATE', 'POLICY', 'DEMAND', 'SUPPLY'
    params_template VARIANT,  -- JSON template for parameters
    horizon_months INTEGER DEFAULT 12,
    enabled BOOLEAN DEFAULT TRUE,
    created_by STRING DEFAULT CURRENT_ROLE(),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (template_id)
);

-- =====================================================
-- 3. EWS HELPER VIEWS
-- =====================================================

-- View combining predictions with watchlists
CREATE OR REPLACE VIEW OPS.PREDICTIONS_WATCHED AS
SELECT 
    p.*,
    w.scope,
    w.key as watch_key,
    w.name as watch_name,
    w.priority as watch_priority,
    CASE WHEN w.watch_id IS NOT NULL THEN TRUE ELSE FALSE END as is_watched
FROM ML.PREDICTIONS p
LEFT JOIN OPS.WATCHLISTS w ON (
    w.enabled = TRUE AND
    (
        (w.scope = 'COUNTRY' AND w.key = p.country) OR
        (w.scope = 'SECTOR' AND w.key = p.sector) OR
        (w.scope = 'PRODUCT' AND w.key = p.product)
    )
);

-- Alert candidates for EWS processing
CREATE OR REPLACE TABLE OPS.ALERT_CANDIDATES AS
SELECT
    HASH(TO_VARCHAR(date) || country || TO_VARCHAR(risk_score) || TO_VARCHAR(probability)) AS dedup_key,
    date,
    country,
    sector,
    product,
    risk_score,
    probability,
    model_version,
    CASE 
        WHEN probability >= 0.80 THEN 'P1'
        WHEN probability >= 0.60 THEN 'P2'
        WHEN probability >= 0.40 THEN 'P3'
        ELSE 'P4'
    END AS severity,
    is_watched,
    watch_priority,
    CURRENT_TIMESTAMP() as candidate_ts
FROM OPS.PREDICTIONS_WATCHED
WHERE probability >= 0.40;  -- Only consider alerts above 40% probability

-- =====================================================
-- 4. EWS RULES CONFIGURATION
-- =====================================================

-- Insert default EWS rules
INSERT INTO OPS.ALERT_RULES (name, severity, predicate_sql, threshold, cool_down_minutes, escalation_policy) VALUES
('HIGH_RISK_IMMEDIATE', 'P1', 'probability >= 0.80 AND date <= DATEADD(day, 7, CURRENT_DATE()) AND is_watched = TRUE', 0.80, 30, 'PAGER'),
('HIGH_RISK_WEEKLY', 'P1', 'probability >= 0.75 AND date BETWEEN CURRENT_DATE() AND DATEADD(day, 7, CURRENT_DATE()) AND is_watched = TRUE', 0.75, 60, 'PAGER'),
('MEDIUM_RISK_MONTHLY', 'P2', 'probability >= 0.60 AND date BETWEEN CURRENT_DATE() AND DATEADD(month, 1, CURRENT_DATE()) AND is_watched = TRUE', 0.60, 120, 'SLACK'),
('LOW_RISK_QUARTERLY', 'P3', 'probability >= 0.40 AND date BETWEEN CURRENT_DATE() AND DATEADD(month, 3, CURRENT_DATE()) AND is_watched = TRUE', 0.40, 240, 'EMAIL'),
('CRITICAL_COUNTRY_RISK', 'P1', 'probability >= 0.70 AND country IN (''US'', ''CN'', ''DE'', ''JP'', ''GB'') AND date <= DATEADD(day, 14, CURRENT_DATE())', 0.70, 15, 'PAGER'),
('SUPPLY_CHAIN_DISRUPTION', 'P2', 'probability >= 0.65 AND sector IN (''MANUFACTURING'', ''LOGISTICS'', ''AGRICULTURE'') AND date <= DATEADD(day, 30, CURRENT_DATE())', 0.65, 90, 'SLACK');

-- =====================================================
-- 5. WATCHLISTS INITIALIZATION
-- =====================================================

-- Insert default watchlists
INSERT INTO OPS.WATCHLISTS (scope, key, name, priority, notes) VALUES
-- Critical countries
('COUNTRY', 'US', 'United States', 'HIGH', 'Largest economy, critical supply chain hub'),
('COUNTRY', 'CN', 'China', 'HIGH', 'Manufacturing powerhouse, supply chain dependency'),
('COUNTRY', 'DE', 'Germany', 'HIGH', 'European economic leader, manufacturing hub'),
('COUNTRY', 'JP', 'Japan', 'HIGH', 'Technology and automotive leader'),
('COUNTRY', 'GB', 'United Kingdom', 'MEDIUM', 'Financial services and logistics hub'),

-- Critical sectors
('SECTOR', 'MANUFACTURING', 'Manufacturing', 'HIGH', 'Core industrial sector'),
('SECTOR', 'AGRICULTURE', 'Agriculture', 'HIGH', 'Food security and supply chains'),
('SECTOR', 'LOGISTICS', 'Logistics & Transportation', 'HIGH', 'Supply chain infrastructure'),
('SECTOR', 'ENERGY', 'Energy', 'HIGH', 'Critical infrastructure sector'),
('SECTOR', 'HEALTHCARE', 'Healthcare', 'HIGH', 'Essential services sector'),

-- Critical products
('PRODUCT', 'FOOD', 'Food Products', 'HIGH', 'Essential for human survival'),
('PRODUCT', 'PHARMACEUTICALS', 'Pharmaceuticals', 'HIGH', 'Critical healthcare supplies'),
('PRODUCT', 'SEMICONDUCTORS', 'Semiconductors', 'HIGH', 'Technology supply chain critical'),
('PRODUCT', 'AUTOMOTIVE', 'Automotive', 'MEDIUM', 'Major manufacturing sector'),
('PRODUCT', 'TEXTILES', 'Textiles', 'MEDIUM', 'Consumer goods sector');

-- =====================================================
-- 6. SCENARIO TEMPLATES
-- =====================================================

-- Insert scenario templates
INSERT INTO OPS.SCENARIO_TEMPLATES (name, description, category, params_template, horizon_months) VALUES
('ECONOMIC_RECESSION', 'Simulate economic recession scenario', 'ECONOMIC', 
 PARSE_JSON('{"fedfunds_bp": 200, "retail_yoy": -0.05, "unemployment_delta": 0.03}'), 24),
 
('CLIMATE_CHANGE_A2', 'High emissions climate scenario', 'CLIMATE',
 PARSE_JSON('{"temp_delta": 2.0, "precipitation_delta": 0.15, "extreme_weather_freq": 1.5}'), 36),
 
('CLIMATE_CHANGE_B1', 'Low emissions climate scenario', 'CLIMATE',
 PARSE_JSON('{"temp_delta": 1.0, "precipitation_delta": 0.05, "extreme_weather_freq": 1.1}'), 36),
 
('SUPPLY_CHAIN_DISRUPTION', 'Major supply chain disruption', 'SUPPLY',
 PARSE_JSON('{"logistics_cost_delta": 0.25, "supplier_reliability_delta": -0.20, "inventory_turnover_delta": -0.15}'), 18),
 
('POLICY_TIGHTENING', 'Monetary policy tightening', 'POLICY',
 PARSE_JSON('{"fedfunds_bp": 150, "treasury_spread_delta": 0.50, "credit_availability_delta": -0.10}'), 12),
 
('DEMAND_SHOCK', 'Major demand shock', 'DEMAND',
 PARSE_JSON('{"retail_yoy": -0.08, "consumer_confidence_delta": -0.20, "disposable_income_delta": -0.05}'), 12);

-- =====================================================
-- 7. EWS STORED PROCEDURES
-- =====================================================

-- Procedure to enqueue new alerts with deduplication
CREATE OR REPLACE PROCEDURE OPS.SP_EWS_ENQUEUE()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    enqueued_count INTEGER DEFAULT 0;
BEGIN
    -- Insert new alerts, avoiding duplicates
    INSERT INTO OPS.ALERT_QUEUE (
        rule_id, event_ts, date, country, sector, product,
        risk_score, probability, severity, status, dedup_key, routed_to, created_at
    )
    SELECT
        'AUTO_RULE',
        CURRENT_TIMESTAMP(),
        c.date,
        c.country,
        c.sector,
        c.product,
        c.risk_score,
        c.probability,
        c.severity,
        'NEW',
        c.dedup_key,
        CASE 
            WHEN c.severity = 'P1' THEN 'PAGER'
            WHEN c.severity = 'P2' THEN 'SLACK'
            WHEN c.severity = 'P3' THEN 'EMAIL'
            ELSE 'DASHBOARD'
        END,
        CURRENT_TIMESTAMP()
    FROM OPS.ALERT_CANDIDATES c
    LEFT JOIN OPS.ALERT_QUEUE q ON q.dedup_key = c.dedup_key 
        AND q.status IN ('NEW', 'ACKNOWLEDGED', 'INVESTIGATING')
    WHERE q.alert_id IS NULL;
    
    -- Get count of enqueued alerts
    SELECT COUNT(*) INTO enqueued_count FROM OPS.ALERT_QUEUE 
    WHERE created_at >= DATEADD(minute, -5, CURRENT_TIMESTAMP());
    
    RETURN 'ENQUEUED ' || enqueued_count || ' alerts';
END;
$$;

-- Procedure to escalate alerts
CREATE OR REPLACE PROCEDURE OPS.SP_ESCALATE_ALERTS()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    escalated_count INTEGER DEFAULT 0;
BEGIN
    -- Escalate P1 alerts not acknowledged within 15 minutes
    INSERT INTO OPS.ALERT_ESCALATIONS (alert_id, escalation_level, escalated_to, escalation_reason)
    SELECT 
        alert_id,
        1,
        'MANAGER',
        'P1 alert not acknowledged within 15 minutes'
    FROM OPS.ALERT_QUEUE
    WHERE severity = 'P1' 
    AND status = 'NEW'
    AND created_at < DATEADD(minute, -15, CURRENT_TIMESTAMP());
    
    -- Escalate P2 alerts not acknowledged within 1 hour
    INSERT INTO OPS.ALERT_ESCALATIONS (alert_id, escalation_level, escalated_to, escalation_reason)
    SELECT 
        alert_id,
        1,
        'TEAM_LEAD',
        'P2 alert not acknowledged within 1 hour'
    FROM OPS.ALERT_QUEUE
    WHERE severity = 'P2' 
    AND status = 'NEW'
    AND created_at < DATEADD(hour, -1, CURRENT_TIMESTAMP());
    
    SELECT COUNT(*) INTO escalated_count FROM OPS.ALERT_ESCALATIONS 
    WHERE escalated_at >= DATEADD(minute, -5, CURRENT_TIMESTAMP());
    
    RETURN 'ESCALATED ' || escalated_count || ' alerts';
END;
$$;

-- Procedure to run scenario simulation
CREATE OR REPLACE PROCEDURE OPS.SP_RUN_SCENARIO(
    p_name STRING,
    p_horizon_months INTEGER,
    p_params VARIANT,
    p_description STRING DEFAULT NULL
)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    v_run_id STRING;
    v_result_count INTEGER DEFAULT 0;
BEGIN
    -- Generate run ID
    v_run_id := UUID_STRING();
    
    -- Insert scenario run record
    INSERT INTO OPS.SCENARIO_RUNS (run_id, name, description, horizon_months, params, status)
    VALUES (v_run_id, p_name, p_description, p_horizon_months, p_params, 'RUNNING');
    
    -- Simulate scenario results (placeholder - would call actual model)
    INSERT INTO OPS.SCENARIO_RESULTS (run_id, date, country, base_risk_score, scenario_risk_score, delta_vs_base)
    SELECT 
        v_run_id,
        p.date,
        p.country,
        p.risk_score as base_risk_score,
        p.risk_score * (1 + RANDOM() * 0.2 - 0.1) as scenario_risk_score,  -- Simulate 10% variation
        (p.risk_score * (1 + RANDOM() * 0.2 - 0.1)) - p.risk_score as delta_vs_base
    FROM ML.PREDICTIONS p
    WHERE p.date >= CURRENT_DATE() 
    AND p.date <= DATEADD(month, p_horizon_months, CURRENT_DATE())
    LIMIT 1000;  -- Limit for performance
    
    -- Update run status
    UPDATE OPS.SCENARIO_RUNS 
    SET status = 'COMPLETED', completed_at = CURRENT_TIMESTAMP()
    WHERE run_id = v_run_id;
    
    SELECT COUNT(*) INTO v_result_count FROM OPS.SCENARIO_RESULTS WHERE run_id = v_run_id;
    
    RETURN 'SCENARIO ' || v_run_id || ' COMPLETED with ' || v_result_count || ' results';
END;
$$;

-- =====================================================
-- 8. EWS AUTOMATION TASKS
-- =====================================================

-- Task to refresh alert candidates
CREATE OR REPLACE TASK OPS.TASK_REFRESH_CANDIDATES
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = 'USING CRON 0 */2 * * * UTC'  -- Every 2 hours
AS
    TRUNCATE TABLE OPS.ALERT_CANDIDATES;
    INSERT INTO OPS.ALERT_CANDIDATES 
    SELECT
        HASH(TO_VARCHAR(date) || country || TO_VARCHAR(risk_score) || TO_VARCHAR(probability)) AS dedup_key,
        date, country, sector, product, risk_score, probability, model_version,
        CASE 
            WHEN probability >= 0.80 THEN 'P1'
            WHEN probability >= 0.60 THEN 'P2'
            WHEN probability >= 0.40 THEN 'P3'
            ELSE 'P4'
        END AS severity,
        is_watched, watch_priority, CURRENT_TIMESTAMP() as candidate_ts
    FROM OPS.PREDICTIONS_WATCHED
    WHERE probability >= 0.40;

-- Task to enqueue alerts
CREATE OR REPLACE TASK OPS.TASK_EWS_ENQUEUE
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = 'USING CRON 15 7 * * * UTC'  -- Daily at 7:15 AM UTC
AS
    CALL OPS.SP_EWS_ENQUEUE();

-- Task to escalate alerts
CREATE OR REPLACE TASK OPS.TASK_ESCALATE_ALERTS
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = 'USING CRON 0 */1 * * * UTC'  -- Every hour
AS
    CALL OPS.SP_ESCALATE_ALERTS();

-- =====================================================
-- 9. GRANT PERMISSIONS
-- =====================================================

-- Grant permissions to appropriate roles
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA OPS TO ROLE OPS_TASK_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA OPS TO ROLE OPS_MONITOR_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA OPS TO ROLE DASHBOARD_ROLE;

-- Grant execute permissions on procedures
GRANT USAGE ON PROCEDURE OPS.SP_EWS_ENQUEUE() TO ROLE OPS_TASK_ROLE;
GRANT USAGE ON PROCEDURE OPS.SP_ESCALATE_ALERTS() TO ROLE OPS_TASK_ROLE;
GRANT USAGE ON PROCEDURE OPS.SP_RUN_SCENARIO(STRING, INTEGER, VARIANT, STRING) TO ROLE DATA_SCIENTIST_ROLE;
GRANT USAGE ON PROCEDURE OPS.SP_RUN_SCENARIO(STRING, INTEGER, VARIANT, STRING) TO ROLE OPS_TASK_ROLE;

-- Grant task permissions
GRANT EXECUTE TASK ON ACCOUNT TO ROLE OPS_TASK_ROLE;

-- =====================================================
-- 10. INITIAL DATA POPULATION
-- =====================================================

-- Populate alert candidates with current data
INSERT INTO OPS.ALERT_CANDIDATES 
SELECT
    HASH(TO_VARCHAR(date) || country || TO_VARCHAR(risk_score) || TO_VARCHAR(probability)) AS dedup_key,
    date, country, sector, product, risk_score, probability, model_version,
    CASE 
        WHEN probability >= 0.80 THEN 'P1'
        WHEN probability >= 0.60 THEN 'P2'
        WHEN probability >= 0.40 THEN 'P3'
        ELSE 'P4'
    END AS severity,
    is_watched, watch_priority, CURRENT_TIMESTAMP() as candidate_ts
FROM OPS.PREDICTIONS_WATCHED
WHERE probability >= 0.40;

-- =====================================================
-- 11. AUDIT LOG
-- =====================================================

INSERT INTO OPS.LOAD_AUDIT (
    execution_id, phase, step, execution_ts, status, rows_affected, execution_time_seconds, error_message
) VALUES (
    'PHASE8_EWS_' || CURRENT_TIMESTAMP()::STRING,
    'PHASE_8',
    'EWS_SETUP',
    CURRENT_TIMESTAMP(),
    'SUCCESS',
    (SELECT COUNT(*) FROM OPS.ALERT_RULES) + (SELECT COUNT(*) FROM OPS.WATCHLISTS),
    0,
    NULL
);

-- Success message
SELECT 'Phase 8: EWS setup completed successfully!' AS status;
