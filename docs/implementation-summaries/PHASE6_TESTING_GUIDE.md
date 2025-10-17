# Phase 6 Testing & Validation Guide

## Pre-Production Readiness Checklist

This guide provides step-by-step instructions for validating Phase 6 implementation before proceeding to Phase 7 or production deployment.

---

## Quick Start

### Option 1: Automated Python Test Suite (Recommended)

```bash
cd snowpark
python test_phase6.py
```

This will:
- Test all Phase 6 components systematically
- Enable tasks in correct order
- Verify streams and offsets
- Run full pipeline dry run
- Check ROI guardrails
- Generate comprehensive report
- Create configuration backups

### Option 2: SQL-Based Testing

```bash
snowsql -f snowflake/test_phase6_readiness.sql
```

This will:
- Execute 25+ validation checks
- Verify task and stream infrastructure
- Check optimization results
- Validate data completeness
- Generate readiness report

---

## Detailed Testing Procedure

### 1. Pre-Test Preparation

**Verify Prerequisites:**
```sql
-- Check Phase 5 completion
SELECT COUNT(*) FROM ML.MODEL_RESULTS;  -- Should be 6
SELECT COUNT(*) FROM ML.PREDICTIONS;     -- Should be >100

-- Check OPS schema exists
USE SCHEMA OPS;
SHOW TABLES;
```

**Environment Check:**
```bash
# Verify Python dependencies
pip list | grep -E "snowflake|scipy|pandas|streamlit"

# Check configuration file
cat ../snowflake_config.json
```

---

### 2. Task Infrastructure Testing

**Check Task Definitions:**
```sql
USE DATABASE GLOBAL_SPOILAGE_DB;
USE SCHEMA OPS;

SELECT name, state, schedule, warehouse
FROM INFORMATION_SCHEMA.TASKS
WHERE task_schema = 'OPS'
ORDER BY name;
```

Expected tasks (6 total):
- `TASK_DAILY_CORE_REFRESH` (1 AM UTC daily)
- `TASK_DAILY_FEATURE_REFRESH` (after CORE refresh)
- `TASK_WEEKLY_MODEL_RETRAIN` (Monday 6 AM UTC)
- `TASK_DAILY_PREDICTION_REFRESH` (7 AM UTC daily)
- `TASK_STREAM_FEDFUNDS` (5 min polling)
- `TASK_STREAM_RETAIL` (5 min polling)

**Enable Tasks (Correct Order):**
```sql
-- 1. Enable child tasks first (no dependencies)
ALTER TASK OPS.TASK_DAILY_PREDICTION_REFRESH RESUME;
ALTER TASK OPS.TASK_WEEKLY_MODEL_RETRAIN RESUME;

-- 2. Enable dependent task
ALTER TASK OPS.TASK_DAILY_FEATURE_REFRESH RESUME;

-- 3. Enable root task last
ALTER TASK OPS.TASK_DAILY_CORE_REFRESH RESUME;

-- 4. Enable stream-triggered tasks
ALTER TASK OPS.TASK_STREAM_FEDFUNDS RESUME;
ALTER TASK OPS.TASK_STREAM_RETAIL RESUME;

-- Verify all started
SELECT name, state FROM INFORMATION_SCHEMA.TASKS WHERE task_schema = 'OPS';
```

**Manual Task Execution Test:**
```sql
-- Test stored procedures
CALL OPS.SP_REFRESH_CORE_DATA();
CALL OPS.SP_REFRESH_FEATURES();

-- Check execution logs
SELECT * FROM OPS.TASK_RUNS ORDER BY execution_start DESC LIMIT 10;
SELECT * FROM OPS.LOAD_AUDIT ORDER BY execution_timestamp DESC LIMIT 10;
```

---

### 3. Stream Infrastructure Testing

**Check Stream Definitions:**
```sql
SELECT name, table_name, table_schema
FROM INFORMATION_SCHEMA.STREAMS
WHERE table_schema = 'OPS'
ORDER BY name;
```

Expected streams (7 total):
- RAW schema: FEDFUNDS, RETAIL, RECESSION, SP500 (4 streams)
- CORE schema: ECONOMIC, RETAIL (2 streams)
- FEAT schema: MASTER (1 stream)

