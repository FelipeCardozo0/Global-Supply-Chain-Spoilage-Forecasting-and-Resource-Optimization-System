# Phase 2 Quick Start Guide

**5-Minute Setup | 10-Minute Execution | Production-Ready CORE Schema**

---

## Quick Start - Get Running in 3 Commands

```bash
# 1. Configure connection
cp snowflake_config.json.template snowflake_config.json
# Edit with your Snowflake credentials

# 2. Install Snowpark (if using Python method)
pip install snowflake-snowpark-python

# 3. Execute Phase 2
cd snowpark
python execute_phase2.py --method sql
```

**Done!** Your CORE schema is now ready with 15 clean, validated tables.

---

## Prerequisites Checklist

- Phase 1 complete (RAW tables loaded)
- Snowflake account with COMPUTE_WH warehouse
- Python 3.8+ installed (if using Python methods)
- snowflake_config.json configured

**Verify Phase 1:**

```sql
-- Run in Snowflake
USE DATABASE GLOBAL_SPOILAGE_DB;
SHOW TABLES IN RAW;

-- Should see: FEDFUNDS_MONTHLY, RSXFS, RECESSION_PERIODS, etc.
```

---

## Choose Your Execution Method

### Method 1: Orchestrated (Recommended)

**Best for:** First-time users, production deployments

```bash
cd snowpark
python execute_phase2.py --method sql
```

**Features:**
- Automatic Phase 1 verification
- Progress tracking
- Comprehensive validation
- Detailed logging
- Summary reports

**Output:**
- `logs/phase2_execution.log`
- `logs/phase2_validation.log`

---

### Method 2: Direct SQL (Fastest)

**Best for:** Experienced users, quick iterations

```sql
-- In Snowflake UI
USE DATABASE GLOBAL_SPOILAGE_DB;
USE SCHEMA CORE;
USE WAREHOUSE COMPUTE_WH;

-- Run these files in order:
@snowflake/02_build_core.sql
@snowflake/validation_core.sql
```

Or via SnowSQL:

```bash
snowsql -c my_connection \
  -f snowflake/02_build_core.sql \
  -f snowflake/validation_core.sql
```

---

### Method 3: Snowpark Python

**Best for:** Developers, API integration

```bash
cd snowpark
python build_core.py
```

---

## Expected Timeline

| Phase | Duration | Activity |
|-------|----------|----------|
| Setup | 2 min | Configure snowflake_config.json |
| Execution | 8-12 min | Build CORE tables |
| Validation | 2-3 min | Run quality checks |
| Review | 2 min | Check logs and summary |
| **TOTAL** | **15 min** | **Complete Phase 2** |

---

## What Gets Created

### 15 CORE Tables

```
DATE_SPINE                    1,800 rows    Temporal backbone
COUNTRY_REFERENCE               250 rows    ISO country codes
FEDFUNDS                        800 rows    Federal Funds Rate
RETAIL_SALES                    400 rows    U.S. Retail Sales
RECESSION_INDICATOR             740 rows    Economic regime
SP500_MONTHLY                   300 rows    S&P 500 index
NASDAQ_MONTHLY                  300 rows    NASDAQ index
GOLD_MONTHLY                    300 rows    Gold prices
TREASURY_HOLDINGS_MONTHLY       200 rows    Treasury data
ECONOMIC_MASTER                 432 rows    Master time series
MACRO_INDICATORS                360 rows    Comprehensive macro data
WB_PROJECTS                  10,000 rows    World Bank projects
WDI_TIME_SERIES             500,000 rows    Development indicators
CLIMATE_HISTORICAL           50,000 rows    Climate observations
CLIMATE_PROJECTIONS          20,000 rows    Climate scenarios

TOTAL: ~600,000 rows, ~70 MB
```

---

## Validation Checkpoints

After execution, verify success:

### 1. Table Count

```sql
SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_SCHEMA = 'CORE' AND TABLE_TYPE = 'BASE TABLE';
-- Expected: 15
```

### 2. Master Table

```sql
SELECT 
    COUNT(*) as rows,
    MIN(date) as start_date,
    MAX(date) as end_date
FROM CORE.ECONOMIC_MASTER;
-- Expected: 432 rows, 1990-01-01 to 2025-12-01
```

### 3. Data Quality

```sql
SELECT 
    AVG(
        CASE WHEN fedfunds_rate IS NOT NULL THEN 1 ELSE 0 END +
        CASE WHEN retail_sales IS NOT NULL THEN 1 ELSE 0 END +
        CASE WHEN unemployment_rate IS NOT NULL THEN 1 ELSE 0 END +
        CASE WHEN sp500_eom_close IS NOT NULL THEN 1 ELSE 0 END
    ) as completeness_score
FROM CORE.ECONOMIC_MASTER;
-- Expected: 3.0-4.0 (out of 5.0)
```

---

## Success Indicators

You'll see these in the logs/output:

