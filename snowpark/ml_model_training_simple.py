"""
Phase 5: Machine Learning Model Training - Simplified
Global Supply Chain Spoilage Forecasting Project
Trains models with sample data for demonstration
"""

import json
import logging
import pandas as pd
import numpy as np
from pathlib import Path
from snowflake.snowpark import Session
from sklearn.ensemble import RandomForestRegressor, RandomForestClassifier
from sklearn.tree import DecisionTreeRegressor, DecisionTreeClassifier
from sklearn.metrics import mean_squared_error, r2_score, accuracy_score, precision_score, recall_score, f1_score
import xgboost as xgb

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/phase5_ml_training.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

def create_logs_directory():
    """Create logs directory if it doesn't exist"""
    Path('logs').mkdir(exist_ok=True)

def load_snowflake_config():
    """Load Snowflake configuration"""
    config_path = 'snowflake_config.json'
    if not Path(config_path).exists():
        logger.error(f"Snowflake config file not found: {config_path}")
        return None
    
    with open(config_path, 'r') as f:
        config = json.load(f)
    
    return config

def create_sample_data(session):
    """Create sample training data for demonstration"""
    logger.info("Creating sample training data...")
    
    # Create sample data with realistic patterns
    np.random.seed(42)
    n_samples = 1000
    
    # Generate sample features
    sample_data = {
        'DATE_COL': pd.date_range('2020-01-01', periods=n_samples, freq='D'),
        'FEDFUNDS_RATE': np.random.normal(2.5, 1.0, n_samples),
        'RETAIL_SALES': np.random.normal(500, 50, n_samples),
        'TREASURY_10Y_RATE': np.random.normal(3.0, 0.5, n_samples),
        'FEDFUNDS_3M_AVG': np.random.normal(2.5, 0.8, n_samples),
        'RETAIL_3M_AVG': np.random.normal(500, 40, n_samples),
        'TREASURY_3M_AVG': np.random.normal(3.0, 0.4, n_samples),
        'FEDFUNDS_LAG_1M': np.random.normal(2.5, 0.9, n_samples),
        'RETAIL_LAG_1M': np.random.normal(500, 45, n_samples),
        'TREASURY_LAG_1M': np.random.normal(3.0, 0.5, n_samples),
        'FEDFUNDS_GROWTH_1M': np.random.normal(0.0, 0.1, n_samples),
        'RETAIL_GROWTH_1M': np.random.normal(0.0, 0.05, n_samples),
        'TREASURY_GROWTH_1M': np.random.normal(0.0, 0.08, n_samples),
        'FEDFUNDS_VOLATILITY_3M': np.random.normal(0.1, 0.05, n_samples),
        'RETAIL_VOLATILITY_3M': np.random.normal(0.1, 0.05, n_samples),
        'TREASURY_VOLATILITY_3M': np.random.normal(0.1, 0.05, n_samples)
    }
    
    # Create target variables
    spoilage_rate = (sample_data['RETAIL_VOLATILITY_3M'] * 
                    sample_data['FEDFUNDS_3M_AVG'] * 
                    sample_data['TREASURY_GROWTH_1M'] + 
                    np.random.normal(0, 0.01, n_samples))
    
    spoilage_risk_flag = (spoilage_rate > np.percentile(spoilage_rate, 75)).astype(int)
    
    sample_data['SPOILAGE_RATE'] = spoilage_rate
    sample_data['SPOILAGE_RISK_FLAG'] = spoilage_risk_flag
    
    # Create DataFrame
    df = pd.DataFrame(sample_data)
    
    # Split into train/val/test
    train_size = int(0.7 * n_samples)
    val_size = int(0.15 * n_samples)
    
    train_df = df[:train_size]
    val_df = df[train_size:train_size + val_size]
    test_df = df[train_size + val_size:]
    
    # Save to Snowflake
    logger.info("Saving sample data to Snowflake...")
    
    # Clear existing tables
    session.sql("TRUNCATE TABLE ML.TRAIN_SET").collect()
    session.sql("TRUNCATE TABLE ML.VAL_SET").collect()
    session.sql("TRUNCATE TABLE ML.TEST_SET").collect()
    
    # Convert to Snowpark DataFrames and save
    train_snowpark = session.create_dataframe(train_df)
    train_snowpark.write.mode("append").save_as_table("ML.TRAIN_SET")
    
    val_snowpark = session.create_dataframe(val_df)
    val_snowpark.write.mode("append").save_as_table("ML.VAL_SET")
    
    test_snowpark = session.create_dataframe(test_df)
    test_snowpark.write.mode("append").save_as_table("ML.TEST_SET")
    
    logger.info(f"Sample data created: {len(train_df)} train, {len(val_df)} val, {len(test_df)} test")
    return train_df, val_df, test_df

