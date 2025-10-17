-- =====================================================
-- PHASE 7: SECRETS MANAGEMENT & ALERTING
-- Global Supply Chain Spoilage Forecasting Project
-- Secrets, API Integrations, Alert Routing
-- =====================================================

USE DATABASE GLOBAL_SPOILAGE_DB;
USE SCHEMA OPS;

-- =====================================================
-- 1. SECRETS MANAGEMENT TABLES
-- =====================================================

-- Create secrets registry (metadata only, no actual secrets)
CREATE OR REPLACE TABLE OPS.SECRETS_REGISTRY (
    secret_id STRING DEFAULT UUID_STRING(),
    secret_name STRING NOT NULL,
    secret_type STRING,  -- API_KEY, DATABASE, SERVICE_ACCOUNT, etc.
    service_name STRING,
    owner_role STRING,
    created_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    last_rotated TIMESTAMP,
    rotation_frequency_days NUMBER,
    next_rotation_date DATE,
    status STRING,  -- ACTIVE, ROTATING, EXPIRED, REVOKED
    vault_path STRING,  -- Path in external vault (e.g., AWS Secrets Manager)
    PRIMARY KEY (secret_id),
    UNIQUE (secret_name)
);

-- Create secret rotation history
CREATE OR REPLACE TABLE OPS.SECRET_ROTATION_HISTORY (
    rotation_id STRING DEFAULT UUID_STRING(),
    secret_name STRING,
    rotation_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    rotation_type STRING,  -- SCHEDULED, MANUAL, EMERGENCY
    rotated_by STRING,
    old_secret_hash STRING,
    new_secret_hash STRING,
    status STRING,  -- SUCCESS, FAILED, ROLLBACK
    error_message STRING,
    PRIMARY KEY (rotation_id)
);

-- Create secret access log
CREATE OR REPLACE TABLE OPS.SECRET_ACCESS_LOG (
    access_id STRING DEFAULT UUID_STRING(),
    secret_name STRING,
    access_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    accessed_by_user STRING,
    accessed_by_role STRING,
    access_type STRING,  -- READ, ROTATE, DELETE
    status STRING,  -- ALLOWED, DENIED
    ip_address STRING,
    PRIMARY KEY (access_id)
);

-- =====================================================
-- 2. API INTEGRATIONS (Example Configuration)
-- =====================================================

-- Create notification integration for alerts (Example: Email)
-- NOTE: This is a template - configure with actual credentials
CREATE OR REPLACE NOTIFICATION INTEGRATION EMAIL_ALERT_INTEGRATION
    TYPE = EMAIL
    ENABLED = TRUE
    ALLOWED_RECIPIENTS = ('ops-team@company.com', 'data-team@company.com')
    COMMENT = 'Email notification integration for alerts';

-- Create API integration for external services (Example: Slack)
-- NOTE: Requires actual Slack webhook URL
CREATE OR REPLACE API INTEGRATION SLACK_ALERT_INTEGRATION
    API_PROVIDER = AWS_API_GATEWAY
    API_AWS_ROLE_ARN = 'arn:aws:iam::123456789012:role/SnowflakeAPIRole'
    API_ALLOWED_PREFIXES = ('https://hooks.slack.com/')
    ENABLED = TRUE
    COMMENT = 'Slack webhook integration for alerts';

-- =====================================================
-- 3. ALERT CONFIGURATION TABLES
-- =====================================================

-- Create alert configuration table
CREATE OR REPLACE TABLE OPS.ALERT_CONFIG (
    alert_id STRING DEFAULT UUID_STRING(),
    alert_name STRING NOT NULL,
    alert_type STRING,  -- DRIFT, ROI, TASK_FAILURE, SLA, SECURITY, DATA_QUALITY
    severity STRING,  -- INFO, WARNING, CRITICAL, EMERGENCY
    enabled BOOLEAN DEFAULT TRUE,
    threshold_value FLOAT,
    threshold_operator STRING,  -- GT, LT, EQ, GTE, LTE
    check_frequency_minutes NUMBER,
    notification_channels ARRAY,  -- ['EMAIL', 'SLACK', 'PAGERDUTY', 'SMS']
    recipients ARRAY,
    escalation_policy STRING,
    created_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    modified_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (alert_id),
    UNIQUE (alert_name)
);

-- Create alert history table
CREATE OR REPLACE TABLE OPS.ALERT_HISTORY (
    history_id STRING DEFAULT UUID_STRING(),
    alert_name STRING,
    triggered_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    alert_type STRING,
    severity STRING,
    threshold_value FLOAT,
    actual_value FLOAT,
    message STRING,
    notification_sent BOOLEAN,
    notification_channels ARRAY,
    recipients ARRAY,
    acknowledged_by STRING,
    acknowledged_timestamp TIMESTAMP,
    resolved_timestamp TIMESTAMP,
    status STRING,  -- OPEN, ACKNOWLEDGED, RESOLVED, ESCALATED
    PRIMARY KEY (history_id)
);

