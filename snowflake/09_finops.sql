-- =====================================================
-- PHASE 9: FINOPS & COST OPTIMIZATION
-- Global Supply Chain Spoilage Forecasting Project
-- Resource monitors, cost dashboards, monthly budgets, alerts
-- =====================================================

USE ROLE ACCOUNTADMIN;

-- =====================================================
-- 1. RESOURCE MONITORS
-- =====================================================

-- Create production resource monitor
CREATE OR REPLACE RESOURCE MONITOR RM_PRD_GLOBAL_SPOILAGE
    WITH CREDIT_QUOTA = 50
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS 
        ON 75 PERCENT DO NOTIFY
        ON 90 PERCENT DO SUSPEND
        ON 100 PERCENT DO SUSPEND_IMMEDIATE;

-- Create staging resource monitor
CREATE OR REPLACE RESOURCE MONITOR RM_STG_GLOBAL_SPOILAGE
    WITH CREDIT_QUOTA = 20
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS 
        ON 80 PERCENT DO NOTIFY
        ON 95 PERCENT DO SUSPEND
        ON 100 PERCENT DO SUSPEND_IMMEDIATE;

-- Create development resource monitor
CREATE OR REPLACE RESOURCE MONITOR RM_DEV_GLOBAL_SPOILAGE
    WITH CREDIT_QUOTA = 10
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS 
        ON 85 PERCENT DO NOTIFY
        ON 95 PERCENT DO SUSPEND
        ON 100 PERCENT DO SUSPEND_IMMEDIATE;

-- =====================================================
-- 2. WAREHOUSE COST OPTIMIZATION
-- =====================================================

-- Attach resource monitors to warehouses
ALTER WAREHOUSE COMPUTE_WH SET RESOURCE_MONITOR = RM_PRD_GLOBAL_SPOILAGE;
ALTER WAREHOUSE COMPUTE_WH_STG SET RESOURCE_MONITOR = RM_STG_GLOBAL_SPOILAGE;
ALTER WAREHOUSE COMPUTE_WH_PRD SET RESOURCE_MONITOR = RM_PRD_GLOBAL_SPOILAGE;

-- Optimize warehouse settings for cost efficiency
ALTER WAREHOUSE COMPUTE_WH SET 
    AUTO_SUSPEND = 300,  -- 5 minutes
    AUTO_RESUME = TRUE,
    INITIALLY_SUSPENDED = TRUE,
    COMMENT = 'Cost-optimized production warehouse';

ALTER WAREHOUSE COMPUTE_WH_STG SET 
    AUTO_SUSPEND = 60,   -- 1 minute
    AUTO_RESUME = TRUE,
    INITIALLY_SUSPENDED = TRUE,
    COMMENT = 'Cost-optimized staging warehouse';

-- =====================================================
-- 3. COST MONITORING VIEWS
-- =====================================================

-- Warehouse cost analysis (7-day view)
CREATE OR REPLACE VIEW GLOBAL_SPOILAGE_DB.OPS.WH_COST_7D AS
SELECT 
    WAREHOUSE_NAME,
    SUM(CREDITS_USED) AS TOTAL_CREDITS,
    AVG(CREDITS_USED) AS AVG_CREDITS_PER_QUERY,
    MAX(CREDITS_USED) AS MAX_CREDITS_PER_QUERY,
    COUNT(*) AS QUERY_COUNT,
    DATE_TRUNC('day', START_TIME) AS USAGE_DATE,
    ROUND(SUM(CREDITS_USED) * 3.0, 2) AS ESTIMATED_COST_USD  -- Assuming $3/credit
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
    AND WAREHOUSE_NAME IN ('COMPUTE_WH', 'COMPUTE_WH_STG', 'COMPUTE_WH_PRD')
GROUP BY WAREHOUSE_NAME, DATE_TRUNC('day', START_TIME)
ORDER BY USAGE_DATE DESC, TOTAL_CREDITS DESC;

-- Monthly cost summary
CREATE OR REPLACE VIEW GLOBAL_SPOILAGE_DB.OPS.MONTHLY_COST_SUMMARY AS
SELECT 
    WAREHOUSE_NAME,
    SUM(CREDITS_USED) AS TOTAL_CREDITS,
    ROUND(SUM(CREDITS_USED) * 3.0, 2) AS TOTAL_COST_USD,
    COUNT(DISTINCT DATE_TRUNC('day', START_TIME)) AS ACTIVE_DAYS,
    ROUND(SUM(CREDITS_USED) / COUNT(DISTINCT DATE_TRUNC('day', START_TIME)), 2) AS AVG_CREDITS_PER_DAY,
    ROUND(SUM(CREDITS_USED) * 3.0 / COUNT(DISTINCT DATE_TRUNC('day', START_TIME)), 2) AS AVG_COST_PER_DAY_USD
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME >= DATEADD('month', -1, CURRENT_TIMESTAMP())
    AND WAREHOUSE_NAME IN ('COMPUTE_WH', 'COMPUTE_WH_STG', 'COMPUTE_WH_PRD')
