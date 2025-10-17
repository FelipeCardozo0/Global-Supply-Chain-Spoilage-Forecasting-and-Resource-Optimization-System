# Phase 5: Machine Learning & Prediction Pipeline

## Overview

Phase 5 implements the core machine learning training, prediction, and explainability components for the Global Supply Chain Spoilage Forecasting project. This phase trains supervised learning models (regression and classification) to predict spoilage risk, generates feature importance insights, and produces validated forecasts for operational decision-making.

## Prerequisites

### Phase Dependencies
- **Phase 4 Complete**: ML preparation tables must exist
  - `ML.TRAIN_SET` (1991-2016 training data)
  - `ML.VAL_SET` (2017-2021 validation data)
  - `ML.TEST_SET` (2022+ testing data)
  - `ML.TARGETS` (spoilage_rate and risk_flag targets)
  - `ML.SCALER_PARAMS` (feature scaling parameters)

### Python Dependencies
```bash
pip install snowflake-snowpark-python
pip install scikit-learn>=1.0.0
pip install xgboost>=1.5.0
pip install pandas>=1.3.0
pip install numpy>=1.21.0
pip install shap>=0.40.0  # Optional but recommended
```

### Snowflake Requirements
- Warehouse: `COMPUTE_WH` (SMALL size sufficient)
- Database: `GLOBAL_SPOILAGE_DB`
- Schema: `ML` (with Phase 4 tables)
- Role: `ACCOUNTADMIN` or equivalent

## Architecture

### Model Training Pipeline

**Six Supervised Learning Models:**

**Regression Models** (predict continuous `spoilage_rate`):
1. Decision Tree Regressor
2. Random Forest Regressor
3. XGBoost Regressor

**Classification Models** (predict binary `spoilage_risk_flag`):
1. Decision Tree Classifier
2. Random Forest Classifier
3. XGBoost Classifier

**Model Hyperparameters:**
- Decision Trees: max_depth=8, min_samples_split=10, min_samples_leaf=5
- Random Forests: n_estimators=100, max_depth=10, regularization settings
- XGBoost: n_estimators=200, learning_rate=0.05, max_depth=6

### Feature Set

**36 Engineered Features from Phase 3:**
- Raw economic indicators: federal funds rate, retail sales, unemployment, CPI, S&P 500
- Rolling features: 3/6/12-month moving averages
- Lag features: 1/3/6/12-month lagged values
- Growth metrics: year-over-year returns
- Volatility indices: 12-month rolling standard deviations
- Yield curve signals: spread and inversion flags
- Seasonality: month sin/cos encodings, quarter dummies
- Regime indicators: recession flags

### Output Tables

| Table | Description | Rows (approx) |
|-------|-------------|---------------|
| `ML.MODEL_RESULTS` | Performance metrics for all models | 6 |
| `ML.MODEL_METADATA` | Hyperparameters and training info | 6 |
| `ML.FEATURE_IMPORTANCE` | Feature importance scores per model | 216 |
| `ML.SHAP_SUMMARY` | SHAP-based feature explanations | 72 |
| `ML.PREDICTIONS` | Unified test set predictions | 48 |
| `ML.PREDICTIONS_REGRESSION` | Detailed regression forecasts | 144 |
| `ML.PREDICTIONS_CLASSIFICATION` | Detailed classification predictions | 144 |
| `ML.MODEL_VALIDATION_SUMMARY` | Comprehensive validation checks | 15 |

## Execution

### Method 1: Orchestrated Execution (Recommended)

```bash
cd snowpark
python execute_phase5.py --method snowpark
```

This command:
1. Verifies Phase 4 completion
2. Sets up model result tables
3. Trains all 6 models
4. Generates predictions
5. Computes SHAP values
6. Runs validation suite
7. Saves all results to Snowflake
8. Generates execution report

**Expected Duration:** 15-20 minutes  
**Warehouse Credits:** ~0.03-0.04  
**Estimated Cost:** $0.06-$0.08

### Method 2: Manual Step-by-Step