-- Create alert suppression rules
CREATE OR REPLACE TABLE OPS.ALERT_SUPPRESSION (
    suppression_id STRING DEFAULT UUID_STRING(),
    alert_name STRING,
    suppression_start TIMESTAMP,
    suppression_end TIMESTAMP,
    suppressed_by STRING,
    reason STRING,
    status STRING,  -- ACTIVE, EXPIRED
    PRIMARY KEY (suppression_id)
);

-- =====================================================
-- 4. SLA MONITORING TABLES
-- =====================================================

-- Create SLA definitions
CREATE OR REPLACE TABLE OPS.SLA_DEFINITIONS (
    sla_id STRING DEFAULT UUID_STRING(),
    sla_name STRING NOT NULL,
    sla_type STRING,  -- PIPELINE_LATENCY, MODEL_ACCURACY, DATA_FRESHNESS, UPTIME
    target_value FLOAT,
    target_unit STRING,  -- MINUTES, HOURS, PERCENTAGE
    measurement_frequency STRING,  -- HOURLY, DAILY, WEEKLY
    alert_threshold_percent FLOAT,  -- Alert when SLA drops below this % of target
    owner_role STRING,
    business_impact STRING,  -- HIGH, MEDIUM, LOW
    created_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (sla_id),
    UNIQUE (sla_name)
);

-- Create SLA measurements
CREATE OR REPLACE TABLE OPS.SLA_MEASUREMENTS (
    measurement_id STRING DEFAULT UUID_STRING(),
    sla_name STRING,
    measurement_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    actual_value FLOAT,
    target_value FLOAT,
    compliance_status STRING,  -- MET, MISSED, AT_RISK
    variance_percent FLOAT,
    measurement_period_start TIMESTAMP,
    measurement_period_end TIMESTAMP,
    PRIMARY KEY (measurement_id)
);

-- =====================================================
-- 5. ROI & BUSINESS METRICS TRACKING
-- =====================================================

-- Create ROI tracking table
CREATE OR REPLACE TABLE OPS.ROI_METRICS (
    roi_id STRING DEFAULT UUID_STRING(),
    measurement_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    metric_name STRING,
    metric_category STRING,  -- COST_SAVINGS, EFFICIENCY_GAIN, WASTE_REDUCTION
    metric_value FLOAT,
    metric_unit STRING,
    baseline_value FLOAT,
    improvement_percent FLOAT,
    annualized_value FLOAT,
    confidence_level FLOAT,
    data_source STRING,
    notes STRING,
    PRIMARY KEY (roi_id)
);

-- Create business value dashboard
CREATE OR REPLACE TABLE OPS.BUSINESS_VALUE_DASHBOARD (
    dashboard_id STRING DEFAULT UUID_STRING(),
    report_date DATE DEFAULT CURRENT_DATE(),
    total_cost_savings FLOAT,
    waste_reduction_percent FLOAT,
    forecast_accuracy_percent FLOAT,
    operational_efficiency_score FLOAT,
    system_uptime_percent FLOAT,
    user_satisfaction_score FLOAT,
    incidents_count NUMBER,
    sla_compliance_percent FLOAT,
    created_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (dashboard_id)
);

-- =====================================================
-- 6. DRIFT DETECTION CONFIGURATION
-- =====================================================

-- Create model drift monitoring
CREATE OR REPLACE TABLE ML.MODEL_DRIFT_MONITOR (
    drift_id STRING DEFAULT UUID_STRING(),
    model_name STRING,
    check_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    drift_type STRING,  -- FEATURE_DRIFT, PREDICTION_DRIFT, PERFORMANCE_DRIFT
    drift_score FLOAT,
    drift_threshold FLOAT,
    status STRING,  -- NO_DRIFT, DRIFT_DETECTED, CRITICAL_DRIFT
    feature_name STRING,
    baseline_distribution VARIANT,
    current_distribution VARIANT,
    statistical_test STRING,
    p_value FLOAT,
    alert_triggered BOOLEAN,
    PRIMARY KEY (drift_id)
);

-- Create data quality drift
CREATE OR REPLACE TABLE OPS.DATA_QUALITY_DRIFT (
    drift_id STRING DEFAULT UUID_STRING(),
    table_name STRING,
    check_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    quality_metric STRING,  -- NULL_RATE, UNIQUENESS, COMPLETENESS, VALIDITY
    baseline_value FLOAT,
    current_value FLOAT,
    drift_percent FLOAT,
    threshold_percent FLOAT,
    status STRING,  -- STABLE, DEGRADING, CRITICAL
    alert_triggered BOOLEAN,
    PRIMARY KEY (drift_id)
);