GROUP BY WAREHOUSE_NAME
ORDER BY TOTAL_COST_USD DESC;

-- Cost by query type
CREATE OR REPLACE VIEW GLOBAL_SPOILAGE_DB.OPS.COST_BY_QUERY_TYPE AS
SELECT 
    CASE 
        WHEN QUERY_TEXT ILIKE '%ML.PREDICTIONS%' THEN 'ML_PREDICTIONS'
        WHEN QUERY_TEXT ILIKE '%OPS.ALERT_QUEUE%' THEN 'ALERT_PROCESSING'
        WHEN QUERY_TEXT ILIKE '%FEAT.MASTER_FEATURES%' THEN 'FEATURE_ENGINEERING'
        WHEN QUERY_TEXT ILIKE '%CORE.UNIFIED_TIME_SERIES%' THEN 'CORE_DATA'
        WHEN QUERY_TEXT ILIKE '%RAW.%' THEN 'RAW_DATA'
        ELSE 'OTHER'
    END AS QUERY_TYPE,
    COUNT(*) AS QUERY_COUNT,
    SUM(CREDITS_USED) AS TOTAL_CREDITS,
    ROUND(SUM(CREDITS_USED) * 3.0, 2) AS TOTAL_COST_USD,
    ROUND(AVG(CREDITS_USED), 4) AS AVG_CREDITS_PER_QUERY
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
JOIN SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY wmh 
    ON qh.QUERY_ID = wmh.QUERY_ID
WHERE qh.START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
    AND qh.WAREHOUSE_NAME IN ('COMPUTE_WH', 'COMPUTE_WH_STG', 'COMPUTE_WH_PRD')
GROUP BY QUERY_TYPE
ORDER BY TOTAL_COST_USD DESC;

-- =====================================================
-- 4. BUDGET MANAGEMENT
-- =====================================================

-- Create budget tracking table
CREATE OR REPLACE TABLE GLOBAL_SPOILAGE_DB.OPS.BUDGET_TRACKING (
    budget_id STRING DEFAULT UUID_STRING(),
    budget_name STRING,
    budget_period STRING, -- 'MONTHLY', 'QUARTERLY', 'YEARLY'
    budget_amount_usd NUMBER,
    actual_spend_usd NUMBER,
    budget_start_date DATE,
    budget_end_date DATE,
    alert_threshold_percent NUMBER DEFAULT 80,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (budget_id)
);

-- Insert default budgets
INSERT INTO GLOBAL_SPOILAGE_DB.OPS.BUDGET_TRACKING (
    budget_name, budget_period, budget_amount_usd, budget_start_date, budget_end_date
) VALUES
('Production Monthly', 'MONTHLY', 150.00, DATE_TRUNC('month', CURRENT_DATE()), LAST_DAY(CURRENT_DATE())),
('Staging Monthly', 'MONTHLY', 60.00, DATE_TRUNC('month', CURRENT_DATE()), LAST_DAY(CURRENT_DATE())),
('Development Monthly', 'MONTHLY', 30.00, DATE_TRUNC('month', CURRENT_DATE()), LAST_DAY(CURRENT_DATE())),
('Quarterly Total', 'QUARTERLY', 720.00, DATE_TRUNC('quarter', CURRENT_DATE()), LAST_DAY(DATE_TRUNC('quarter', CURRENT_DATE()) + INTERVAL '2 months'));

-- =====================================================
-- 5. COST ALERTING
-- =====================================================

-- Create cost alert table
CREATE OR REPLACE TABLE GLOBAL_SPOILAGE_DB.OPS.COST_ALERTS (
    alert_id STRING DEFAULT UUID_STRING(),
    alert_type STRING, -- 'BUDGET_THRESHOLD', 'UNUSUAL_SPEND', 'RESOURCE_MONITOR'
    alert_severity STRING, -- 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'
    alert_message STRING,
    current_spend_usd NUMBER,
    threshold_usd NUMBER,
    alert_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    is_acknowledged BOOLEAN DEFAULT FALSE,
    acknowledged_by STRING,
    acknowledged_at TIMESTAMP,
    PRIMARY KEY (alert_id)
);

-- =====================================================
-- 6. COST OPTIMIZATION PROCEDURES
-- =====================================================

-- Procedure to update budget tracking
CREATE OR REPLACE PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_UPDATE_BUDGET_TRACKING()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    update_result STRING;
    current_spend NUMBER;
    budget_record RECORD;
