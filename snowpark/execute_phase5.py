"""
Phase 5 Orchestrator - Machine Learning & Prediction Pipeline
Global Supply Chain Spoilage and Resource Allocation Forecasting
================================================================================
Purpose: Orchestrate complete Phase 5 execution (model training & validation)
Usage: python execute_phase5.py [--method snowpark|sql]
================================================================================
"""

from snowflake.snowpark import Session
import json
import sys
import argparse
from pathlib import Path
from datetime import datetime
import time
import subprocess


class Phase5Orchestrator:
    """Orchestrate Phase 5 execution"""
    
    def __init__(self, config_file='../snowflake_config.json'):
        self.config_file = config_file
        self.session = None
        self.log_file = '../logs/phase5_execution.log'
        self.validation_file = '../logs/phase5_validation.log'
        
        # Ensure logs directory
        Path('../logs').mkdir(exist_ok=True)
        
    def log(self, message, to_file=True, to_console=True):
        """Log message to file and/or console"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        log_msg = f"[{timestamp}] {message}"
        
        if to_console:
            print(message)
        
        if to_file:
            with open(self.log_file, 'a', encoding='utf-8') as f:
                f.write(log_msg + '\n')
    
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
            self.log("Snowpark session created")
            self.log(f"   Database: {self.session.get_current_database()}")
            self.log(f"   Schema: {self.session.get_current_schema()}")
            return True
            
        except FileNotFoundError:
            self.log("Config file not found. Please create snowflake_config.json")
            self.log("   Template: snowflake_config.json.template")
            return False
        except Exception as e:
            self.log(f"Failed to connect: {e}")
            return False
    
    def verify_phase4(self):
        """Verify Phase 4 completion"""
        self.log("\nVerifying Phase 4 prerequisites...")
        
        try:
            # Check ML schema exists
            self.session.sql("USE SCHEMA ML").collect()
            
            # Check key ML tables
            tables = self.session.sql("SHOW TABLES IN ML").collect()
            table_names = [row['name'] for row in tables]
            
            required_tables = ['TRAIN_SET', 'VAL_SET', 'TEST_SET', 'TARGETS']
            missing_tables = [t for t in required_tables if t not in table_names]
            
            if missing_tables:
                self.log(f"Missing ML tables: {', '.join(missing_tables)}")
                self.log("   Please complete Phase 4 first.")
                return False
            
            # Check TRAIN_SET has data
            count = self.session.table("ML.TRAIN_SET").count()
            if count < 200:
                self.log(f"TRAIN_SET has insufficient data: {count} rows")
                self.log("   Expected at least 200 rows. Please re-run Phase 4.")
                return False
            
            self.log(f"Phase 4 verified: {len(table_names)} ML tables found")
            self.log(f"TRAIN_SET rows: {count}")
            return True
            
        except Exception as e:
            self.log(f"Phase 4 verification failed: {e}")
            return False
    
    def setup_model_schema(self):
        """Create model result tables"""
        self.log("\nSetting up model schema...")
        
        sql_file = '../snowflake/05_train_models.sql'
        if not Path(sql_file).exists():
            self.log(f"Warning: {sql_file} not found, skipping schema setup")
            return True
        
        try:
            with open(sql_file, 'r', encoding='utf-8') as f:
                sql_content = f.read()
            
            # Split into statements
            statements = [s.strip() for s in sql_content.split(';') 
                         if s.strip() and not s.strip().startswith('--')]
            
            self.log(f"   Executing {len(statements)} SQL statements...")
            
            for i, stmt in enumerate(statements, 1):
                try:
                    if i % 5 == 0:
                        self.log(f"   Progress: {i}/{len(statements)}...", 
                               to_file=True, to_console=False)
                    self.session.sql(stmt).collect()
                except Exception as e:
                    self.log(f"   Warning: Statement {i} failed: {str(e)[:100]}")
            
            self.log("   Model schema setup complete")
            return True
            
        except Exception as e:
            self.log(f"Failed to setup model schema: {e}")
            return False
    
    def execute_model_training(self):
        """Execute model training via Python script"""
        self.log("\n" + "="*80)
        self.log("EXECUTING MODEL TRAINING")
        self.log("="*80)
        
        try:
            # Import and run the ML pipeline
            from ml_model_training import SpoilageMLPipeline
            
            pipeline = SpoilageMLPipeline(self.config_file)
            pipeline.session = self.session  # Reuse existing session
            
            self.log("\nStarting ML training pipeline...")
            start_time = time.time()
            
            success = pipeline.run_pipeline()
            
            elapsed = time.time() - start_time
            
            if success:
                self.log(f"\nModel training complete ({elapsed/60:.1f} minutes)")
            else:
                self.log("Model training failed")
                return False
            
            return True
            
        except ImportError as e:
            self.log(f"Failed to import ml_model_training: {e}")
            self.log("Ensure ml_model_training.py exists in snowpark directory")
            return False
        except Exception as e:
            self.log(f"Model training failed: {e}")
            import traceback
            self.log(traceback.format_exc())
            return False
    
    def run_validation(self):
        """Run comprehensive validation"""
        self.log("\n" + "="*80)
        self.log("RUNNING MODEL VALIDATION")
        self.log("="*80)
        
        validation_sql = '../snowflake/validation_model.sql'
        if not Path(validation_sql).exists():
            self.log("Warning: validation_model.sql not found, skipping validation")
            return True
        
        try:
            with open(validation_sql, 'r', encoding='utf-8') as f:
                sql_content = f.read()
            
            # Split into statements
            statements = [s.strip() for s in sql_content.split(';') 
                         if s.strip() and not s.strip().startswith('--')]
            
            self.log(f"Running {len(statements)} validation queries...")
            
            # Open validation log
            with open(self.validation_file, 'w', encoding='utf-8') as vlog:
                vlog.write("="*80 + "\n")
                vlog.write("PHASE 5 MODEL VALIDATION REPORT\n")
                vlog.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
                vlog.write("="*80 + "\n\n")
                
                for i, stmt in enumerate(statements, 1):
                    try:
                        if 'SELECT' in stmt.upper() and 'INSERT' not in stmt.upper():
                            results = self.session.sql(stmt).collect()
                            
                            if results and len(results) <= 10:
                                for row in results:
                                    vlog.write(str(dict(row.asDict())) + "\n")
                                vlog.write("\n")
                        else:
                            self.session.sql(stmt).collect()
                        
                        if i % 10 == 0:
                            self.log(f"   Progress: {i}/{len(statements)}...", 
                                   to_file=True, to_console=False)
                        
                    except Exception as e:
                        error_msg = f"Validation query {i} failed: {str(e)[:100]}"
                        self.log(f"   Warning: {error_msg}")
                        vlog.write(f"ERROR: {error_msg}\n\n")
                
                vlog.write("="*80 + "\n")
                vlog.write("VALIDATION COMPLETE\n")
                vlog.write("="*80 + "\n")
            
            self.log(f"Validation report saved: {self.validation_file}")
            
            # Check overall validation status
            try:
                status_result = self.session.sql("""
                    SELECT status, details
                    FROM ML.MODEL_VALIDATION_SUMMARY
                    WHERE validation_check = 'OVERALL_STATUS'
                """).collect()
                
                if status_result:
                    status = status_result[0]['STATUS']
                    details = status_result[0]['DETAILS']
                    self.log(f"\nValidation Status: {status}")
                    self.log(f"Details: {details}")
                    
                    return status in ['PASS', 'WARN']
                
            except Exception as e:
                self.log(f"Could not retrieve validation status: {e}")
            
            return True
            
        except Exception as e:
            self.log(f"Validation execution failed: {e}")
            return False
    
    def generate_summary(self):
        """Generate Phase 5 completion summary"""
        self.log("\n" + "="*80)
        self.log("PHASE 5 COMPLETION SUMMARY")
        self.log("="*80)
        
        try:
            # Model results summary
            models = self.session.sql("""
                SELECT 
                    model_name,
                    task,
                    CASE WHEN task = 'regression' THEN val_r2 ELSE val_f1 END AS val_metric,
                    created_at
                FROM ML.MODEL_RESULTS
                ORDER BY task, model_name
            """).collect()
            
            if models:
                self.log("\nTrained Models:")
                self.log("-" * 60)
                for model in models:
                    metric_name = 'R²' if model['TASK'] == 'regression' else 'F1'
                    self.log(f"  {model['MODEL_NAME']:30} {model['TASK']:15} "
                           f"{metric_name}: {model['VAL_METRIC']:.4f}")
            
            # Feature importance summary
            try:
                top_features = self.session.sql("""
                    SELECT 
                        feature_name,
                        ROUND(AVG(importance_score), 4) AS avg_importance
                    FROM ML.FEATURE_IMPORTANCE
                    GROUP BY feature_name
                    ORDER BY avg_importance DESC
                    LIMIT 10
                """).collect()
                
                if top_features:
                    self.log("\nTop 10 Most Important Features:")
                    self.log("-" * 60)
                    for i, feat in enumerate(top_features, 1):
                        self.log(f"  {i:2}. {feat['FEATURE_NAME']:30} "
                               f"Avg Importance: {feat['AVG_IMPORTANCE']:.4f}")
            except:
                pass
            
            # Predictions summary
            try:
                pred_count = self.session.table("ML.PREDICTIONS").count()
                self.log(f"\nPredictions Generated: {pred_count} rows")
            except:
                pass
            
            self.log("-" * 60)
            self.log("Phase 5 Complete")
            
        except Exception as e:
            self.log(f"Summary generation failed: {e}")
    
    def execute(self, method='snowpark'):
        """Execute complete Phase 5"""
        start_time = time.time()
        
        self.log("="*80)
        self.log("PHASE 5: MACHINE LEARNING & PREDICTION")
        self.log("="*80)
        self.log(f"Start Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        self.log(f"Method: {method.upper()}")
        
        # Create session
        if not self.create_session():
            return False
        
        # Verify Phase 4
        if not self.verify_phase4():
            return False
        
        # Setup model schema
        if not self.setup_model_schema():
            self.log("Warning: Schema setup incomplete, continuing...")
        
        # Execute model training
        if method == 'snowpark':
            if not self.execute_model_training():
                self.log("Error: Model training failed")
                return False
        else:
            self.log("SQL-only method not fully implemented for Phase 5")
            self.log("Phase 5 requires Python for ML training")
            self.log("Please use: python execute_phase5.py --method snowpark")
            return False
        
        # Run validation
        self.run_validation()
        
        # Generate summary
        self.generate_summary()
        
        # Completion
        elapsed = time.time() - start_time
        self.log("\n" + "="*80)
        self.log("PHASE 5 COMPLETE")
        self.log(f"Duration: {elapsed/60:.1f} minutes")
        self.log(f"Log File: {self.log_file}")
        self.log(f"Validation Report: {self.validation_file}")
        self.log("="*80)
        
        return True
    
    def close(self):
        """Close session"""
        if self.session:
            self.session.close()


def main():
    """Main execution"""
    parser = argparse.ArgumentParser(description='Execute Phase 5: ML Training & Prediction')
    parser.add_argument('--method', choices=['snowpark', 'sql'], default='snowpark',
                        help='Execution method: snowpark (default) or sql')
    args = parser.parse_args()
    
    orchestrator = Phase5Orchestrator()
    
    try:
        success = orchestrator.execute(method=args.method)
        sys.exit(0 if success else 1)
        
    except KeyboardInterrupt:
        print("\n\nExecution interrupted by user")
        sys.exit(1)
        
    except Exception as e:
        print(f"\nFatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
        
    finally:
        orchestrator.close()


if __name__ == "__main__":
    main()