**Verify Stream Data:**
```sql
-- Check if streams have pending data
SELECT 
    'STREAM_RAW_FEDFUNDS' AS stream,
    SYSTEM$STREAM_HAS_DATA('OPS.STREAM_RAW_FEDFUNDS') AS has_data,
    (SELECT COUNT(*) FROM OPS.STREAM_RAW_FEDFUNDS) AS pending_rows;

-- Check stream status
SELECT * FROM OPS.STREAM_STATUS ORDER BY last_processed DESC;

-- Verify offset freshness (<24h)
SELECT 
    stream_name,
    last_processed,
    DATEDIFF(hour, last_processed, CURRENT_TIMESTAMP()) AS hours_since_process
FROM OPS.STREAM_STATUS;
```

**Test Stream Processing:**
```sql
-- Insert test data to trigger stream
INSERT INTO RAW.FEDFUNDS_MONTHLY (DATE, VALUE)
VALUES ('2025-01-15', 5.25);

-- Check stream detects change
SELECT COUNT(*) FROM OPS.STREAM_RAW_FEDFUNDS;

-- Process stream manually
CALL OPS.SP_PROCESS_FEDFUNDS_STREAM();

-- Verify stream consumed
SELECT COUNT(*) FROM OPS.STREAM_RAW_FEDFUNDS;  -- Should be 0

-- Check CORE table updated
SELECT * FROM CORE.FEDFUNDS WHERE date = '2025-01-15';
```

---

### 4. Optimization & ROI Testing

**Run Optimization:**
```bash
cd optimization
python resource_lp.py
```

**Verify Results:**
```sql
-- Check optimization logs
SELECT 
    optimization_run_id,
    method,
    status,
    total_budget,
    budget_used,
    ROUND((budget_used / total_budget) * 100, 2) AS budget_util_pct,
    total_spoilage_reduction,
    ROUND(spoilage_reduction_pct, 2) AS reduction_pct,
    ROUND((total_spoilage_reduction / budget_used), 2) AS roi_ratio
FROM OPS.OPTIMIZATION_LOGS
ORDER BY created_at DESC
LIMIT 1;
```

**ROI Guardrail Check:**
```sql
-- ROI must be >= 1.5× (savings >= 1.5× spend)
WITH latest_opt AS (
    SELECT 
        total_spoilage_reduction AS savings,
        budget_used AS spend,
        (total_spoilage_reduction / budget_used) AS roi_ratio
    FROM OPS.OPTIMIZATION_LOGS
    ORDER BY created_at DESC
    LIMIT 1
)
SELECT 
    ROUND(savings, 2) AS savings_dollars,
    ROUND(spend, 2) AS spend_dollars,
    ROUND(roi_ratio, 2) AS roi_ratio,
    CASE 
        WHEN roi_ratio >= 1.5 THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS roi_check
FROM latest_opt;
```

**Expected Results:**
- Spoilage reduction: ≥30%
- Budget utilization: 70-100%
- ROI ratio: ≥1.5×
- Status: SUCCESS

---

### 5. Policy Evaluation Testing

**Run Policy Comparison:**
```bash
cd optimization
python policy_eval.py
```

**Verify Results:**
```sql
-- Check policy evaluations
SELECT 
    policy_name,
    ROUND(total_cost, 2) AS total_cost,
    ROUND(spoilage_reduction, 2) AS savings,
    ROUND(spoilage_reduction_pct, 2) AS reduction_pct,
    ROUND(allocation_efficiency, 2) AS efficiency,
    rank_by_total_cost
FROM OPS.POLICY_EVALUATION
WHERE evaluation_timestamp = (SELECT MAX(evaluation_timestamp) FROM OPS.POLICY_EVALUATION)
ORDER BY total_cost;
```

**Expected Results:**
- At least 4 policies evaluated
- Optimal (LP) policy ranks #1 by total cost
- Clear efficiency advantages demonstrated

---

### 6. Monitoring & Drift Detection

**Run Monitoring:**
```bash
cd snowpark
python monitor_ops.py
```

**Check Results:**
```sql
-- Feature drift summary
SELECT 
    feature_name,
    ks_statistic,
    p_value,
    has_drift,
    alert_severity
FROM OPS.MONITORING_SUMMARY
WHERE check_type = 'DRIFT_DETECTION'
  AND checked_at >= DATEADD(day, -1, CURRENT_DATE())
ORDER BY p_value;

-- Check alerts
SELECT 
    alert_type,
    severity,
    message,
    created_at
FROM OPS.ALERTS
WHERE acknowledged = FALSE
ORDER BY 
    CASE severity 
        WHEN 'HIGH' THEN 1 
        WHEN 'MEDIUM' THEN 2 
        ELSE 3 
    END,
    created_at DESC;
```

