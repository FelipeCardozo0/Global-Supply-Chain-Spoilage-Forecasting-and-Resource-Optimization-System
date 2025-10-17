"""
Operations Monitoring & Drift Detection
Global Supply Chain Spoilage and Resource Allocation Forecasting
================================================================================
Purpose: Monitor model performance, detect drift, generate alerts
Methods: KS-test for distribution drift, outlier detection, performance monitoring
================================================================================
"""

import sys
from pathlib import Path
import json
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from scipy import stats
from snowflake.snowpark import Session


class OperationsMonitor:
    """
    Monitor operational health and model performance
    """
    
    def __init__(self, config_file='../snowflake_config.json'):
        """Initialize monitor"""
        self.config_file = config_file
        self.session = None
        self.alerts = []
        self.drift_results = {}
        
        # Monitoring thresholds
        self.drift_threshold = 0.05  # p-value threshold for KS test
        self.outlier_threshold = 3  # Standard deviations for outliers
        self.performance_degradation_threshold = 0.1  # 10% degradation
        
    def create_session(self):
        """Create Snowpark session"""
        try:
            with open(self.config_file, 'r') as f:
                config = json.load(f)
            
            sf_config = config['snowflake']
            
            connection_parameters = {
                "account": sf_config['account'],
                "user": sf_config['user'],
                "password": sf_config['password'],
                "warehouse": sf_config.get('warehouse', 'COMPUTE_WH'),
                "database": sf_config.get('database', 'GLOBAL_SPOILAGE_DB'),
                "schema": "ML",
                "role": sf_config.get('role', 'ACCOUNTADMIN')
            }
            
            self.session = Session.builder.configs(connection_parameters).create()
            print("Snowpark session created")
            return True
            
        except Exception as e:
            print(f"Failed to create session: {e}")
            return False
    
    def detect_feature_drift(self):
        """
        Detect distribution drift in features using KS test
        Compare recent data to training distribution
        """
        print("\n" + "="*80)
        print("FEATURE DRIFT DETECTION")
        print("="*80)
        
        try:
            # Get training set features (baseline)
            train_query = """
                SELECT 
                    fedfunds_rate, retail_sales, unemployment_rate,
                    consumer_price_index, sp500_eom_close,
                    retail_volatility_12m, economic_uncertainty_index
                FROM ML.TRAIN_SET
                WHERE fedfunds_rate IS NOT NULL
            """
            train_df = self.session.sql(train_query).to_pandas()
            
            # Get recent test/production features
            recent_query = """
                SELECT 
                    fedfunds_rate, retail_sales, unemployment_rate,
                    consumer_price_index, sp500_eom_close,
                    retail_volatility_12m, economic_uncertainty_index
                FROM ML.TEST_SET
                WHERE fedfunds_rate IS NOT NULL
                ORDER BY date DESC
                LIMIT 12  -- Last 12 months
            """
            recent_df = self.session.sql(recent_query).to_pandas()
            
            if len(recent_df) == 0:
                print("Warning: No recent data available for drift detection")
                return False
            
            print(f"\nComparing distributions:")
            print(f"  Training set: {len(train_df)} samples")
            print(f"  Recent data: {len(recent_df)} samples")
            
            # Perform KS test for each feature
            drift_detected = False
            
            for feature in train_df.columns:
                train_values = train_df[feature].dropna().values
                recent_values = recent_df[feature].dropna().values
                
                if len(train_values) < 10 or len(recent_values) < 5:
                    continue
                
                # Two-sample Kolmogorov-Smirnov test
                ks_statistic, p_value = stats.ks_2samp(train_values, recent_values)
                
                # Detect drift
                has_drift = p_value < self.drift_threshold
                
                if has_drift:
                    drift_detected = True
                    self.alerts.append({
                        'alert_type': 'DRIFT',
                        'feature': feature,
                        'ks_statistic': ks_statistic,
                        'p_value': p_value,
                        'severity': 'HIGH' if p_value < 0.01 else 'MEDIUM',
                        'message': f"Distribution drift detected in {feature} (p={p_value:.4f})"
                    })
                
                self.drift_results[feature] = {
                    'ks_statistic': ks_statistic,
                    'p_value': p_value,
                    'has_drift': has_drift,
                    'train_mean': train_values.mean(),
                    'recent_mean': recent_values.mean(),
                    'train_std': train_values.std(),
                    'recent_std': recent_values.std()
                }
                
                status = "DRIFT!" if has_drift else "OK"
                print(f"\n{feature}:")
                print(f"  KS statistic: {ks_statistic:.4f}")
                print(f"  p-value: {p_value:.4f}")
                print(f"  Status: {status}")
                
                if has_drift:
                    print(f"  Train mean: {train_values.mean():.4f}, Recent mean: {recent_values.mean():.4f}")
                    print(f"  Train std: {train_values.std():.4f}, Recent std: {recent_values.std():.4f}")
            
            if drift_detected:
                print("\nWARNING: Feature drift detected! Consider retraining models.")
            else:
                print("\nNo significant feature drift detected.")
            
            return True
            
        except Exception as e:
            print(f"Drift detection failed: {e}")
            return False
    
    def detect_prediction_outliers(self):
        """
        Detect anomalous predictions using statistical outlier detection
        """
        print("\n" + "="*80)
        print("PREDICTION OUTLIER DETECTION")
        print("="*80)
        
        try:
            # Get predictions
            predictions_query = """
                SELECT 
                    date,
                    (randomforestregressor_pred + xgbregressor_pred) / 2.0 AS predicted_rate,
                    randomforestclassifier_proba AS risk_probability
                FROM ML.PREDICTIONS
                ORDER BY date
            """
            predictions = self.session.sql(predictions_query).to_pandas()
            
            # Calculate z-scores
            pred_values = predictions['PREDICTED_RATE'].values
            mean = pred_values.mean()
            std = pred_values.std()
            z_scores = np.abs((pred_values - mean) / std)
            
            # Identify outliers
            outliers = z_scores > self.outlier_threshold
            n_outliers = outliers.sum()
            
            print(f"\nPrediction statistics:")
            print(f"  Total predictions: {len(predictions)}")
            print(f"  Mean: {mean:.4f}")
            print(f"  Std: {std:.4f}")
            print(f"  Outliers (>{self.outlier_threshold}σ): {n_outliers}")
            
            if n_outliers > 0:
                outlier_dates = predictions.loc[outliers, 'DATE'].values
                outlier_values = predictions.loc[outliers, 'PREDICTED_RATE'].values
                outlier_z = z_scores[outliers]
                
                print(f"\nOutlier predictions:")
                for date, value, z in zip(outlier_dates, outlier_values, outlier_z):
                    print(f"  {date}: {value:.4f} (z={z:.2f})")
                    
                    self.alerts.append({
                        'alert_type': 'OUTLIER',
                        'date': str(date),
                        'predicted_value': value,
                        'z_score': z,
                        'severity': 'HIGH' if z > 4 else 'MEDIUM',
                        'message': f"Anomalous prediction on {date}: {value:.4f} (z={z:.2f})"
                    })
            else:
                print("No prediction outliers detected.")
            
            return True
            
        except Exception as e:
            print(f"Outlier detection failed: {e}")
            return False
    
    def monitor_model_performance(self):
        """
        Monitor model performance over time
        Check for degradation compared to validation metrics
        """
        print("\n" + "="*80)
        print("MODEL PERFORMANCE MONITORING")
        print("="*80)
        
        try:
            # Get validation metrics
            val_metrics_query = """
                SELECT 
                    model_name,
                    task,
                    val_r2,
                    val_f1,
                    val_auc
                FROM ML.MODEL_RESULTS
            """
            val_metrics = self.session.sql(val_metrics_query).to_pandas()
            
            print("\nValidation metrics:")
            for _, row in val_metrics.iterrows():
                print(f"\n{row['MODEL_NAME']} ({row['TASK']}):")
                if row['TASK'] == 'regression':
                    print(f"  Validation R²: {row['VAL_R2']:.4f}")
                else:
                    print(f"  Validation F1: {row['VAL_F1']:.4f}")
                    print(f"  Validation AUC: {row['VAL_AUC']:.4f}")
            
            # TODO: In production, compare against recent test set performance
            # For now, we just log the validation metrics
            
            print("\nNote: Continuous performance monitoring requires ongoing test data")
            print("      Implement periodic revalidation on hold-out test set")
            
            return True
            
        except Exception as e:
            print(f"Performance monitoring failed: {e}")
            return False
    
    def check_task_execution_health(self):
        """
        Monitor automated task execution health
        """
        print("\n" + "="*80)
        print("TASK EXECUTION HEALTH CHECK")
        print("="*80)
        
        try:
            # Get recent task runs
            task_query = """
                SELECT 
                    task_name,
                    execution_start,
                    status,
                    duration_seconds,
                    error_message
                FROM OPS.TASK_RUNS
                WHERE execution_start >= DATEADD(day, -7, CURRENT_DATE())
                ORDER BY execution_start DESC
            """
            
            try:
                task_runs = self.session.sql(task_query).to_pandas()
                
                if len(task_runs) == 0:
                    print("No recent task executions found.")
                    return True
                
                # Calculate success rate
                total = len(task_runs)
                successful = (task_runs['STATUS'] == 'SUCCESS').sum()
                failed = (task_runs['STATUS'] == 'FAILED').sum()
                success_rate = (successful / total) * 100
                
                print(f"\nTask execution summary (last 7 days):")
                print(f"  Total runs: {total}")
                print(f"  Successful: {successful}")
                print(f"  Failed: {failed}")
                print(f"  Success rate: {success_rate:.1f}%")
                
                # Alert on low success rate
                if success_rate < 80:
                    self.alerts.append({
                        'alert_type': 'TASK_FAILURE',
                        'success_rate': success_rate,
                        'failed_count': failed,
                        'severity': 'HIGH' if success_rate < 50 else 'MEDIUM',
                        'message': f"Task success rate is low: {success_rate:.1f}% ({failed} failures)"
                    })
                
                # Show failed tasks
                if failed > 0:
                    print("\nFailed tasks:")
                    failed_tasks = task_runs[task_runs['STATUS'] == 'FAILED']
                    for _, row in failed_tasks.iterrows():
                        print(f"  {row['TASK_NAME']} at {row['EXECUTION_START']}")
                        if row['ERROR_MESSAGE']:
                            print(f"    Error: {row['ERROR_MESSAGE']}")
                
            except:
                print("Task execution table not found. Tasks may not be activated yet.")
                
            return True
            
        except Exception as e:
            print(f"Task health check failed: {e}")
            return False
    
    def save_monitoring_results(self):
        """Save monitoring results to Snowflake"""
        print("\n" + "="*80)
        print("SAVING MONITORING RESULTS")
        print("="*80)
        
        try:
            # Create monitoring summary table
            self.session.sql("""
                CREATE TABLE IF NOT EXISTS OPS.MONITORING_SUMMARY (
                    monitor_id NUMBER AUTOINCREMENT,
                    check_type STRING NOT NULL,
                    feature_name STRING,
                    ks_statistic FLOAT,
                    p_value FLOAT,
                    has_drift BOOLEAN,
                    alert_generated BOOLEAN,
                    alert_severity STRING,
                    details STRING,
                    checked_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
                    CONSTRAINT pk_monitoring PRIMARY KEY (monitor_id)
                )
            """).collect()
            
            # Save drift results
            drift_records = []
            for feature, results in self.drift_results.items():
                drift_records.append({
                    'check_type': 'DRIFT_DETECTION',
                    'feature_name': feature,
                    'ks_statistic': results['ks_statistic'],
                    'p_value': results['p_value'],
                    'has_drift': results['has_drift'],
                    'alert_generated': results['has_drift'],
                    'alert_severity': 'HIGH' if results['p_value'] < 0.01 else 'MEDIUM',
                    'details': f"KS={results['ks_statistic']:.4f}, p={results['p_value']:.4f}"
                })
            
            if drift_records:
                drift_df = pd.DataFrame(drift_records)
                sp_drift_df = self.session.create_dataframe(drift_df)
                sp_drift_df.write.mode("append").save_as_table("OPS.MONITORING_SUMMARY")
                print(f"Saved {len(drift_records)} drift detection records")
            
            # Save alerts
            if self.alerts:
                self.session.sql("""
                    CREATE TABLE IF NOT EXISTS OPS.ALERTS (
                        alert_id NUMBER AUTOINCREMENT,
                        alert_type STRING NOT NULL,
                        severity STRING NOT NULL,
                        message STRING NOT NULL,
                        details VARIANT,
                        created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
                        acknowledged BOOLEAN DEFAULT FALSE,
                        CONSTRAINT pk_alerts PRIMARY KEY (alert_id)
                    )
                """).collect()
                
                alert_records = []
                for alert in self.alerts:
                    alert_records.append({
                        'alert_type': alert['alert_type'],
                        'severity': alert['severity'],
                        'message': alert['message'],
                        'details': json.dumps({k: v for k, v in alert.items() 
                                             if k not in ['alert_type', 'severity', 'message']})
                    })
                
                alert_df = pd.DataFrame(alert_records)
                sp_alert_df = self.session.create_dataframe(alert_df)
                sp_alert_df.write.mode("append").save_as_table("OPS.ALERTS")
                print(f"Generated {len(alert_records)} alerts")
            else:
                print("No alerts generated - system healthy")
            
            return True
            
        except Exception as e:
            print(f"Failed to save monitoring results: {e}")
            return False
    
    def generate_monitoring_report(self):
        """Generate human-readable monitoring report"""
        print("\n" + "="*80)
        print("MONITORING REPORT")
        print("="*80)
        print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("="*80)
        
        # Drift summary
        drift_count = sum(1 for r in self.drift_results.values() if r['has_drift'])
        print(f"\nFeature Drift:")
        print(f"  Features monitored: {len(self.drift_results)}")
        print(f"  Drift detected: {drift_count}")
        
        # Alerts summary
        print(f"\nAlerts:")
        print(f"  Total alerts: {len(self.alerts)}")
        
        if self.alerts:
            high = sum(1 for a in self.alerts if a['severity'] == 'HIGH')
            medium = sum(1 for a in self.alerts if a['severity'] == 'MEDIUM')
            print(f"  High severity: {high}")
            print(f"  Medium severity: {medium}")
            
            print(f"\nAlert details:")
            for alert in self.alerts:
                print(f"  [{alert['severity']}] {alert['message']}")
        else:
            print("  No alerts - system healthy")
        
        # Recommendations
        print(f"\nRecommendations:")
        if drift_count > 2:
            print("  - Consider retraining models due to feature drift")
        if len(self.alerts) > 0:
            print("  - Review alerts and take corrective action")
        if drift_count == 0 and len(self.alerts) == 0:
            print("  - System is healthy, continue monitoring")
        
        print("="*80)
    
    def run_monitoring(self):
        """Execute complete monitoring workflow"""
        print("="*80)
        print("OPERATIONS MONITORING")
        print("="*80)
        
        # Drift detection
        self.detect_feature_drift()
        
        # Outlier detection
        self.detect_prediction_outliers()
        
        # Performance monitoring
        self.monitor_model_performance()
        
        # Task health
        self.check_task_execution_health()
        
        # Save results
        self.save_monitoring_results()
        
        # Generate report
        self.generate_monitoring_report()
        
        print("\nMonitoring complete!")
        return True
    
    def close(self):
        """Close session"""
        if self.session:
            self.session.close()
            print("\nSession closed")


def main():
    """Main execution"""
    print("="*80)
    print("PHASE 6: OPERATIONS MONITORING")
    print("="*80)
    
    monitor = OperationsMonitor()
    
    if not monitor.create_session():
        sys.exit(1)
    
    try:
        monitor.run_monitoring()
        print("\nPhase 6 monitoring complete!")
        
    except Exception as e:
        print(f"\nFatal error: {e}")
        import traceback
        traceback.print_exc()
        
    finally:
        monitor.close()


if __name__ == "__main__":
    main()