BEGIN
    -- Update actual spend for each active budget
    FOR budget_record IN 
        SELECT budget_id, budget_name, budget_amount_usd, alert_threshold_percent
        FROM GLOBAL_SPOILAGE_DB.OPS.BUDGET_TRACKING 
        WHERE is_active = TRUE
    LOOP
        -- Calculate current spend
        SELECT COALESCE(SUM(TOTAL_COST_USD), 0) INTO current_spend
        FROM GLOBAL_SPOILAGE_DB.OPS.MONTHLY_COST_SUMMARY
        WHERE WAREHOUSE_NAME IN ('COMPUTE_WH', 'COMPUTE_WH_STG', 'COMPUTE_WH_PRD');
        
        -- Update budget tracking
        UPDATE GLOBAL_SPOILAGE_DB.OPS.BUDGET_TRACKING
        SET actual_spend_usd = current_spend,
            updated_at = CURRENT_TIMESTAMP()
        WHERE budget_id = budget_record.budget_id;
        
        -- Check for threshold alerts
        IF current_spend >= (budget_record.budget_amount_usd * budget_record.alert_threshold_percent / 100) THEN
            INSERT INTO GLOBAL_SPOILAGE_DB.OPS.COST_ALERTS (
                alert_type, alert_severity, alert_message, current_spend_usd, threshold_usd
            ) VALUES (
                'BUDGET_THRESHOLD',
                CASE 
                    WHEN current_spend >= budget_record.budget_amount_usd THEN 'CRITICAL'
                    WHEN current_spend >= (budget_record.budget_amount_usd * 0.9) THEN 'HIGH'
                    ELSE 'MEDIUM'
                END,
                'Budget threshold reached for ' || budget_record.budget_name || 
                ': $' || current_spend || ' of $' || budget_record.budget_amount_usd,
                current_spend,
                budget_record.budget_amount_usd * budget_record.alert_threshold_percent / 100
            );
        END IF;
    END LOOP;
    
    SELECT 'BUDGET_UPDATED' INTO update_result;
    
    RETURN update_result;
END;
$$;

-- Procedure for cost optimization recommendations
CREATE OR REPLACE PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_COST_OPTIMIZATION_RECOMMENDATIONS()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    recommendations STRING;
    high_cost_queries INTEGER;
    unused_warehouses INTEGER;
    oversized_warehouses INTEGER;
BEGIN
    -- Analyze high-cost queries
    SELECT COUNT(*) INTO high_cost_queries
    FROM GLOBAL_SPOILAGE_DB.OPS.COST_BY_QUERY_TYPE
    WHERE AVG_CREDITS_PER_QUERY > 1.0;
    
    -- Check for unused warehouses
    SELECT COUNT(*) INTO unused_warehouses
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSES w
    LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY wmh 
        ON w.WAREHOUSE_NAME = wmh.WAREHOUSE_NAME
        AND wmh.START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
    WHERE wmh.WAREHOUSE_NAME IS NULL;
    
    -- Check for oversized warehouses
    SELECT COUNT(*) INTO oversized_warehouses
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
    WHERE START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
    AND CREDITS_USED < 0.1  -- Very low credit usage
    AND WAREHOUSE_NAME IN ('COMPUTE_WH', 'COMPUTE_WH_STG', 'COMPUTE_WH_PRD');
    
    -- Generate recommendations
    recommendations := 'COST_OPTIMIZATION_RECOMMENDATIONS: ';
    
    IF high_cost_queries > 0 THEN
        recommendations := recommendations || 'Review ' || high_cost_queries || ' high-cost queries. ';
    END IF;
    
    IF unused_warehouses > 0 THEN
        recommendations := recommendations || 'Consider removing ' || unused_warehouses || ' unused warehouses. ';
    END IF;
    
    IF oversized_warehouses > 0 THEN
        recommendations := recommendations || 'Consider downsizing ' || oversized_warehouses || ' oversized warehouses. ';
    END IF;
    
    RETURN recommendations;
END;
$$;

-- =====================================================
-- 7. FINOPS DASHBOARD METRICS
-- =====================================================

-- Create FinOps dashboard view
CREATE OR REPLACE VIEW GLOBAL_SPOILAGE_DB.OPS.FINOPS_DASHBOARD AS
SELECT 
    CURRENT_DATE() AS report_date,
    'GLOBAL_SPOILAGE' AS project_name,
    (SELECT SUM(TOTAL_COST_USD) FROM GLOBAL_SPOILAGE_DB.OPS.MONTHLY_COST_SUMMARY) AS total_monthly_cost,
    (SELECT SUM(budget_amount_usd) FROM GLOBAL_SPOILAGE_DB.OPS.BUDGET_TRACKING WHERE is_active = TRUE) AS total_budget,
    (SELECT COUNT(*) FROM GLOBAL_SPOILAGE_DB.OPS.COST_ALERTS WHERE is_acknowledged = FALSE) AS active_alerts,
    (SELECT AVG(TOTAL_CREDITS) FROM GLOBAL_SPOILAGE_DB.OPS.WH_COST_7D WHERE USAGE_DATE >= DATEADD('day', -7, CURRENT_DATE())) AS avg_daily_credits,
    (SELECT MAX(TOTAL_CREDITS) FROM GLOBAL_SPOILAGE_DB.OPS.WH_COST_7D WHERE USAGE_DATE >= DATEADD('day', -7, CURRENT_DATE())) AS peak_daily_credits;