**Expected Results:**
- 0-2 features with drift (≤2 acceptable)
- No HIGH severity alerts unacknowledged
- Monitoring completed successfully

---

### 7. Dashboard Testing

**Launch Dashboard:**
```bash
cd dashboards
streamlit run streamlit_app.py
```

**Verify Functionality:**
1. **Overview Page:**
   - 4 KPI metrics displayed
   - Spoilage timeseries chart renders
   - Risk classification chart renders

2. **Predictions Page:**
   - Prediction data table populated
   - Date range filter functional

3. **Model Performance:**
   - Model comparison charts display
   - Feature importance visible

4. **Resource Allocation:**
   - Allocation timeline renders
   - Summary metrics accurate

5. **Policy Comparison:**
   - Policy bar chart displays
   - Best policy highlighted

**Test Interactivity:**
- Date range selection updates charts
- Data tables are sortable/filterable
- No errors in console

---

### 8. Validation Suite

**Run Comprehensive Validation:**
```sql
-- Execute full validation
@snowflake/validation_ops.sql

-- Check results
SELECT 
    validation_check,
    status,
    details
FROM OPS.OPS_VALIDATION_SUMMARY
WHERE status IN ('FAIL', 'WARN')
ORDER BY 
    CASE status WHEN 'FAIL' THEN 1 ELSE 2 END;

-- Overall status
SELECT 
    COUNT(*) AS total_checks,
    SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END) AS passed,
    SUM(CASE WHEN status = 'WARN' THEN 1 ELSE 0 END) AS warnings,
    SUM(CASE WHEN status = 'FAIL' THEN 1 ELSE 0 END) AS failures
FROM OPS.OPS_VALIDATION_SUMMARY;
```

**Pass Criteria:**
- 0 FAIL status (critical)
- ≤3 WARN status (acceptable)
- OVERALL_OPS_STATUS = 'PASS'

---

### 9. Full Pipeline Dry Run

**Execute Complete Workflow:**
```bash
cd snowpark
python execute_phase6.py --mode full
```

**Capture KPI Snapshot:**
```sql
-- Prediction metrics
SELECT 
    COUNT(*) AS total_predictions,
    AVG((randomforestregressor_pred + xgbregressor_pred) / 2.0) AS avg_rate,
    MAX(date) AS latest_date
FROM ML.PREDICTIONS;

-- Model metrics
SELECT 
    model_name,
    task,
    val_r2,
    val_f1,
    val_auc
FROM ML.MODEL_RESULTS
ORDER BY task, model_name;

-- Optimization metrics
SELECT 
    total_spoilage_reduction,
    spoilage_reduction_pct,
    budget_used,
    (total_spoilage_reduction / budget_used) AS roi
FROM OPS.OPTIMIZATION_LOGS
ORDER BY created_at DESC
LIMIT 1;

-- Task health
SELECT 
    task_name,
    COUNT(*) AS runs,
    SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) AS successful,
    ROUND(AVG(duration_seconds), 2) AS avg_duration
FROM OPS.TASK_RUNS
GROUP BY task_name;
```

---

### 10. Backup & Documentation

**Create Configuration Backup:**
```bash
# Create backup directory
mkdir -p backups/phase6_$(date +%Y%m%d)

# Backup SQL scripts
cp snowflake/*.sql backups/phase6_$(date +%Y%m%d)/
cp dashboards/*.sql backups/phase6_$(date +%Y%m%d)/

# Backup Python scripts
cp optimization/*.py backups/phase6_$(date +%Y%m%d)/
cp snowpark/execute_phase6.py backups/phase6_$(date +%Y%m%d)/
cp snowpark/monitor_ops.py backups/phase6_$(date +%Y%m%d)/
cp dashboards/streamlit_app.py backups/phase6_$(date +%Y%m%d)/

# Create changelog
cat > backups/phase6_$(date +%Y%m%d)/CHANGELOG.md << 'EOF'
# Phase 6 Deployment - $(date +%Y-%m-%d)

## Components
- Automation (Tasks & Streams)
- Resource Optimization (LP)
- Policy Evaluation
- Interactive Dashboard
- Operational Monitoring

## Validation Status
- All tests: PASS
- Ready for production: YES

## Configuration
- Database: GLOBAL_SPOILAGE_DB
- Warehouse: COMPUTE_WH
- Tasks: 6 enabled
- Streams: 7 active

## Next Steps
- Phase 7 planning
- Production deployment
- Stakeholder training
EOF
```