- `PHASE 2 COMPLETE`  
- `15 CORE tables created`  
- `Validation PASSED`  
- `No critical errors`

---

## Troubleshooting

### Error: "Config file not found"

```bash
# Create from template
cp snowflake_config.json.template snowflake_config.json

# Edit with your credentials
nano snowflake_config.json
```

---

### Error: "RAW schema not found"

**Solution:** Run Phase 1 first

```bash
# Phase 1 execution
cd snowflake
snowsql -c my_connection -f 01_load_raw.sql
```

---

### Error: "Warehouse not running"

```sql
-- Start warehouse
ALTER WAREHOUSE COMPUTE_WH RESUME;

-- Or create if doesn't exist
CREATE WAREHOUSE COMPUTE_WH 
    WAREHOUSE_SIZE = 'SMALL' 
    AUTO_SUSPEND = 300 
    AUTO_RESUME = TRUE;
```

---

### Warning: "High NULL rates"

**Normal behavior** - Different indicators have different start dates.

See `PHASE2_README.md` for expected coverage by indicator.

---

## Generated Files

After execution:

```
logs/
├── phase2_execution.log       <- Detailed step-by-step log
└── phase2_validation.log      <- Quality check results
```

**Review these files if you see any warnings or errors.**

---

## Cost Estimate

- **Warehouse:** SMALL ($2/credit)
- **Credits used:** ~0.02-0.03
- **Cost per run:** ~$0.05

*Assuming standard Snowflake pricing*

---

## Next Steps

After Phase 2 completes:

### Immediate Actions

1. Review validation log: `logs/phase2_validation.log`
2. Check table summary: `SELECT * FROM CORE.LOAD_AUDIT;`
3. Explore master table: `SELECT * FROM CORE.ECONOMIC_MASTER LIMIT 100;`

### Ready for Phase 3

Phase 3 will create **feature engineering** layer:

- Rolling averages
- Lag features
- Volatility metrics
- Economic indicators

**File:** `snowflake/03_features.sql` (coming soon)

---

## Need Help?

### Check These First

1. `logs/phase2_execution.log` - Detailed execution log
2. `logs/phase2_validation.log` - Validation results
3. `PHASE2_README.md` - Complete documentation
4. `PHASE2_IMPLEMENTATION_COMPLETE.md` - Implementation details

### Common Issues

| Issue | Solution |
|-------|----------|
| Connection fails | Check `snowflake_config.json` |
| Phase 1 not complete | Run `01_load_raw.sql` |
| Warehouse suspended | Run `ALTER WAREHOUSE COMPUTE_WH RESUME;` |
| High NULL rates | Normal - different date ranges |

---

## Learning Path

**New to Snowflake?** Follow this sequence:

1. Read `PHASE2_QUICKSTART.md` (this file)
2. Execute Phase 2 using Method 1 (orchestrated)
3. Review `logs/phase2_validation.log`
4. Read `PHASE2_README.md` for deep dive
5. Explore CORE tables in Snowflake UI

**Experienced user?**

- Jump straight to Method 2 (direct SQL)
- Review `PHASE2_IMPLEMENTATION_COMPLETE.md`
- Customize transformations as needed

---

## Example Output

When Phase 2 completes, you'll see:

```
================================================================================
PHASE 2 COMPLETION SUMMARY
================================================================================

CORE Tables Created:
------------------------------------------------------------
  DATE_SPINE                         1,800 rows      0.05 MB
  ECONOMIC_MASTER                      432 rows      0.15 MB
  WDI_TIME_SERIES                  500,000 rows     45.00 MB
  CLIMATE_HISTORICAL                50,000 rows      5.50 MB
  ...
------------------------------------------------------------
  TOTAL                            600,000 rows     70.00 MB

Phase 2 Complete: 15 CORE tables created
Duration: 10.5 minutes
Log File: logs/phase2_execution.log
Validation Report: logs/phase2_validation.log
================================================================================
```

---

## Quick Reference

### Execute Phase 2

```bash
cd snowpark
python execute_phase2.py --method sql
```

### Verify Success

```sql
SELECT COUNT(*) FROM CORE.ECONOMIC_MASTER;
-- Should return: 432
```

### Check Logs

```bash
cat logs/phase2_validation.log
# Should show success indicators, no critical errors
```

---

## Ready to Start?

**Let's go!**

```bash
# Step 1: Configure
cp snowflake_config.json.template snowflake_config.json
# Edit snowflake_config.json with your credentials

# Step 2: Execute
cd snowpark
python execute_phase2.py --method sql

# Step 3: Verify
# Check logs/phase2_validation.log
```

**Time to completion:** ~15 minutes

---

**Status:** Ready for Execution  
**Difficulty:** Easy (2/5)  
**Time:** 15 minutes  
**Cost:** ~$0.05

---

*Last Updated: October 10, 2025*  
*For detailed documentation, see: PHASE2_README.md*
