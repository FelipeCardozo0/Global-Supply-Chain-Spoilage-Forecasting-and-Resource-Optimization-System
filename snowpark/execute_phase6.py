"""
Phase 6 Orchestrator - Operations, Automation & Optimization
Global Supply Chain Spoilage and Resource Allocation Forecasting
================================================================================
Purpose: Orchestrate complete Phase 6 execution
Usage: python execute_phase6.py [--mode full|sql|optimize|monitor|dashboard]
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


class Phase6Orchestrator:
    """Orchestrate Phase 6 execution"""
    
    def __init__(self, config_file='../snowflake_config.json'):
        self.config_file = config_file
        self.session = None
        self.log_file = '../logs/phase6_execution.log'
        self.validation_file = '../logs/phase6_validation.log'
        
        # Ensure logs directory
        Path('../logs').mkdir(exist_ok=True)
        
    def log(self, message, to_file=True, to_console=True):
        """Log message"""
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
                "schema": "OPS",
                "role": sf_config.get('role', 'ACCOUNTADMIN')
            }
            
            self.session = Session.builder.configs(connection_parameters).create()
            self.log("Snowpark session created")
            self.log(f"   Database: {self.session.get_current_database()}")
            self.log(f"   Schema: {self.session.get_current_schema()}")
            return True
            
        except FileNotFoundError:
            self.log("Config file not found. Please create snowflake_config.json")
            return False
        except Exception as e:
            self.log(f"Failed to connect: {e}")
            return False
    
    def verify_phase5(self):
        """Verify Phase 5 completion"""
        self.log("\nVerifying Phase 5 prerequisites...")
        
        try:
            # Check ML schema exists
            self.session.sql("USE SCHEMA ML").collect()
            
            # Check model results exist
            count = self.session.sql("SELECT COUNT(*) FROM ML.MODEL_RESULTS").collect()[0][0]
            if count < 6:
                self.log(f"Insufficient models trained: {count} (expected 6)")
                return False
            
            # Check predictions exist
            count = self.session.sql("SELECT COUNT(*) FROM ML.PREDICTIONS").collect()[0][0]
            if count < 10:
                self.log(f"Insufficient predictions: {count}")
                return False
            
            self.log(f"Phase 5 verified: {count} predictions available")
            return True
            
        except Exception as e:
            self.log(f"Phase 5 verification failed: {e}")
            return False
    
    def setup_ops_schema(self):
        """Set up OPS schema and tables"""
        self.log("\nSetting up OPS schema...")
        
        sql_file = '../snowflake/06_ops_tasks.sql'
        if not Path(sql_file).exists():
            self.log(f"Warning: {sql_file} not found")
            return False
        
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
                    # Some statements may fail if objects already exist - that's OK
                    if 'already exists' not in str(e).lower():
                        self.log(f"   Warning: Statement {i} failed: {str(e)[:100]}")
            
            self.log("   OPS tasks schema setup complete")
            return True
            
        except Exception as e:
            self.log(f"Failed to setup OPS schema: {e}")
            return False
    
    def setup_ops_streams(self):
        """Set up OPS streams"""
        self.log("\nSetting up OPS streams...")
        
        sql_file = '../snowflake/06_ops_streams.sql'
        if not Path(sql_file).exists():
            self.log(f"Warning: {sql_file} not found")
            return False
        
        try:
            with open(sql_file, 'r', encoding='utf-8') as f:
                sql_content = f.read()
            
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
                    if 'already exists' not in str(e).lower():
                        self.log(f"   Warning: Statement {i} failed: {str(e)[:100]}")
            
            self.log("   OPS streams setup complete")
            return True
            
        except Exception as e:
            self.log(f"Failed to setup streams: {e}")
            return False
    
    def execute_optimization(self):
        """Execute resource allocation optimization"""
        self.log("\n" + "="*80)
        self.log("EXECUTING OPTIMIZATION")
        self.log("="*80)
        
        try:
            # Import and run optimization
            sys.path.insert(0, str(Path(__file__).parent.parent / 'optimization'))
            from resource_lp import ResourceAllocationOptimizer
            
            optimizer = ResourceAllocationOptimizer(self.config_file)
            optimizer.session = self.session  # Reuse session
            
            self.log("\nStarting resource allocation optimization...")
            start_time = time.time()
            
            success = optimizer.run_optimization(method='scipy')
            
            elapsed = time.time() - start_time
            
            if success:
                self.log(f"\nOptimization complete ({elapsed:.1f} seconds)")
            else:
                self.log("Optimization failed")
                return False
            
            # Run policy evaluation
            from policy_eval import AllocationPolicyEvaluator
            
            evaluator = AllocationPolicyEvaluator(self.config_file)
            evaluator.session = self.session
            
            self.log("\nStarting policy evaluation...")
            success = evaluator.run_evaluation()
            
            if success:
                self.log("Policy evaluation complete")
            
            return True
            
        except ImportError as e:
            self.log(f"Failed to import optimization modules: {e}")
            return False
        except Exception as e:
            self.log(f"Optimization failed: {e}")
            import traceback
            self.log(traceback.format_exc())
            return False
    
    def execute_monitoring(self):
        """Execute monitoring and drift detection"""
        self.log("\n" + "="*80)
        self.log("EXECUTING MONITORING")
        self.log("="*80)
        
        try:
            from monitor_ops import OperationsMonitor
            
            monitor = OperationsMonitor(self.config_file)
            monitor.session = self.session
            
            self.log("\nStarting operations monitoring...")
            success = monitor.run_monitoring()
            
            if success:
                self.log("Monitoring complete")
            
            return success
            
        except ImportError as e:
            self.log(f"Failed to import monitoring module: {e}")
            return False
        except Exception as e:
            self.log(f"Monitoring failed: {e}")
            import traceback
            self.log(traceback.format_exc())
            return False
    
    def run_validation(self):
        """Run comprehensive validation"""
        self.log("\n" + "="*80)
        self.log("RUNNING OPS VALIDATION")
        self.log("="*80)
        
        validation_sql = '../snowflake/validation_ops.sql'
        if not Path(validation_sql).exists():
            self.log("Warning: validation_ops.sql not found, skipping validation")
            return True
        
        try:
            with open(validation_sql, 'r', encoding='utf-8') as f:
                sql_content = f.read()
            
            statements = [s.strip() for s in sql_content.split(';') 
                         if s.strip() and not s.strip().startswith('--')]
            
            self.log(f"Running {len(statements)} validation queries...")
            
            # Open validation log
            with open(self.validation_file, 'w', encoding='utf-8') as vlog:
                vlog.write("="*80 + "\n")
                vlog.write("PHASE 6 OPERATIONS VALIDATION REPORT\n")
                vlog.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
                vlog.write("="*80 + "\n\n")
                
                for i, stmt in enumerate(statements, 1):
                    try:
                        if 'SELECT' in stmt.upper() and 'INSERT' not in stmt.upper():
                            results = self.session.sql(stmt).collect()
                            
                            if results and len(results) <= 20:
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
                    FROM OPS.OPS_VALIDATION_SUMMARY
                    WHERE validation_check = 'OVERALL_OPS_STATUS'
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
    
    def launch_dashboard(self):
        """Launch Streamlit dashboard"""
        self.log("\n" + "="*80)
        self.log("LAUNCHING DASHBOARD")
        self.log("="*80)
        
        dashboard_file = Path(__file__).parent.parent / 'dashboards' / 'streamlit_app.py'
        
        if not dashboard_file.exists():
            self.log("Dashboard file not found")
            return False
        
        self.log("\nStarting Streamlit dashboard...")
        self.log(f"Dashboard file: {dashboard_file}")
        self.log("\nNOTE: Dashboard will open in a new window")
        self.log("      Press Ctrl+C in the dashboard terminal to stop it")
        
        try:
            # Launch dashboard in separate process
            subprocess.Popen([
                sys.executable, '-m', 'streamlit', 'run', str(dashboard_file)
            ])
            
            self.log("Dashboard launched successfully")
            self.log("Access at: http://localhost:8501")
            return True
            
        except Exception as e:
            self.log(f"Failed to launch dashboard: {e}")
            self.log("You can manually run: streamlit run dashboards/streamlit_app.py")
            return False
    
    def generate_summary(self):
        """Generate Phase 6 completion summary"""
        self.log("\n" + "="*80)
        self.log("PHASE 6 COMPLETION SUMMARY")
        self.log("="*80)
        
        try:
            # Tasks created
            try:
                tasks = self.session.sql("""
                    SELECT name, state 
                    FROM INFORMATION_SCHEMA.TASKS 
                    WHERE task_schema = 'OPS'
                """).collect()
                
                if tasks:
                    self.log("\nTasks Created:")
                    self.log("-" * 60)
                    for task in tasks:
                        self.log(f"  {task['NAME']:40} {task['STATE']}")
            except:
                pass
            
            # Streams created
            try:
                streams = self.session.sql("""
                    SELECT name, table_name 
                    FROM INFORMATION_SCHEMA.STREAMS 
                    WHERE table_schema = 'OPS'
                """).collect()
                
                if streams:
                    self.log("\nStreams Created:")
                    self.log("-" * 60)
                    for stream in streams:
                        self.log(f"  {stream['NAME']:40} on {stream['TABLE_NAME']}")
            except:
                pass
            
            # Optimization summary
            try:
                opt_summary = self.session.sql("""
                    SELECT 
                        optimization_run_id,
                        method,
                        ROUND(total_spoilage_reduction, 2) AS reduction,
                        ROUND(spoilage_reduction_pct, 2) AS reduction_pct
                    FROM OPS.OPTIMIZATION_LOGS
                    ORDER BY created_at DESC
                    LIMIT 1
                """).collect()
                
                if opt_summary:
                    row = opt_summary[0]
                    self.log("\nOptimization Results:")
                    self.log("-" * 60)
                    self.log(f"  Run ID: {row['OPTIMIZATION_RUN_ID']}")
                    self.log(f"  Method: {row['METHOD']}")
                    self.log(f"  Spoilage Reduction: ${row['REDUCTION']:,.0f} ({row['REDUCTION_PCT']}%)")
            except:
                pass
            
            self.log("-" * 60)
            self.log("Phase 6 Complete")
            
        except Exception as e:
            self.log(f"Summary generation failed: {e}")
    
    def execute(self, mode='full'):
        """Execute complete Phase 6"""
        start_time = time.time()
        
        self.log("="*80)
        self.log("PHASE 6: OPERATIONS, AUTOMATION & OPTIMIZATION")
        self.log("="*80)
        self.log(f"Start Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        self.log(f"Mode: {mode.upper()}")
        
        # Create session
        if not self.create_session():
            return False
        
        # Verify Phase 5
        if mode == 'full':
            if not self.verify_phase5():
                self.log("Error: Phase 5 not complete")
                return False
        
        # Execute based on mode
        if mode in ['full', 'sql']:
            # Setup OPS schema
            if not self.setup_ops_schema():
                self.log("Warning: OPS schema setup incomplete")
            
            # Setup streams
            if not self.setup_ops_streams():
                self.log("Warning: Streams setup incomplete")
        
        if mode in ['full', 'optimize']:
            # Execute optimization
            if not self.execute_optimization():
                self.log("Error: Optimization failed")
                return False
        
        if mode in ['full', 'monitor']:
            # Execute monitoring
            self.execute_monitoring()
        
        if mode in ['full', 'sql']:
            # Run validation
            self.run_validation()
        
        if mode in ['dashboard']:
            # Launch dashboard
            self.launch_dashboard()
        
        # Generate summary
        self.generate_summary()
        
        # Completion
        elapsed = time.time() - start_time
        self.log("\n" + "="*80)
        self.log("PHASE 6 COMPLETE")
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
    parser = argparse.ArgumentParser(description='Execute Phase 6: Operations & Automation')
    parser.add_argument('--mode', choices=['full', 'sql', 'optimize', 'monitor', 'dashboard'], 
                       default='full',
                       help='Execution mode (default: full)')
    args = parser.parse_args()
    
    orchestrator = Phase6Orchestrator()
    
    try:
        success = orchestrator.execute(mode=args.mode)
        
        if args.mode == 'dashboard':
            print("\nDashboard is running. Press Ctrl+C to exit.")
            try:
                while True:
                    time.sleep(1)
            except KeyboardInterrupt:
                print("\nShutting down...")
        
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

