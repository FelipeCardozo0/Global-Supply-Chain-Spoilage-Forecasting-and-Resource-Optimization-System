# Phase 1: Database & Data Loading - Quick Start Guide

## 🎯 **Objective**
Create the database structure and load all 8 Kaggle datasets into Snowflake for the Global Supply Chain Spoilage Forecasting project.

## 📋 **Prerequisites**
- ✅ Snowflake account with admin access
- ✅ Python environment with required packages
- ✅ Kaggle API credentials (`kaggle.json`)

## 🚀 **Quick Start (5 Steps)**

### **Step 1: Install Required Packages**
```bash
pip install snowflake-snowpark-python kaggle pandas
```

### **Step 2: Configure Snowflake Connection**
1. Copy the template:
   ```bash
   cp snowflake_config.json.template snowflake_config.json
   ```

2. Edit `snowflake_config.json` with your Snowflake credentials:
   ```json
   {
     "account": "your-account.snowflakecomputing.com",
     "user": "your-username", 
     "password": "your-password",
     "warehouse": "COMPUTE_WH",
     "database": "GLOBAL_SPOILAGE_DB",
     "schema": "RAW",
     "role": "ACCOUNTADMIN"
   }
   ```

### **Step 3: Set Up Kaggle API**
1. Place your `kaggle.json` file in the project root directory
2. Set permissions:
   ```bash
   chmod 600 kaggle.json
   ```

### **Step 4: Run Phase 1**
```bash
cd snowpark
python execute_phase1.py
```

### **Step 5: Verify Success**
Check the logs for:
- ✅ Database and schemas created
- ✅ 8/8 datasets loaded successfully
- ✅ Phase 1 validation passed

## 📊 **What Gets Created**

### **Database Structure:**
```
GLOBAL_SPOILAGE_DB/
├── RAW/          # Raw Kaggle data
├── CORE/         # Cleaned, unified data  
├── FEAT/         # Engineered features
├── ML/           # ML datasets & models
└── OPS/          # Operations & automation
```

### **Loaded Datasets:**
1. **FEDFUNDS** - Federal Funds Rate
2. **RETAIL_SALES** - US Advance Retail Sales  
3. **MACRO_ECONOMIC** - US Economic Indicators 1974-2024
4. **MACRO_FRED** - US Macroeconomic Data 1996-2020
5. **TREASURY** - US Treasury Securities
6. **CLIMATE_CHANGE** - World Bank Climate Data
7. **WDI** - World Development Indicators
8. **WORLD_BANK** - World Bank Data 1960-2016

## 🔍 **Verification Commands**

### **Check Database:**
```sql
USE DATABASE GLOBAL_SPOILAGE_DB;
SHOW SCHEMAS;
```

### **Check Raw Tables:**
```sql
SELECT TABLE_NAME, ROW_COUNT 
FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_SCHEMA = 'RAW';
```

### **Check Audit Log:**
```sql
SELECT * FROM OPS.LOAD_AUDIT 
ORDER BY EXECUTION_TS DESC;
```

## ⚠️ **Troubleshooting**

### **Common Issues:**

1. **"Snowflake config file not found"**
   - Create `snowflake_config.json` from template
   - Verify file is in project root

2. **"Kaggle authentication failed"**
   - Check `kaggle.json` is in project root
   - Verify API key is valid

3. **"Permission denied"**
   - Ensure you have ACCOUNTADMIN role
   - Check warehouse permissions

4. **"Dataset download failed"**
   - Check internet connection
   - Verify Kaggle API quota

### **Log Files:**
- `logs/phase1_execution.log` - Detailed execution log
- Check for specific error messages

## 🎯 **Success Criteria**
- ✅ Database `GLOBAL_SPOILAGE_DB` exists
- ✅ All 5 schemas created (RAW, CORE, FEAT, ML, OPS)
- ✅ 8/8 Kaggle datasets loaded into RAW schema
- ✅ Audit table populated with execution records
- ✅ No errors in logs

## 🚀 **Next Steps**
After Phase 1 completion:
1. **Phase 2:** Build Core Data Model
2. **Phase 3:** Feature Engineering  
3. **Phase 4:** ML Data Preparation
4. **Phase 5:** Model Training
5. **Phase 6:** Operations & Testing

---

**Estimated Time:** 10-15 minutes  
**Cost:** ~$0.02 (small warehouse)  
**Status:** Ready to execute