def train_models(train_df, val_df, test_df):
    """Train machine learning models"""
    logger.info("Training machine learning models...")
    
    # Prepare features
    feature_cols = [
        'FEDFUNDS_RATE', 'RETAIL_SALES', 'TREASURY_10Y_RATE',
        'FEDFUNDS_3M_AVG', 'RETAIL_3M_AVG', 'TREASURY_3M_AVG',
        'FEDFUNDS_LAG_1M', 'RETAIL_LAG_1M', 'TREASURY_LAG_1M',
        'FEDFUNDS_GROWTH_1M', 'RETAIL_GROWTH_1M', 'TREASURY_GROWTH_1M',
        'FEDFUNDS_VOLATILITY_3M', 'RETAIL_VOLATILITY_3M', 'TREASURY_VOLATILITY_3M'
    ]
    
    X_train = train_df[feature_cols].fillna(0)
    y_train_reg = train_df['SPOILAGE_RATE'].fillna(0)
    y_train_clf = train_df['SPOILAGE_RISK_FLAG'].fillna(0)
    
    X_val = val_df[feature_cols].fillna(0)
    y_val_reg = val_df['SPOILAGE_RATE'].fillna(0)
    y_val_clf = val_df['SPOILAGE_RISK_FLAG'].fillna(0)
    
    X_test = test_df[feature_cols].fillna(0)
    y_test_reg = test_df['SPOILAGE_RATE'].fillna(0)
    y_test_clf = test_df['SPOILAGE_RISK_FLAG'].fillna(0)
    
    logger.info(f"Training features: {X_train.shape}")
    logger.info(f"Validation features: {X_val.shape}")
    logger.info(f"Test features: {X_test.shape}")
    
    # Train regression models
    logger.info("Training regression models...")
    
    # Decision Tree Regression
    dt_reg = DecisionTreeRegressor(random_state=42)
    dt_reg.fit(X_train, y_train_reg)
    dt_reg_pred = dt_reg.predict(X_val)
    dt_reg_r2 = r2_score(y_val_reg, dt_reg_pred)
    dt_reg_rmse = np.sqrt(mean_squared_error(y_val_reg, dt_reg_pred))
    
    # Random Forest Regression
    rf_reg = RandomForestRegressor(n_estimators=100, random_state=42)
    rf_reg.fit(X_train, y_train_reg)
    rf_reg_pred = rf_reg.predict(X_val)
    rf_reg_r2 = r2_score(y_val_reg, rf_reg_pred)
    rf_reg_rmse = np.sqrt(mean_squared_error(y_val_reg, rf_reg_pred))
    
    # XGBoost Regression
    xgb_reg = xgb.XGBRegressor(random_state=42)
    xgb_reg.fit(X_train, y_train_reg)
    xgb_reg_pred = xgb_reg.predict(X_val)
    xgb_reg_r2 = r2_score(y_val_reg, xgb_reg_pred)
    xgb_reg_rmse = np.sqrt(mean_squared_error(y_val_reg, xgb_reg_pred))
    
    # Train classification models
    logger.info("Training classification models...")
    
    # Decision Tree Classification
    dt_clf = DecisionTreeClassifier(random_state=42)
    dt_clf.fit(X_train, y_train_clf)
    dt_clf_pred = dt_clf.predict(X_val)
    dt_clf_acc = accuracy_score(y_val_clf, dt_clf_pred)
    dt_clf_f1 = f1_score(y_val_clf, dt_clf_pred)
    
    # Random Forest Classification
    rf_clf = RandomForestClassifier(n_estimators=100, random_state=42)
    rf_clf.fit(X_train, y_train_clf)
    rf_clf_pred = rf_clf.predict(X_val)
    rf_clf_acc = accuracy_score(y_val_clf, rf_clf_pred)
    rf_clf_f1 = f1_score(y_val_clf, rf_clf_pred)
    
    # XGBoost Classification
    xgb_clf = xgb.XGBClassifier(random_state=42)
    xgb_clf.fit(X_train, y_train_clf)
    xgb_clf_pred = xgb_clf.predict(X_val)
    xgb_clf_acc = accuracy_score(y_val_clf, xgb_clf_pred)
    xgb_clf_f1 = f1_score(y_val_clf, xgb_clf_pred)
    
    # Generate predictions on test set
    logger.info("Generating predictions on test set...")
    
    test_predictions = []
    for model_name, model in [('DT_REG', dt_reg), ('RF_REG', rf_reg), ('XGB_REG', xgb_reg)]:
        pred = model.predict(X_test)
        for i, (idx, row) in enumerate(test_df.iterrows()):
            test_predictions.append({
                'DATE_COL': row['DATE_COL'],
                'MODEL_NAME': model_name,
                'PREDICTION_TYPE': 'regression',
                'PREDICTED_VALUE': float(pred[i]),
                'ACTUAL_VALUE': float(y_test_reg.iloc[i])
            })
    
    for model_name, model in [('DT_CLF', dt_clf), ('RF_CLF', rf_clf), ('XGB_CLF', xgb_clf)]:
        pred = model.predict(X_test)
        pred_proba = model.predict_proba(X_test)[:, 1] if hasattr(model, 'predict_proba') else pred
        for i, (idx, row) in enumerate(test_df.iterrows()):
            test_predictions.append({
                'DATE_COL': row['DATE_COL'],
                'MODEL_NAME': model_name,
                'PREDICTION_TYPE': 'classification',
                'PREDICTED_VALUE': float(pred[i]),
                'PREDICTED_PROBABILITY': float(pred_proba[i]),
                'ACTUAL_VALUE': float(y_test_clf.iloc[i])
            })
    
    return {
        'regression_models': {
            'DecisionTree': {'r2': dt_reg_r2, 'rmse': dt_reg_rmse},
            'RandomForest': {'r2': rf_reg_r2, 'rmse': rf_reg_rmse},
            'XGBoost': {'r2': xgb_reg_r2, 'rmse': xgb_reg_rmse}
        },
        'classification_models': {
            'DecisionTree': {'accuracy': dt_clf_acc, 'f1': dt_clf_f1},
            'RandomForest': {'accuracy': rf_clf_acc, 'f1': rf_clf_f1},
            'XGBoost': {'accuracy': xgb_clf_acc, 'f1': xgb_clf_f1}
        },
        'test_predictions': test_predictions
    }