-- =====================================================
-- 7. TASK FAILURE MONITORING
-- =====================================================

-- Create task failure tracking
CREATE OR REPLACE TABLE OPS.TASK_FAILURE_LOG (
    failure_id STRING DEFAULT UUID_STRING(),
    task_name STRING,
    failure_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    error_code STRING,
    error_message STRING,
    query_id STRING,
    warehouse_name STRING,
    execution_time_seconds FLOAT,
    retry_count NUMBER,
    max_retries NUMBER,
    next_retry_time TIMESTAMP,
    status STRING,  -- FAILED, RETRYING, EXHAUSTED, RESOLVED
    resolution_notes STRING,
    PRIMARY KEY (failure_id)
);

-- =====================================================
-- 8. POPULATE INITIAL CONFIGURATIONS
-- =====================================================

-- Insert sample secret registry entries (metadata only)
INSERT INTO OPS.SECRETS_REGISTRY (
    secret_name, secret_type, service_name, owner_role, 
    rotation_frequency_days, next_rotation_date, status, vault_path
) VALUES
    ('SNOWFLAKE_API_KEY', 'API_KEY', 'Snowflake', 'PLATFORM_ADMIN', 90, DATEADD(day, 90, CURRENT_DATE()), 'ACTIVE', '/secrets/snowflake/api_key'),
    ('KAGGLE_API_KEY', 'API_KEY', 'Kaggle', 'DATA_ENGINEER_ROLE', 90, DATEADD(day, 90, CURRENT_DATE()), 'ACTIVE', '/secrets/kaggle/api_key'),
    ('AWS_SERVICE_ACCOUNT', 'SERVICE_ACCOUNT', 'AWS', 'PLATFORM_ADMIN', 180, DATEADD(day, 180, CURRENT_DATE()), 'ACTIVE', '/secrets/aws/service_account'),
    ('SLACK_WEBHOOK_URL', 'API_KEY', 'Slack', 'OPS_TASK_ROLE', 365, DATEADD(day, 365, CURRENT_DATE()), 'ACTIVE', '/secrets/slack/webhook'),
    ('EMAIL_SMTP_PASSWORD', 'PASSWORD', 'Email', 'OPS_TASK_ROLE', 90, DATEADD(day, 90, CURRENT_DATE()), 'ACTIVE', '/secrets/email/smtp');

-- Insert alert configurations
INSERT INTO OPS.ALERT_CONFIG (
    alert_name, alert_type, severity, threshold_value, threshold_operator,
    check_frequency_minutes, notification_channels, recipients
) VALUES
    ('MODEL_ACCURACY_DROP', 'DRIFT', 'CRITICAL', 85.0, 'LT', 60, ARRAY_CONSTRUCT('EMAIL', 'SLACK'), ARRAY_CONSTRUCT('data-team@company.com', 'ml-team@company.com')),
    ('PIPELINE_FAILURE', 'TASK_FAILURE', 'CRITICAL', 1.0, 'GTE', 5, ARRAY_CONSTRUCT('EMAIL', 'SLACK', 'PAGERDUTY'), ARRAY_CONSTRUCT('ops-team@company.com')),
    ('DATA_FRESHNESS_SLA', 'SLA', 'WARNING', 24.0, 'GT', 60, ARRAY_CONSTRUCT('EMAIL'), ARRAY_CONSTRUCT('data-team@company.com')),
    ('COST_OVERRUN', 'ROI', 'WARNING', 80.0, 'GT', 1440, ARRAY_CONSTRUCT('EMAIL'), ARRAY_CONSTRUCT('finance@company.com', 'ops-team@company.com')),
    ('SECURITY_BREACH_ATTEMPT', 'SECURITY', 'EMERGENCY', 5.0, 'GTE', 1, ARRAY_CONSTRUCT('EMAIL', 'SLACK', 'SMS', 'PAGERDUTY'), ARRAY_CONSTRUCT('security@company.com', 'ciso@company.com')),
    ('DATA_QUALITY_DEGRADATION', 'DATA_QUALITY', 'WARNING', 90.0, 'LT', 60, ARRAY_CONSTRUCT('EMAIL', 'SLACK'), ARRAY_CONSTRUCT('data-team@company.com'));

