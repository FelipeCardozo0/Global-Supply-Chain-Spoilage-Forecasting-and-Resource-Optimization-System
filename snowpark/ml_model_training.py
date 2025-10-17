"""
Phase 5: Machine Learning Model Training
Global Supply Chain Spoilage Forecasting Project
Trains 6 ML models and generates predictions
"""

import os
import json
import logging
import pandas as pd
import numpy as np
from pathlib import Path
from snowflake.snowpark import Session
from sklearn.ensemble import RandomForestRegressor, RandomForestClassifier
from sklearn.tree import DecisionTreeRegressor, DecisionTreeClassifier
from sklearn.metrics import mean_squared_error, mean_absolute_error, r2_score, accuracy_score, precision_score, recall_score, f1_score, roc_auc_score
from sklearn.model_selection import cross_val_score
import xgboost as xgb

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/phase5_execution.log'),
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
    if not os.path.exists(config_path):
        logger.error(f"Snowflake config file not found: {config_path}")
        return None
    
    with open(config_path, 'r') as f:
        config = json.load(f)
    
    return config

class MLModelTrainer:
    def __init__(self, session: Session):
        self.session = session
        self.models = {}
        self.results = {}
        
    def load_data(self):
        """Load training, validation, and test data"""
        try:
            logger.info("Loading ML datasets...")
            
            # Load training data
            train_df = self.session.table("ML.TRAIN_SET").to_pandas()
            logger.info(f"Training data: {train_df.shape}")
            
            # Load validation data
            val_df = self.session.table("ML.VAL_SET").to_pandas()
            logger.info(f"Validation data: {val_df.shape}")
            
            # Load test data
            test_df = self.session.table("ML.TEST_SET").to_pandas()
            logger.info(f"Test data: {test_df.shape}")
            
            return train_df, val_df, test_df
            
        except Exception as e:
            logger.error(f"Error loading data: {str(e)}")
            raise
    
    def prepare_features(self, df):
        """Prepare feature matrix and target variables"""
        try:
            # Select feature columns (exclude target and metadata)
            feature_cols = [
                'fedfunds_rate', 'retail_sales', 'treasury_10y_rate',
                'fedfunds_3m_avg', 'retail_3m_avg', 'treasury_3m_avg',
                'fedfunds_lag_1m', 'retail_lag_1m', 'treasury_lag_1m',
                'fedfunds_growth_1m', 'retail_growth_1m', 'treasury_growth_1m',
                'fedfunds_volatility_3m', 'retail_volatility_3m', 'treasury_volatility_3m',
                'yield_curve_inversion', 'yield_spread'
            ]
            
            # Filter available columns
            available_cols = [col for col in feature_cols if col in df.columns]
            X = df[available_cols].fillna(0)
            
            # Target variables
            y_reg = df['spoilage_rate'].fillna(0) if 'spoilage_rate' in df.columns else pd.Series([0] * len(df))
            y_clf = df['spoilage_risk_flag'].fillna(0) if 'spoilage_risk_flag' in df.columns else pd.Series([0] * len(df))
            
            logger.info(f"Features: {len(available_cols)} columns")
            logger.info(f"Regression target: {y_reg.notna().sum()} non-null values")
            logger.info(f"Classification target: {y_clf.notna().sum()} non-null values")
            
            return X, y_reg, y_clf, available_cols
            
        except Exception as e:
            logger.error(f"Error preparing features: {str(e)}")
            raise
    
    def train_models(self, X_train, y_train_reg, y_train_clf, X_val, y_val_reg, y_val_clf):
        """Train 6 ML models (3 regression, 3 classification)"""
        try:
            logger.info("Training ML models...")
            
            # Regression models
            logger.info("Training regression models...")
            
            # Decision Tree Regression
            dt_reg = DecisionTreeRegressor(random_state=42, max_depth=10)
            dt_reg.fit(X_train, y_train_reg)
            self.models['dt_reg'] = dt_reg
            
            # Random Forest Regression
            rf_reg = RandomForestRegressor(n_estimators=100, random_state=42, max_depth=10)
            rf_reg.fit(X_train, y_train_reg)
            self.models['rf_reg'] = rf_reg
            
            # XGBoost Regression
            xgb_reg = xgb.XGBRegressor(n_estimators=100, random_state=42, max_depth=6)
            xgb_reg.fit(X_train, y_train_reg)
            self.models['xgb_reg'] = xgb_reg
            
            # Classification models
            logger.info("Training classification models...")
            
            # Decision Tree Classification
            dt_clf = DecisionTreeClassifier(random_state=42, max_depth=10)
            dt_clf.fit(X_train, y_train_clf)
            self.models['dt_clf'] = dt_clf
            
            # Random Forest Classification
            rf_clf = RandomForestClassifier(n_estimators=100, random_state=42, max_depth=10)
            rf_clf.fit(X_train, y_train_clf)
            self.models['rf_clf'] = rf_clf
            
            # XGBoost Classification
            xgb_clf = xgb.XGBClassifier(n_estimators=100, random_state=42, max_depth=6)
            xgb_clf.fit(X_train, y_train_clf)
            self.models['xgb_clf'] = xgb_clf
            
            logger.info("All models trained successfully")
            return True
            
        except Exception as e:
            logger.error(f"Error training models: {str(e)}")
            raise
    
    def evaluate_models(self, X_val, y_val_reg, y_val_clf):
        """Evaluate model performance"""
        try:
            logger.info("Evaluating model performance...")
            
            results = {}
            
            # Regression models
            for model_name in ['dt_reg', 'rf_reg', 'xgb_reg']:
                if model_name in self.models:
                    model = self.models[model_name]
                    y_pred = model.predict(X_val)
                    
                    rmse = np.sqrt(mean_squared_error(y_val_reg, y_pred))
                    mae = mean_absolute_error(y_val_reg, y_pred)
                    r2 = r2_score(y_val_reg, y_pred)
                    
                    results[model_name] = {
                        'rmse': rmse,
                        'mae': mae,
                        'r2': r2
                    }
                    
                    logger.info(f"{model_name}: RMSE={rmse:.4f}, MAE={mae:.4f}, R²={r2:.4f}")
            
            # Classification models
            for model_name in ['dt_clf', 'rf_clf', 'xgb_clf']:
                if model_name in self.models:
                    model = self.models[model_name]
                    y_pred = model.predict(X_val)
                    y_pred_proba = model.predict_proba(X_val)[:, 1] if hasattr(model, 'predict_proba') else y_pred
                    
                    accuracy = accuracy_score(y_val_clf, y_pred)
                    precision = precision_score(y_val_clf, y_pred, average='weighted')
                    recall = recall_score(y_val_clf, y_pred, average='weighted')
                    f1 = f1_score(y_val_clf, y_pred, average='weighted')
                    
                    try:
                        auc = roc_auc_score(y_val_clf, y_pred_proba)
                    except:
                        auc = 0.5
                    
                    results[model_name] = {
                        'accuracy': accuracy,
                        'precision': precision,
                        'recall': recall,
                        'f1': f1,
                        'auc': auc
                    }
                    
                    logger.info(f"{model_name}: Accuracy={accuracy:.4f}, F1={f1:.4f}, AUC={auc:.4f}")
            
            self.results = results
            return results
            
        except Exception as e:
            logger.error(f"Error evaluating models: {str(e)}")
            raise
    
    def save_results(self, X_test, y_test_reg, y_test_clf, feature_names):
        """Save model results to Snowflake"""
        try:
            logger.info("Saving model results to Snowflake...")
            
            # Create model results table
            self.session.sql("""
                CREATE OR REPLACE TABLE ML.MODEL_RESULTS (
                    model_name STRING,
                    model_type STRING,
                    metric_name STRING,
                    metric_value FLOAT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
                )
            """).collect()
            
            # Insert results
            for model_name, metrics in self.results.items():
                model_type = 'regression' if 'reg' in model_name else 'classification'
                
                for metric_name, metric_value in metrics.items():
                    self.session.sql(f"""
                        INSERT INTO ML.MODEL_RESULTS (model_name, model_type, metric_name, metric_value)
                        VALUES ('{model_name}', '{model_type}', '{metric_name}', {metric_value})
                    """).collect()
            
            # Generate predictions on test set
            logger.info("Generating predictions on test set...")
            
            predictions = []
            for model_name, model in self.models.items():
                if 'reg' in model_name:
                    y_pred = model.predict(X_test)
                    for i, pred in enumerate(y_pred):
                        predictions.append({
                            'date': X_test.index[i] if hasattr(X_test, 'index') else i,
                            'model_name': model_name,
                            'predicted_spoilage_rate': pred,
                            'predicted_risk_flag': None,
                            'prediction_probability': None
                        })
                else:
                    y_pred = model.predict(X_test)
                    y_pred_proba = model.predict_proba(X_test)[:, 1] if hasattr(model, 'predict_proba') else y_pred
                    for i, (pred, proba) in enumerate(zip(y_pred, y_pred_proba)):
                        predictions.append({
                            'date': X_test.index[i] if hasattr(X_test, 'index') else i,
                            'model_name': model_name,
                            'predicted_spoilage_rate': None,
                            'predicted_risk_flag': int(pred),
                            'prediction_probability': float(proba)
                        })
            
            # Create predictions table
            self.session.sql("""
                CREATE OR REPLACE TABLE ML.PREDICTIONS (
                    date STRING,
                    model_name STRING,
                    predicted_spoilage_rate FLOAT,
                    predicted_risk_flag INTEGER,
                    prediction_probability FLOAT,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
                )
            """).collect()
            
            # Insert predictions
            for pred in predictions:
                self.session.sql(f"""
                    INSERT INTO ML.PREDICTIONS (date, model_name, predicted_spoilage_rate, predicted_risk_flag, prediction_probability)
                    VALUES ('{pred['date']}', '{pred['model_name']}', {pred['predicted_spoilage_rate'] or 'NULL'}, {pred['predicted_risk_flag'] or 'NULL'}, {pred['prediction_probability'] or 'NULL'})
                """).collect()
            
            logger.info("Model results saved successfully")
            return True
            
        except Exception as e:
            logger.error(f"Error saving results: {str(e)}")
            raise

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
        # Initialize trainer
        trainer = MLModelTrainer(session)
        
        # Load data
        train_df, val_df, test_df = trainer.load_data()
        
        # Prepare features
        X_train, y_train_reg, y_train_clf, feature_names = trainer.prepare_features(train_df)
        X_val, y_val_reg, y_val_clf, _ = trainer.prepare_features(val_df)
        X_test, y_test_reg, y_test_clf, _ = trainer.prepare_features(test_df)
        
        # Train models
        trainer.train_models(X_train, y_train_reg, y_train_clf, X_val, y_val_reg, y_val_clf)
        
        # Evaluate models
        results = trainer.evaluate_models(X_val, y_val_reg, y_val_clf)
        
        # Save results
        trainer.save_results(X_test, y_test_reg, y_test_clf, feature_names)
        
        logger.info("Phase 5 completed successfully!")
        logger.info("Next steps:")
        logger.info("  1. Review model results in Snowflake")
        logger.info("  2. Run Phase 6: Operations & Testing")
        logger.info("  3. Deploy to production")
        
    except Exception as e:
        logger.error(f"Phase 5 execution failed: {str(e)}")
        return
    finally:
        session.close()
        logger.info("Disconnected from Snowflake")

if __name__ == "__main__":
    main()