def save_results_to_snowflake(session, results):
    """Save model results and predictions to Snowflake"""
    logger.info("Saving results to Snowflake...")
    
    # Save model results
    model_results = []
    for model_type, models in [('regression', results['regression_models']), 
                              ('classification', results['classification_models'])]:
        for model_name, metrics in models.items():
            model_results.append({
                'MODEL_NAME': model_name,
                'MODEL_TYPE': model_type,
                'METRICS': json.dumps(metrics),
                'CREATED_AT': pd.Timestamp.now()
            })
    
    # Save to Snowflake
    results_df = pd.DataFrame(model_results)
    results_snowpark = session.create_dataframe(results_df)
    results_snowpark.write.mode("overwrite").save_as_table("ML.MODEL_RESULTS")
    
    # Save predictions
    if results['test_predictions']:
        pred_df = pd.DataFrame(results['test_predictions'])
        pred_snowpark = session.create_dataframe(pred_df)
        pred_snowpark.write.mode("overwrite").save_as_table("ML.PREDICTIONS")
    
    logger.info("Results saved to Snowflake successfully")

def main():
    """Main execution function"""
    create_logs_directory()
    
    logger.info("=" * 60)
    logger.info("PHASE 5: MACHINE LEARNING MODEL TRAINING")
    logger.info("=" * 60)
    
    # Load Snowflake configuration
    config = load_snowflake_config()
    if not config:
        return
    
    # Create Snowflake session
    try:
        session = Session.builder.configs(config).create()
        logger.info("Connected to Snowflake")
    except Exception as e:
        logger.error(f"Failed to connect to Snowflake: {str(e)}")
        return
    
    try:
        # Create sample data
        train_df, val_df, test_df = create_sample_data(session)
        
        # Train models
        results = train_models(train_df, val_df, test_df)
        
        # Save results
        save_results_to_snowflake(session, results)
        
        # Log results
        logger.info("Model Training Results:")
        logger.info("Regression Models:")
        for model, metrics in results['regression_models'].items():
            logger.info(f"  {model}: R² = {metrics['r2']:.4f}, RMSE = {metrics['rmse']:.4f}")
        
        logger.info("Classification Models:")
        for model, metrics in results['classification_models'].items():
            logger.info(f"  {model}: Accuracy = {metrics['accuracy']:.4f}, F1 = {metrics['f1']:.4f}")
        
        logger.info("Phase 5 completed successfully!")
        logger.info("Next steps:")
        logger.info("  1. Review model results in Snowflake")
        logger.info("  2. Run Phase 6: Operations and Optimization")
        logger.info("  3. Continue with deployment")
        
    except Exception as e:
        logger.error(f"Phase 5 execution failed: {str(e)}")
        return
    finally:
        session.close()
        logger.info("Disconnected from Snowflake")

if __name__ == "__main__":
    main()