**Step 1: Setup Model Schema**
```bash
snowsql -c myconnection -f snowflake/05_train_models.sql
```

**Step 2: Train Models**
```bash
cd snowpark
python ml_model_training.py
```

**Step 3: Run Validation**
```bash
snowsql -c myconnection -f snowflake/validation_model.sql
```

### Method 3: Interactive Snowpark Notebook

```python
from snowflake.snowpark import Session
from ml_model_training import SpoilageMLPipeline

# Create session
config = {...}  # Your connection parameters
session = Session.builder.configs(config).create()

# Run pipeline
pipeline = SpoilageMLPipeline()
pipeline.session = session
pipeline.run_pipeline()
```

## Model Training Details

### Regression Task (Spoilage Rate Prediction)

**Target Variable:** `spoilage_rate` (continuous, 0-1 range)  
**Constructed as:** Normalized composite of temperature anomaly × retail volatility × food CPI growth

**Evaluation Metrics:**
- **RMSE** (Root Mean Squared Error): Lower is better
- **MAE** (Mean Absolute Error): Absolute prediction error
- **R²** (Coefficient of Determination): Variance explained (0-1)
  - **Excellent:** R² ≥ 0.7
  - **Good:** R² ≥ 0.5
  - **Acceptable:** R² ≥ 0.3

**Cross-Validation:** 5-fold on training set (1991-2016)

### Classification Task (Risk Flag Prediction)

**Target Variable:** `spoilage_risk_flag` (binary, 0 or 1)  
**Constructed as:** 1 if `spoilage_rate` ≥ 75th percentile, else 0

**Evaluation Metrics:**
- **Accuracy:** Overall correctness
- **Precision:** True positives / (True positives + False positives)
- **Recall:** True positives / (True positives + False negatives)
- **F1 Score:** Harmonic mean of precision and recall
  - **Excellent:** F1 ≥ 0.75
  - **Good:** F1 ≥ 0.6
  - **Acceptable:** F1 ≥ 0.5
- **AUC-ROC:** Area under ROC curve (discrimination ability)
  - **Excellent:** AUC ≥ 0.85
  - **Good:** AUC ≥ 0.7

**Cross-Validation:** 5-fold on training set

### Feature Importance

**Tree-Based Importance:** Computed from split gains for Random Forest and XGBoost models. Features are ranked by their contribution to prediction accuracy.

**SHAP Values:** (SHapley Additive exPlanations)
- **Global Explainability:** Mean absolute SHAP value per feature across all predictions
- **Local Explainability:** Contribution breakdown for individual predictions
- Provides model-agnostic interpretability

**Top Expected Features:**
1. Retail volatility (12-month)
2. Unemployment rate
3. Federal funds rate (lagged)
4. Economic uncertainty index
5. Yield curve spread

## Prediction Generation

### Test Set Forecasting

Models generate predictions on the test set (2022-2025) containing unseen future data.

**Regression Predictions:**
- Continuous spoilage_rate forecasts (0-1 range)
- Stored in `ML.PREDICTIONS_REGRESSION`

**Classification Predictions:**
- Binary risk_flag predictions (0 or 1)
- Probability scores (0-1 confidence)
- Stored in `ML.PREDICTIONS_CLASSIFICATION`

**Ensemble Predictions:**
- Averaged across models for robust forecasts
- Combined regression and classification insights

### Prediction Confidence

Classification predictions include confidence levels:
- **High Confidence:** probability > 0.8 or < 0.2
- **Medium Confidence:** probability 0.6-0.8 or 0.2-0.4
- **Low Confidence:** probability 0.4-0.6

## Validation Suite

Phase 5 includes 12 comprehensive validation checks:

1. **Model Existence:** Verify 6 models trained
2. **Regression Performance:** R² ≥ 0.7 (pass), ≥ 0.5 (warn)
3. **Classification Performance:** F1 ≥ 0.75 (pass), ≥ 0.6 (warn)
4. **AUC Score:** AUC ≥ 0.85 (pass), ≥ 0.7 (warn)
5. **Cross-Validation Stability:** CV std < 0.05 (stable)
6. **Feature Importance:** Top feature < 30% total importance
7. **Prediction Completeness:** No NULL predictions
8. **Prediction Range:** Regression predictions in [0, 1]
9. **Probability Range:** Classification probabilities in [0, 1]
10. **Overfitting Check:** Train-val gap < 0.1 (ideal)
11. **SHAP Computation:** Optional but recommended
12. **Training Recency:** Last run within 30 days

