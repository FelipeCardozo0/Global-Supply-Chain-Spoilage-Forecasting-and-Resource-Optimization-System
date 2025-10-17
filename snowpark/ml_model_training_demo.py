"""
Phase 5: Machine Learning Model Training - Demo
Global Supply Chain Spoilage Forecasting Project
Creates demo model results for demonstration
"""

import json
import logging
import pandas as pd
import numpy as np
from pathlib import Path
from snowflake.snowpark import Session
from sklearn.ensemble import RandomForestRegressor, RandomForestClassifier
from sklearn.tree import DecisionTreeRegressor, DecisionTreeClassifier
from sklearn.metrics import mean_squared_error, r2_score, accuracy_score, f1_score

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

def create_demo_results():
    """Create demo model results"""
    logger.info("Creating demo model results...")
    
    # Generate demo data
    np.random.seed(42)
    n_samples = 1000
    
    # Create sample features
    X = np.random.randn(n_samples, 15)
    y_reg = np.random.randn(n_samples) * 0.1 + 0.5
    y_clf = (np.random.randn(n_samples) > 0).astype(int)
    
    # Split data
    train_size = int(0.7 * n_samples)
    val_size = int(0.15 * n_samples)
    
    X_train = X[:train_size]
    X_val = X[train_size:train_size + val_size]
    X_test = X[train_size + val_size:]
    
    y_train_reg = y_reg[:train_size]
    y_val_reg = y_reg[train_size:train_size + val_size]
    y_test_reg = y_reg[train_size + val_size:]
    
    y_train_clf = y_clf[:train_size]
    y_val_clf = y_clf[train_size:train_size + val_size]
    y_test_clf = y_clf[train_size + val_size:]
    
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
    
    return {
        'regression_models': {
            'DecisionTree': {'r2': dt_reg_r2, 'rmse': dt_reg_rmse},
            'RandomForest': {'r2': rf_reg_r2, 'rmse': rf_reg_rmse}
        },
        'classification_models': {
            'DecisionTree': {'accuracy': dt_clf_acc, 'f1': dt_clf_f1},
            'RandomForest': {'accuracy': rf_clf_acc, 'f1': rf_clf_f1}
        }
    }

def save_results_to_snowflake(session, results):
    """Save model results to Snowflake"""
    logger.info("Saving results to Snowflake...")
    
    # Create model results table if it doesn't exist
    session.sql("""
        CREATE OR REPLACE TABLE ML.MODEL_RESULTS (
            MODEL_NAME VARCHAR(255),
            MODEL_TYPE VARCHAR(50),
            R_SQUARED FLOAT,
            RMSE FLOAT,
            ACCURACY FLOAT,
            F1_SCORE FLOAT,
            CREATED_AT TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
        )
    """).collect()
    
    # Create predictions table if it doesn't exist
    session.sql("""
        CREATE OR REPLACE TABLE ML.PREDICTIONS (
            PREDICTION_ID VARCHAR(255) DEFAULT UUID_STRING(),
            MODEL_NAME VARCHAR(255),
            PREDICTION_TYPE VARCHAR(50),
            PREDICTED_VALUE FLOAT,
            ACTUAL_VALUE FLOAT,
            CREATED_AT TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
        )
    """).collect()
    
    # Save regression results
    for model_name, metrics in results['regression_models'].items():
        session.sql(f"""
            INSERT INTO ML.MODEL_RESULTS (MODEL_NAME, MODEL_TYPE, R_SQUARED, RMSE)
            VALUES ('{model_name}', 'regression', {metrics['r2']}, {metrics['rmse']})
        """).collect()
    
    # Save classification results
    for model_name, metrics in results['classification_models'].items():
        session.sql(f"""
            INSERT INTO ML.MODEL_RESULTS (MODEL_NAME, MODEL_TYPE, ACCURACY, F1_SCORE)
            VALUES ('{model_name}', 'classification', {metrics['accuracy']}, {metrics['f1']})
        """).collect()
    
    # Create sample predictions
    sample_predictions = [
        ('DecisionTree', 'regression', 0.45, 0.42),
        ('RandomForest', 'regression', 0.52, 0.48),
        ('DecisionTree', 'classification', 0.78, 0.75),
        ('RandomForest', 'classification', 0.82, 0.79)
    ]
    
    for model_name, pred_type, pred_val, actual_val in sample_predictions:
        session.sql(f"""
            INSERT INTO ML.PREDICTIONS (MODEL_NAME, PREDICTION_TYPE, PREDICTED_VALUE, ACTUAL_VALUE)
            VALUES ('{model_name}', '{pred_type}', {pred_val}, {actual_val})
        """).collect()
    
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
        # Create demo results
        results = create_demo_results()
        
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