-- =====================================================
-- 8. COST REPORTING AUTOMATION
-- =====================================================

-- Create cost reporting table
CREATE OR REPLACE TABLE GLOBAL_SPOILAGE_DB.OPS.COST_REPORTS (
    report_id STRING DEFAULT UUID_STRING(),
    report_date DATE,
    report_type STRING, -- 'DAILY', 'WEEKLY', 'MONTHLY'
    total_cost_usd NUMBER,
    cost_by_warehouse VARIANT,
    cost_by_query_type VARIANT,
    budget_variance_usd NUMBER,
    recommendations STRING,
    generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (report_id)
);

-- =====================================================
-- 9. AUTOMATED COST MONITORING TASKS
-- =====================================================

-- Task for daily budget updates
CREATE OR REPLACE TASK GLOBAL_SPOILAGE_DB.OPS.TASK_DAILY_BUDGET_UPDATE
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = 'USING CRON 0 6 * * * UTC' -- Daily at 6 AM UTC
AS
    CALL GLOBAL_SPOILAGE_DB.OPS.SP_UPDATE_BUDGET_TRACKING();

-- Task for weekly cost optimization analysis
CREATE OR REPLACE TASK GLOBAL_SPOILAGE_DB.OPS.TASK_WEEKLY_COST_ANALYSIS
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = 'USING CRON 0 8 * * 1 UTC' -- Weekly on Monday at 8 AM UTC
AS
    CALL GLOBAL_SPOILAGE_DB.OPS.SP_COST_OPTIMIZATION_RECOMMENDATIONS();

-- =====================================================
-- 10. COST THRESHOLD ALERTS
-- =====================================================

-- Create cost threshold monitoring
CREATE OR REPLACE VIEW GLOBAL_SPOILAGE_DB.OPS.COST_THRESHOLD_MONITORING AS
SELECT 
    bt.budget_name,
    bt.budget_amount_usd,
    bt.actual_spend_usd,
    ROUND((bt.actual_spend_usd / bt.budget_amount_usd) * 100, 2) AS spend_percentage,
    bt.alert_threshold_percent,
    CASE 
        WHEN bt.actual_spend_usd >= bt.budget_amount_usd THEN 'OVER_BUDGET'
        WHEN bt.actual_spend_usd >= (bt.budget_amount_usd * bt.alert_threshold_percent / 100) THEN 'THRESHOLD_REACHED'
        ELSE 'WITHIN_BUDGET'
    END AS budget_status
FROM GLOBAL_SPOILAGE_DB.OPS.BUDGET_TRACKING bt
WHERE bt.is_active = TRUE;

-- =====================================================
-- 11. GRANT PERMISSIONS
-- =====================================================

-- Grant FinOps permissions
GRANT SELECT ON ALL VIEWS IN SCHEMA GLOBAL_SPOILAGE_DB.OPS TO ROLE OPS_MONITOR_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA GLOBAL_SPOILAGE_DB.OPS TO ROLE OPS_MONITOR_ROLE;

GRANT USAGE ON PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_UPDATE_BUDGET_TRACKING() TO ROLE OPS_TASK_ROLE;
GRANT USAGE ON PROCEDURE GLOBAL_SPOILAGE_DB.OPS.SP_COST_OPTIMIZATION_RECOMMENDATIONS() TO ROLE OPS_TASK_ROLE;

-- Grant task permissions
GRANT EXECUTE TASK ON ACCOUNT TO ROLE OPS_TASK_ROLE;

-- =====================================================
-- 12. AUDIT LOG
-- =====================================================

INSERT INTO GLOBAL_SPOILAGE_DB.OPS.LOAD_AUDIT (
    execution_id, phase, step, execution_ts, status, rows_affected, execution_time_seconds, error_message
) VALUES (
    'PHASE9_FINOPS_' || CURRENT_TIMESTAMP()::STRING,
    'PHASE_9',
    'FINOPS_SETUP',
    CURRENT_TIMESTAMP(),
    'SUCCESS',
    0,
    0,
    NULL
);

-- Success message
SELECT 'Phase 9: FinOps setup completed successfully!' AS status;