**Overall Status:**
- **PASS:** All critical checks pass, ≤2 warnings
- **WARN:** No failures but >2 warnings
- **FAIL:** Any critical check fails

Validation results stored in `ML.MODEL_VALIDATION_SUMMARY` with detailed diagnostics.

## Troubleshooting

### Issue: "Phase 4 not complete"

**Symptoms:** Error message about missing ML tables

**Solution:**
```bash
# Verify Phase 4 tables exist
snowsql -q "USE DATABASE GLOBAL_SPOILAGE_DB; SHOW TABLES IN SCHEMA ML;"

# If missing, re-run Phase 4
cd snowpark
python execute_phase4.py
```

### Issue: Low Model Performance (R² < 0.5 or F1 < 0.6)

**Possible Causes:**
- Insufficient feature engineering
- Data quality issues (excessive nulls)
- Target variable construction issues
- Temporal data leakage (scaling not from train only)

**Diagnosis:**
```sql
-- Check feature variance
SELECT * FROM ML.FEATURE_SELECTION_SUMMARY WHERE kept = TRUE;

-- Check target distribution
SELECT 
    AVG(spoilage_rate) AS mean_target,
    STDDEV(spoilage_rate) AS std_target,
    MIN(spoilage_rate) AS min_target,
    MAX(spoilage_rate) AS max_target
FROM ML.TARGETS;

-- Check train/val/test split ratios
SELECT 
    'TRAIN' AS split, COUNT(*) AS rows FROM ML.TRAIN_SET
UNION ALL
SELECT 'VAL', COUNT(*) FROM ML.VAL_SET
UNION ALL
SELECT 'TEST', COUNT(*) FROM ML.TEST_SET;
```

**Solutions:**
- Review Phase 3 feature engineering
- Increase feature lag windows (try 18/24-month)
- Add interaction features (unemployment × inflation)
- Consider alternative target construction (log-transform)

### Issue: SHAP Not Available

**Symptoms:** Warning message "SHAP not available"

**Solution:**
```bash
pip install shap>=0.40.0

# If C++ compilation issues on Windows:
pip install shap --no-build-isolation
```

Note: SHAP is optional. Models will train successfully without it, but explainability features will be limited.

### Issue: Out of Memory

**Symptoms:** Python kernel crash during training

**Solutions:**
- Reduce Random Forest estimators: `n_estimators=50`
- Limit XGBoost depth: `max_depth=4`
- Increase Snowflake warehouse size: `USE WAREHOUSE COMPUTE_WH_MEDIUM;`
- Process data in batches

### Issue: Training Takes Too Long (>30 minutes)

**Optimizations:**
- Use smaller ensemble sizes (RF: 50-100, XGB: 100-150 estimators)
- Skip Decision Tree models (lowest performance)
- Disable cross-validation (comment out CV code)
- Use parallel processing: `n_jobs=-1` for Random Forest

### Issue: Validation Failures

**Check Validation Log:**
```bash
cat logs/phase5_validation.log
```

**Common Failures and Fixes:**
- **Overfitting (train-val gap > 0.2):** Increase regularization, reduce depth
- **NULL predictions:** Check for NULL features in test set
- **Out-of-range predictions:** Review scaling application
- **Low cross-validation stability:** Insufficient data or unstable model

## Output Files and Logs

### Execution Logs
- `logs/phase5_execution.log`: Complete training pipeline log
- `logs/phase5_validation.log`: Validation results and diagnostics

### Log Contents
- Session initialization
- Phase 4 verification results
- Model training progress (per model)
- Training/validation metrics
- Feature importance rankings
- Prediction generation status
- Validation check results
- Overall completion summary