-- Insert SLA definitions
INSERT INTO OPS.SLA_DEFINITIONS (
    sla_name, sla_type, target_value, target_unit, measurement_frequency,
    alert_threshold_percent, owner_role, business_impact
) VALUES
    ('PIPELINE_EXECUTION_TIME', 'PIPELINE_LATENCY', 60.0, 'MINUTES', 'HOURLY', 80.0, 'OPS_TASK_ROLE', 'HIGH'),
    ('MODEL_PREDICTION_ACCURACY', 'MODEL_ACCURACY', 95.0, 'PERCENTAGE', 'DAILY', 90.0, 'DATA_SCIENTIST_ROLE', 'HIGH'),
    ('DATA_FRESHNESS', 'DATA_FRESHNESS', 12.0, 'HOURS', 'HOURLY', 75.0, 'DATA_ENGINEER_ROLE', 'MEDIUM'),
    ('SYSTEM_UPTIME', 'UPTIME', 99.9, 'PERCENTAGE', 'DAILY', 99.0, 'PLATFORM_ADMIN', 'HIGH'),
    ('API_RESPONSE_TIME', 'PIPELINE_LATENCY', 2.0, 'SECONDS', 'HOURLY', 80.0, 'OPS_TASK_ROLE', 'MEDIUM');

-- Insert initial ROI metrics
INSERT INTO OPS.ROI_METRICS (
    metric_name, metric_category, metric_value, metric_unit, baseline_value,
    improvement_percent, annualized_value, confidence_level
) VALUES
    ('WASTE_REDUCTION', 'COST_SAVINGS', 250000.0, 'USD', 1000000.0, 25.0, 3000000.0, 0.85),
    ('FORECAST_ACCURACY_IMPROVEMENT', 'EFFICIENCY_GAIN', 15.0, 'PERCENTAGE', 80.0, 18.75, NULL, 0.90),
    ('OPERATIONAL_COST_REDUCTION', 'COST_SAVINGS', 50000.0, 'USD', 200000.0, 25.0, 600000.0, 0.80),
    ('INVENTORY_OPTIMIZATION', 'EFFICIENCY_GAIN', 20.0, 'PERCENTAGE', 100.0, 20.0, NULL, 0.75);

-- =====================================================
-- 9. ALERT ROUTING PROCEDURES
-- =====================================================

-- Create procedure to trigger alerts
CREATE OR REPLACE PROCEDURE OPS.TRIGGER_ALERT(
    p_alert_name STRING,
    p_actual_value FLOAT,
    p_message STRING
)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    -- Check if alert is enabled
    LET alert_config_exists NUMBER := (
        SELECT COUNT(*) FROM OPS.ALERT_CONFIG 
        WHERE alert_name = :p_alert_name AND enabled = TRUE
    );
    
    IF (alert_config_exists = 0) THEN
        RETURN 'Alert not found or not enabled: ' || :p_alert_name;
    END IF;
    
    -- Get alert configuration
    LET alert_config OBJECT := (
        SELECT OBJECT_CONSTRUCT(
            'alert_type', alert_type,
            'severity', severity,
            'threshold_value', threshold_value,
            'notification_channels', notification_channels,
            'recipients', recipients
        )
        FROM OPS.ALERT_CONFIG
        WHERE alert_name = :p_alert_name
    );
    
    -- Insert into alert history
    INSERT INTO OPS.ALERT_HISTORY (
        alert_name, alert_type, severity, threshold_value, actual_value,
        message, notification_sent, notification_channels, recipients, status
    )
    SELECT 
        :p_alert_name,
        alert_config:alert_type::STRING,
        alert_config:severity::STRING,
        alert_config:threshold_value::FLOAT,
        :p_actual_value,
        :p_message,
        TRUE,
        alert_config:notification_channels,
        alert_config:recipients,
        'OPEN'
    FROM (SELECT :alert_config AS alert_config);
    
    RETURN 'Alert triggered successfully: ' || :p_alert_name;
END;
$$;

-- Grant execute on procedure
GRANT USAGE ON PROCEDURE OPS.TRIGGER_ALERT(STRING, FLOAT, STRING) TO ROLE OPS_TASK_ROLE;
GRANT USAGE ON PROCEDURE OPS.TRIGGER_ALERT(STRING, FLOAT, STRING) TO ROLE OPS_MONITOR_ROLE;

-- =====================================================
-- 10. AUDIT LOG
-- =====================================================

INSERT INTO OPS.LOAD_AUDIT (
    execution_id,
    phase,
    step,
    execution_ts,
    status,
    rows_affected,
    execution_time_seconds,
    error_message
) VALUES (
    'PHASE7_SECRETS_ALERTS_' || CURRENT_TIMESTAMP()::STRING,
    'PHASE_7',
    'SECRETS_ALERTS_SETUP',
    CURRENT_TIMESTAMP(),
    'SUCCESS',
    0,
    0,
    NULL
);

-- Success message
SELECT 'Phase 7: Secrets & Alerts setup completed successfully!' AS status;