**Export Configurations:**
```sql
-- Export task definitions
SELECT 
    name,
    state,
    schedule,
    warehouse,
    created_on
FROM INFORMATION_SCHEMA.TASKS
WHERE task_schema = 'OPS';

-- Export optimization parameters
SELECT 
    optimization_run_id,
    method,
    total_budget,
    periods_optimized,
    created_at
FROM OPS.OPTIMIZATION_LOGS;
```

---

## Success Criteria Summary

### Critical Requirements (Must Pass)
- ✓ All 6 tasks defined and enabled
- ✓ All 7 streams created and operational
- ✓ 0 validation failures
- ✓ Optimization ROI ≥ 1.5×
- ✓ Full pipeline executes successfully
- ✓ All models trained (6 total)
- ✓ Predictions available (≥100 records)

### High Priority (Recommended)
- ✓ Task success rate ≥ 90%
- ✓ Stream offset age < 24 hours
- ✓ Spoilage reduction ≥ 30%
- ✓ Budget utilization 70-100%
- ✓ ≤3 validation warnings
- ✓ ≤2 features with drift
- ✓ Dashboard fully functional

### Medium Priority (Nice to Have)
- ✓ Policy evaluations complete
- ✓ Monitoring executed
- ✓ Configuration backups created
- ✓ KPI snapshots captured

---

## Troubleshooting

### Task Failures
```sql
-- Check failed tasks
SELECT task_name, execution_start, error_message
FROM OPS.TASK_RUNS
WHERE status = 'FAILED'
ORDER BY execution_start DESC;

-- Manual execution for debugging
CALL OPS.SP_REFRESH_CORE_DATA();
```

### Stream Issues
```sql
-- Reset stream if stuck
DROP STREAM IF EXISTS OPS.STREAM_RAW_FEDFUNDS;
CREATE STREAM OPS.STREAM_RAW_FEDFUNDS ON TABLE RAW.FEDFUNDS_MONTHLY;
```

### Optimization Failures
```bash
# Check predictions available
python -c "from resource_lp import *; opt = ResourceAllocationOptimizer(); opt.create_session(); opt.load_predictions()"

# Run with debug output
python resource_lp.py 2>&1 | tee optimization_debug.log
```

### Dashboard Not Loading
```bash
# Check dependencies
pip install streamlit plotly pandas snowflake-snowpark-python

# Run with debug
streamlit run streamlit_app.py --logger.level=debug
```

---

## Next Steps After Testing

### If All Tests Pass:
1. Review KPI snapshots and establish baselines
2. Schedule stakeholder demo of dashboard
3. Plan Phase 7 (production hardening, RBAC, secrets rotation)
4. Document any environment-specific configurations
5. Create runbook for operational procedures

### If Tests Fail:
1. Review failure logs in `logs/phase6_readiness_test.log`
2. Address critical failures first
3. Re-run tests after fixes
4. Update documentation with lessons learned
5. Consider extending testing period

---

## Test Execution Log

Use this template to document your test run:

```
Test Date: ______________
Tester: ______________
Environment: ______________

Results:
[ ] Task Infrastructure: ____
[ ] Stream Infrastructure: ____
[ ] Optimization & ROI: ____
[ ] Policy Evaluation: ____
[ ] Monitoring: ____
[ ] Dashboard: ____
[ ] Validation Suite: ____
[ ] Dry Run: ____
[ ] Backup: ____

Overall Status: ______________
Notes:
```

---

## Contact & Support

For issues or questions:
- Review logs in `logs/` directory
- Check `PROJECT_STATUS.md` for project health
- Consult `PHASE6_IMPLEMENTATION_COMPLETE.md` for details
- Reference Snowflake documentation for task/stream issues

---

**Last Updated:** 2025-01-13
**Version:** 1.0
**Status:** Ready for Testing