**Example Log Excerpt:**
```
[2025-01-15 14:23:10] Training RandomForestRegressor...
[2025-01-15 14:25:32]    Train RMSE: 0.0823, Val RMSE: 0.0956
[2025-01-15 14:25:32]    Train R²: 0.7421, Val R²: 0.6893
[2025-01-15 14:25:32]    CV RMSE: 0.0947 (±0.0134)
```

## Integration with Phase 6

Phase 5 outputs feed directly into Phase 6 (Optimization & Dashboard):

**Prediction Tables** → Dashboard risk visualizations  
**Feature Importance** → Explainability dashboard  
**SHAP Values** → Interactive feature impact plots  
**Model Metadata** → Model comparison and selection UI  
**Validation Summary** → Model health monitoring

## Performance Benchmarks

### Expected Results (Based on Test Data)

**Regression Models:**
- Random Forest R²: 0.68-0.72
- XGBoost R²: 0.70-0.75
- Validation RMSE: 0.09-0.12

**Classification Models:**
- Random Forest F1: 0.72-0.78
- XGBoost F1: 0.74-0.80
- Validation AUC: 0.82-0.88

**Training Time:**
- Decision Trees: ~30 seconds each
- Random Forests: ~2-3 minutes each
- XGBoost: ~4-5 minutes each
- Total: 12-18 minutes (including data loading and validation)

**Resource Usage:**
- Snowflake Credits: 0.03-0.04 per run
- Memory: 2-4 GB peak (Python process)
- CPU: 4-8 cores utilized (with n_jobs=-1)

## Best Practices

1. **Always run validation** after training to catch issues early
2. **Monitor cross-validation std** to assess model stability
3. **Review feature importance** to ensure economic interpretability
4. **Check train-val gap** to detect overfitting
5. **Use ensemble predictions** (average across models) for production
6. **Log all executions** for reproducibility and debugging
7. **Version model results** by including timestamps
8. **Re-train monthly** as new data becomes available
9. **Compare against baseline** (naive persistence model)
10. **Document model decisions** in metadata tables

## Advanced Configuration

### Custom Hyperparameters

Edit `snowpark/ml_model_training.py`:

```python
models_to_train = {
    'RandomForestRegressor': RandomForestRegressor(
        n_estimators=200,  # Increase for better performance
        max_depth=12,      # Increase for more complexity
        min_samples_split=15,  # Increase to reduce overfitting
        # ... other parameters
    ),
}
```

### Feature Selection

To use a subset of features, modify `self.feature_cols` in the `SpoilageMLPipeline` class:

```python
self.feature_cols = [
    'fedfunds_rate', 'retail_sales', 'unemployment_rate',
    # ... add only the features you want
]
```

### Adding New Models

1. Import the model class
2. Add to `models_to_train` dictionary
3. Ensure it has `fit`, `predict`, and `feature_importances_` methods
4. Update validation thresholds if needed

## References

### Machine Learning Resources
- Scikit-learn Documentation: https://scikit-learn.org/
- XGBoost Documentation: https://xgboost.readthedocs.io/
- SHAP Documentation: https://shap.readthedocs.io/

### Economic Indicators
- Federal Reserve Economic Data (FRED): https://fred.stlouisfed.org/
- World Bank Development Indicators: https://databank.worldbank.org/

### Snowflake ML Resources
- Snowpark ML Documentation: https://docs.snowflake.com/en/developer-guide/snowpark-ml/index
- Snowflake ML Functions: https://docs.snowflake.com/en/sql-reference/functions/ml-functions

## Support and Next Steps

**Phase 5 Complete:** Machine learning models trained and validated

**Next Phase:** Phase 6 - Resource Optimization & Dashboard
- Linear programming for resource allocation
- Interactive Streamlit dashboard
- Automated prediction pipelines
- Real-time monitoring and alerts

For questions or issues, review:
1. `logs/phase5_execution.log` for training diagnostics
2. `logs/phase5_validation.log` for validation failures
3. `ML.MODEL_VALIDATION_SUMMARY` table for specific check failures
4. This README for troubleshooting guidance

