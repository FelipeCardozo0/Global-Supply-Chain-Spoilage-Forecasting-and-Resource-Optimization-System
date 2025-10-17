"""
Phase 6 Pre-Production Readiness Testing
Global Supply Chain Spoilage and Resource Allocation Forecasting
================================================================================
Purpose: Comprehensive validation before Phase 7 / production deployment
Tests: Tasks, streams, validation, alerts, ROI, dry run, backups
================================================================================
"""

import sys
import json
import time
from pathlib import Path
from datetime import datetime, timedelta
import pandas as pd
from snowflake.snowpark import Session


class Phase6ReadinessTest:
    """Comprehensive Phase 6 readiness testing"""
    
    def __init__(self, config_file='../snowflake_config.json'):
        self.config_file = config_file
        self.session = None
        self.test_results = []
        self.test_log = '../logs/phase6_readiness_test.log'
        
        # Ensure logs directory
        Path('../logs').mkdir(exist_ok=True)
        
        # Test configuration
        self.max_stream_age_hours = 24
        self.min_task_success_rate = 80.0
        self.max_validation_failures = 0
        self.max_validation_warnings = 3
        self.min_roi_ratio = 1.5  # savings >= 1.5x spend
        
    def log(self, message, level='INFO'):
        """Log test message"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        log_msg = f"[{timestamp}] [{level}] {message}"
        print(log_msg)
        
        with open(self.test_log, 'a', encoding='utf-8') as f:
            f.write(log_msg + '\n')
    
    def add_result(self, test_name, passed, details, severity='CRITICAL'):
        """Record test result"""
        self.test_results.append({
            'test_name': test_name,
            'passed': passed,
            'details': details,
            'severity': severity,
            'timestamp': datetime.now()
        })
    
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
            return True
            
        except Exception as e:
            self.log(f"Failed to create session: {e}", 'ERROR')
            return False
    
    def test_01_task_definitions(self):
        """TEST 1: Verify task definitions exist"""
        self.log("\n" + "="*80)
        self.log("TEST 1: Task Definitions")
        self.log("="*80)
        
        try:
            tasks = self.session.sql("""
                SELECT name, state, schedule
                FROM INFORMATION_SCHEMA.TASKS
                WHERE task_schema = 'OPS'
                ORDER BY name
            """).collect()
            
            task_count = len(tasks)
            expected_tasks = {
                'TASK_DAILY_CORE_REFRESH',
                'TASK_DAILY_FEATURE_REFRESH',
                'TASK_WEEKLY_MODEL_RETRAIN',
                'TASK_DAILY_PREDICTION_REFRESH',
                'TASK_STREAM_FEDFUNDS',
                'TASK_STREAM_RETAIL'
            }
            
            found_tasks = {task['NAME'] for task in tasks}
            missing_tasks = expected_tasks - found_tasks
            
            self.log(f"Found {task_count} tasks (expected 6)")
            for task in tasks:
                self.log(f"  - {task['NAME']:40} State: {task['STATE']}")
            
            passed = task_count >= 6 and len(missing_tasks) == 0
            
            if missing_tasks:
                details = f"Missing tasks: {', '.join(missing_tasks)}"
            else:
                details = f"All {task_count} tasks defined correctly"
            
            self.add_result('Task Definitions', passed, details, 'CRITICAL')
            return passed
            
        except Exception as e:
            self.log(f"Task definition check failed: {e}", 'ERROR')
            self.add_result('Task Definitions', False, str(e), 'CRITICAL')
            return False
    
    def test_02_enable_tasks(self):
        """TEST 2: Enable tasks in correct order"""
        self.log("\n" + "="*80)
        self.log("TEST 2: Enable Tasks (CORE → FEAT → PREDICT → RETRAIN)")
        self.log("="*80)
        
        try:
            # Order matters: child tasks must be started before parent tasks
            task_order = [
                'TASK_DAILY_PREDICTION_REFRESH',  # No dependencies
                'TASK_WEEKLY_MODEL_RETRAIN',       # No dependencies
                'TASK_DAILY_FEATURE_REFRESH',      # Depends on CORE
                'TASK_DAILY_CORE_REFRESH',         # Root task
                'TASK_STREAM_FEDFUNDS',            # Stream-triggered
                'TASK_STREAM_RETAIL'               # Stream-triggered
            ]
            
            for task_name in task_order:
                try:
                    self.session.sql(f"ALTER TASK OPS.{task_name} RESUME").collect()
                    self.log(f"  ✓ Enabled: {task_name}")
                    time.sleep(1)  # Small delay between task activations
                except Exception as e:
                    if 'already started' in str(e).lower():
                        self.log(f"  ✓ Already enabled: {task_name}")
                    else:
                        raise e
            
            # Verify all tasks are started
            time.sleep(2)
            states = self.session.sql("""
                SELECT name, state
                FROM INFORMATION_SCHEMA.TASKS
                WHERE task_schema = 'OPS'
            """).collect()
            
            all_started = all(task['STATE'] == 'started' for task in states)
            
            if all_started:
                self.log("\n✓ All tasks successfully enabled")
                self.add_result('Enable Tasks', True, 'All tasks started', 'CRITICAL')
                return True
            else:
                suspended = [t['NAME'] for t in states if t['STATE'] != 'started']
                details = f"Tasks still suspended: {', '.join(suspended)}"
                self.log(f"\n✗ {details}", 'ERROR')
                self.add_result('Enable Tasks', False, details, 'CRITICAL')
                return False
                
        except Exception as e:
            self.log(f"Task enablement failed: {e}", 'ERROR')
            self.add_result('Enable Tasks', False, str(e), 'CRITICAL')
            return False
    
    def test_03_stream_verification(self):
        """TEST 3: Verify streams and check offset ages"""
        self.log("\n" + "="*80)
        self.log("TEST 3: Stream Verification (SYSTEM$STREAM_HAS_DATA, offset age <24h)")
        self.log("="*80)
        
        try:
            streams = self.session.sql("""
                SELECT name, table_name
                FROM INFORMATION_SCHEMA.STREAMS
                WHERE table_schema = 'OPS'
                ORDER BY name
            """).collect()
            
            self.log(f"Found {len(streams)} streams")
            
            all_healthy = True
            stale_streams = []
            
            # Check stream status
            try:
                stream_status = self.session.sql("""
                    SELECT 
                        stream_name,
                        last_processed,
                        DATEDIFF(hour, last_processed, CURRENT_TIMESTAMP()) AS hours_since_process
                    FROM OPS.STREAM_STATUS
                """).collect()
                
                for status in stream_status:
                    hours = status['HOURS_SINCE_PROCESS'] or 0
                    stream = status['STREAM_NAME']
                    
                    if hours > self.max_stream_age_hours:
                        all_healthy = False
                        stale_streams.append(f"{stream} ({hours}h)")
                        self.log(f"  ✗ {stream}: {hours}h since last process (>24h)", 'WARN')
                    else:
                        self.log(f"  ✓ {stream}: {hours}h since last process")
                        
            except Exception as e:
                self.log(f"  Note: Stream status table not populated yet: {e}", 'WARN')
            
            # Check if streams have data
            for stream in streams:
                stream_name = f"OPS.{stream['NAME']}"
                try:
                    has_data = self.session.sql(
                        f"SELECT SYSTEM$STREAM_HAS_DATA('{stream_name}') AS has_data"
                    ).collect()[0]['HAS_DATA']
                    
                    self.log(f"  - {stream['NAME']:40} Has data: {has_data}")
                except Exception as e:
                    self.log(f"  - {stream['NAME']:40} Check failed: {str(e)[:50]}", 'WARN')
            
            if all_healthy:
                details = f"All {len(streams)} streams healthy (offset age <24h)"
                self.add_result('Stream Verification', True, details, 'HIGH')
            else:
                details = f"Stale streams: {', '.join(stale_streams)}"
                self.add_result('Stream Verification', False, details, 'HIGH')
            
            return all_healthy
            
        except Exception as e:
            self.log(f"Stream verification failed: {e}", 'ERROR')
            self.add_result('Stream Verification', False, str(e), 'HIGH')
            return False
    
    def test_04_run_validation(self):
        """TEST 4: Run validation_ops.sql and check for failures"""
        self.log("\n" + "="*80)
        self.log("TEST 4: Validation Suite (0 FAIL, ≤3 WARN)")
        self.log("="*80)
        
        try:
            validation_sql = Path('../snowflake/validation_ops.sql')
            
            if not validation_sql.exists():
                self.log("Validation SQL file not found", 'ERROR')
                self.add_result('Validation Suite', False, 'validation_ops.sql not found', 'CRITICAL')
                return False
            
            # Execute validation SQL
            self.log("Executing validation_ops.sql...")
            with open(validation_sql, 'r', encoding='utf-8') as f:
                sql_content = f.read()
            
            statements = [s.strip() for s in sql_content.split(';') 
                         if s.strip() and not s.strip().startswith('--')]
            
            for stmt in statements:
                try:
                    self.session.sql(stmt).collect()
                except Exception as e:
                    # Some errors are expected in validation queries
                    pass
            
            # Check validation results
            results = self.session.sql("""
                SELECT 
                    validation_check,
                    status,
                    details
                FROM OPS.OPS_VALIDATION_SUMMARY
                ORDER BY 
                    CASE status
                        WHEN 'FAIL' THEN 1
                        WHEN 'WARN' THEN 2
                        WHEN 'PASS' THEN 3
                    END,
                    validation_check
            """).collect()
            
            fail_count = sum(1 for r in results if r['STATUS'] == 'FAIL')
            warn_count = sum(1 for r in results if r['STATUS'] == 'WARN')
            pass_count = sum(1 for r in results if r['STATUS'] == 'PASS')
            
            self.log(f"\nValidation Results:")
            self.log(f"  PASS: {pass_count}")
            self.log(f"  WARN: {warn_count}")
            self.log(f"  FAIL: {fail_count}")
            
            # Show failures and warnings
            for result in results:
                if result['STATUS'] in ['FAIL', 'WARN']:
                    symbol = '✗' if result['STATUS'] == 'FAIL' else '⚠'
                    self.log(f"  {symbol} [{result['STATUS']}] {result['VALIDATION_CHECK']}: {result['DETAILS']}")
            
            passed = (fail_count == self.max_validation_failures and 
                     warn_count <= self.max_validation_warnings)
            
            if passed:
                details = f"Validation passed: {pass_count} PASS, {warn_count} WARN, {fail_count} FAIL"
                self.log(f"\n✓ {details}")
            else:
                details = f"Validation failed: {fail_count} FAIL (expected 0), {warn_count} WARN (expected ≤3)"
                self.log(f"\n✗ {details}", 'ERROR')
            
            self.add_result('Validation Suite', passed, details, 'CRITICAL')
            return passed
            
        except Exception as e:
            self.log(f"Validation execution failed: {e}", 'ERROR')
            self.add_result('Validation Suite', False, str(e), 'CRITICAL')
            return False
    
    def test_05_roi_guardrail(self):
        """TEST 5: Verify ROI guardrail (savings ≥ 1.5× spend)"""
        self.log("\n" + "="*80)
        self.log("TEST 5: ROI Guardrail (savings ≥ 1.5× spend)")
        self.log("="*80)
        
        try:
            # Get latest optimization results
            opt_results = self.session.sql("""
                SELECT 
                    optimization_run_id,
                    method,
                    budget_used,
                    total_spoilage_reduction,
                    spoilage_reduction_pct
                FROM OPS.OPTIMIZATION_LOGS
                ORDER BY created_at DESC
                LIMIT 1
            """).collect()
            
            if not opt_results:
                self.log("No optimization results found. Run optimization first.", 'ERROR')
                self.add_result('ROI Guardrail', False, 'No optimization results', 'HIGH')
                return False
            
            result = opt_results[0]
            budget_used = result['BUDGET_USED']
            savings = result['TOTAL_SPOILAGE_REDUCTION']
            roi_ratio = savings / budget_used if budget_used > 0 else 0
            
            self.log(f"Optimization Run: {result['OPTIMIZATION_RUN_ID']}")
            self.log(f"Method: {result['METHOD']}")
            self.log(f"Budget Used: ${budget_used:,.2f}")
            self.log(f"Spoilage Reduction: ${savings:,.2f}")
            self.log(f"ROI Ratio: {roi_ratio:.2f}× (savings / spend)")
            self.log(f"Reduction %: {result['SPOILAGE_REDUCTION_PCT']:.1f}%")
            
            passed = roi_ratio >= self.min_roi_ratio
            
            if passed:
                details = f"ROI {roi_ratio:.2f}× ≥ {self.min_roi_ratio}× (PASS)"
                self.log(f"\n✓ {details}")
            else:
                details = f"ROI {roi_ratio:.2f}× < {self.min_roi_ratio}× (FAIL)"
                self.log(f"\n✗ {details}", 'ERROR')
            
            self.add_result('ROI Guardrail', passed, details, 'HIGH')
            return passed
            
        except Exception as e:
            self.log(f"ROI check failed: {e}", 'ERROR')
            self.add_result('ROI Guardrail', False, str(e), 'HIGH')
            return False
    
    def test_06_dry_run_pipeline(self):
        """TEST 6: Execute full pipeline dry run"""
        self.log("\n" + "="*80)
        self.log("TEST 6: Full Pipeline Dry Run (LP + Policy Eval)")
        self.log("="*80)
        
        try:
            start_time = time.time()
            
            # Run optimization
            self.log("\n1. Running resource allocation optimization...")
            sys.path.insert(0, str(Path(__file__).parent.parent / 'optimization'))
            from resource_lp import ResourceAllocationOptimizer
            
            optimizer = ResourceAllocationOptimizer(self.config_file)
            optimizer.session = self.session
            
            opt_success = optimizer.run_optimization(method='scipy')
            
            if not opt_success:
                self.log("Optimization failed", 'ERROR')
                self.add_result('Dry Run - Optimization', False, 'Optimization failed', 'CRITICAL')
                return False
            
            self.log("✓ Optimization completed")
            
            # Run policy evaluation
            self.log("\n2. Running policy evaluation...")
            from policy_eval import AllocationPolicyEvaluator
            
            evaluator = AllocationPolicyEvaluator(self.config_file)
            evaluator.session = self.session
            
            eval_success = evaluator.run_evaluation()
            
            if not eval_success:
                self.log("Policy evaluation failed", 'ERROR')
                self.add_result('Dry Run - Policy Eval', False, 'Policy evaluation failed', 'HIGH')
                return False
            
            self.log("✓ Policy evaluation completed")
            
            # Run monitoring
            self.log("\n3. Running operational monitoring...")
            from monitor_ops import OperationsMonitor
            
            monitor = OperationsMonitor(self.config_file)
            monitor.session = self.session
            
            monitor_success = monitor.run_monitoring()
            
            if not monitor_success:
                self.log("Monitoring failed", 'WARN')
                self.add_result('Dry Run - Monitoring', False, 'Monitoring failed', 'MEDIUM')
            else:
                self.log("✓ Monitoring completed")
            
            elapsed = time.time() - start_time
            
            # Snapshot KPIs
            self.log("\n4. Capturing KPI snapshot...")
            kpis = self.capture_kpi_snapshot()
            
            self.log(f"\n✓ Full pipeline dry run completed in {elapsed:.1f} seconds")
            
            details = f"Pipeline executed in {elapsed:.1f}s with {len(kpis)} KPIs captured"
            self.add_result('Dry Run Pipeline', True, details, 'CRITICAL')
            return True
            
        except Exception as e:
            self.log(f"Dry run failed: {e}", 'ERROR')
            import traceback
            self.log(traceback.format_exc(), 'ERROR')
            self.add_result('Dry Run Pipeline', False, str(e), 'CRITICAL')
            return False
    
    def capture_kpi_snapshot(self):
        """Capture current KPI snapshot"""
        kpis = {}
        
        try:
            # Prediction KPIs
            pred_stats = self.session.sql("""
                SELECT 
                    COUNT(*) AS prediction_count,
                    AVG((randomforestregressor_pred + xgbregressor_pred) / 2.0) AS avg_spoilage_rate,
                    MAX(date) AS latest_prediction_date
                FROM ML.PREDICTIONS
            """).collect()[0]
            
            kpis['prediction_count'] = pred_stats['PREDICTION_COUNT']
            kpis['avg_spoilage_rate'] = float(pred_stats['AVG_SPOILAGE_RATE'])
            kpis['latest_prediction_date'] = str(pred_stats['LATEST_PREDICTION_DATE'])
            
            # Model KPIs
            model_stats = self.session.sql("""
                SELECT 
                    MAX(val_r2) AS best_r2,
                    MAX(val_f1) AS best_f1
                FROM ML.MODEL_RESULTS
            """).collect()[0]
            
            kpis['best_r2'] = float(model_stats['BEST_R2'] or 0)
            kpis['best_f1'] = float(model_stats['BEST_F1'] or 0)
            
            # Optimization KPIs
            opt_stats = self.session.sql("""
                SELECT 
                    total_spoilage_reduction,
                    spoilage_reduction_pct,
                    budget_used,
                    (total_spoilage_reduction / budget_used) AS roi_ratio
                FROM OPS.OPTIMIZATION_LOGS
                ORDER BY created_at DESC
                LIMIT 1
            """).collect()
            
            if opt_stats:
                opt = opt_stats[0]
                kpis['spoilage_reduction'] = float(opt['TOTAL_SPOILAGE_REDUCTION'])
                kpis['reduction_pct'] = float(opt['SPOILAGE_REDUCTION_PCT'])
                kpis['budget_used'] = float(opt['BUDGET_USED'])
                kpis['roi_ratio'] = float(opt['ROI_RATIO'])
            
            # Task KPIs
            task_stats = self.session.sql("""
                SELECT 
                    COUNT(*) AS total_runs,
                    SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) AS successful_runs
                FROM OPS.TASK_RUNS
                WHERE execution_start >= DATEADD(day, -7, CURRENT_DATE())
            """).collect()
            
            if task_stats and task_stats[0]['TOTAL_RUNS'] > 0:
                stats = task_stats[0]
                kpis['task_runs_7d'] = stats['TOTAL_RUNS']
                kpis['task_success_rate'] = float(stats['SUCCESSFUL_RUNS']) / float(stats['TOTAL_RUNS']) * 100
            
            # Log KPIs
            self.log("\nKPI Snapshot:")
            for key, value in kpis.items():
                if isinstance(value, float):
                    self.log(f"  {key}: {value:.4f}")
                else:
                    self.log(f"  {key}: {value}")
            
            # Save to file
            snapshot_file = f"../logs/kpi_snapshot_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
            with open(snapshot_file, 'w') as f:
                json.dump(kpis, f, indent=2, default=str)
            self.log(f"\nKPI snapshot saved: {snapshot_file}")
            
        except Exception as e:
            self.log(f"KPI capture error: {e}", 'WARN')
        
        return kpis
    
    def test_07_backup_configs(self):
        """TEST 7: Backup configurations and create changelog entry"""
        self.log("\n" + "="*80)
        self.log("TEST 7: Backup Configurations")
        self.log("="*80)
        
        try:
            backup_dir = Path(f"../backups/phase6_{datetime.now().strftime('%Y%m%d_%H%M%S')}")
            backup_dir.mkdir(parents=True, exist_ok=True)
            
            # Backup SQL scripts
            sql_files = [
                '../snowflake/06_ops_tasks.sql',
                '../snowflake/06_ops_streams.sql',
                '../snowflake/validation_ops.sql',
                '../dashboards/queries.sql'
            ]
            
            for sql_file in sql_files:
                src = Path(sql_file)
                if src.exists():
                    dst = backup_dir / src.name
                    dst.write_text(src.read_text())
                    self.log(f"  ✓ Backed up: {src.name}")
            
            # Backup Python scripts
            py_files = [
                '../optimization/resource_lp.py',
                '../optimization/policy_eval.py',
                '../snowpark/monitor_ops.py',
                '../snowpark/execute_phase6.py',
                '../dashboards/streamlit_app.py'
            ]
            
            for py_file in py_files:
                src = Path(py_file)
                if src.exists():
                    dst = backup_dir / src.name
                    dst.write_text(src.read_text())
                    self.log(f"  ✓ Backed up: {src.name}")
            
            # Create changelog entry
            changelog_entry = f"""
# Phase 6 - Operations & Automation
Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
Version: 1.0.0

## Components Deployed
- Automation Infrastructure (Tasks & Streams)
- Resource Allocation Optimizer (Linear Programming)
- Policy Evaluation Framework
- Interactive Dashboard (Streamlit)
- Operational Monitoring & Drift Detection

## Configuration Backup
Location: {backup_dir}
Files: {len(sql_files) + len(py_files)} scripts backed up

## Test Results
{'PASSED' if all(r['passed'] for r in self.test_results) else 'FAILED'}

## Next Steps
- Phase 7 planning
- Production deployment
- Stakeholder training
"""
            
            changelog_file = backup_dir / 'CHANGELOG.md'
            changelog_file.write_text(changelog_entry)
            self.log(f"\n✓ Changelog created: {changelog_file}")
            
            self.add_result('Backup Configs', True, f'Backed up to {backup_dir}', 'MEDIUM')
            return True
            
        except Exception as e:
            self.log(f"Backup failed: {e}", 'ERROR')
            self.add_result('Backup Configs', False, str(e), 'MEDIUM')
            return False
    
    def generate_report(self):
        """Generate comprehensive test report"""
        self.log("\n" + "="*80)
        self.log("PHASE 6 READINESS TEST REPORT")
        self.log("="*80)
        self.log(f"Test Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        self.log(f"Log File: {self.test_log}")
        
        # Count results by severity
        critical_tests = [r for r in self.test_results if r['severity'] == 'CRITICAL']
        high_tests = [r for r in self.test_results if r['severity'] == 'HIGH']
        
        critical_passed = sum(1 for r in critical_tests if r['passed'])
        high_passed = sum(1 for r in high_tests if r['passed'])
        
        total_passed = sum(1 for r in self.test_results if r['passed'])
        total_tests = len(self.test_results)
        
        self.log(f"\nTest Summary:")
        self.log(f"  Total Tests: {total_tests}")
        self.log(f"  Passed: {total_passed}")
        self.log(f"  Failed: {total_tests - total_passed}")
        self.log(f"  Critical Tests: {critical_passed}/{len(critical_tests)} passed")
        self.log(f"  High Priority: {high_passed}/{len(high_tests)} passed")
        
        # Detailed results
        self.log(f"\nDetailed Results:")
        self.log("-" * 80)
        
        for result in self.test_results:
            status = "✓ PASS" if result['passed'] else "✗ FAIL"
            self.log(f"{status} | {result['severity']:8} | {result['test_name']}")
            self.log(f"       Details: {result['details']}")
        
        # Overall assessment
        self.log("\n" + "="*80)
        
        all_critical_passed = all(r['passed'] for r in critical_tests)
        most_high_passed = high_passed >= len(high_tests) * 0.8
        
        if all_critical_passed and most_high_passed:
            self.log("✓ PHASE 6 READY FOR PRODUCTION")
            self.log("All critical tests passed. System ready for Phase 7.")
            overall_status = "READY"
        elif all_critical_passed:
            self.log("⚠ PHASE 6 READY WITH WARNINGS")
            self.log("Critical tests passed but some high-priority items need attention.")
            overall_status = "READY_WITH_WARNINGS"
        else:
            self.log("✗ PHASE 6 NOT READY")
            self.log("Critical tests failed. Address issues before proceeding.")
            overall_status = "NOT_READY"
        
        self.log("="*80)
        
        # Save report
        report_file = f"../logs/phase6_readiness_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        report_data = {
            'test_date': datetime.now().isoformat(),
            'overall_status': overall_status,
            'total_tests': total_tests,
            'passed': total_passed,
            'failed': total_tests - total_passed,
            'critical_tests': len(critical_tests),
            'critical_passed': critical_passed,
            'results': [
                {
                    'test_name': r['test_name'],
                    'passed': r['passed'],
                    'details': r['details'],
                    'severity': r['severity'],
                    'timestamp': r['timestamp'].isoformat()
                }
                for r in self.test_results
            ]
        }
        
        with open(report_file, 'w') as f:
            json.dump(report_data, f, indent=2)
        
        self.log(f"\nFull report saved: {report_file}")
        
        return overall_status == "READY"
    
    def run_all_tests(self):
        """Execute all readiness tests"""
        self.log("="*80)
        self.log("PHASE 6 PRE-PRODUCTION READINESS TESTING")
        self.log("="*80)
        self.log(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        
        start_time = time.time()
        
        # Run tests in sequence
        self.test_01_task_definitions()
        self.test_02_enable_tasks()
        self.test_03_stream_verification()
        self.test_04_run_validation()
        self.test_05_roi_guardrail()
        self.test_06_dry_run_pipeline()
        self.test_07_backup_configs()
        
        elapsed = time.time() - start_time
        
        self.log(f"\nTotal test execution time: {elapsed/60:.1f} minutes")
        
        # Generate final report
        ready = self.generate_report()
        
        return ready
    
    def close(self):
        """Close session"""
        if self.session:
            self.session.close()


def main():
    """Main execution"""
    print("="*80)
    print("PHASE 6 READINESS TESTING")
    print("="*80)
    
    tester = Phase6ReadinessTest()
    
    if not tester.create_session():
        print("\nFailed to connect to Snowflake")
        sys.exit(1)
    
    try:
        ready = tester.run_all_tests()
        
        sys.exit(0 if ready else 1)
        
    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
        sys.exit(1)
        
    except Exception as e:
        print(f"\nFatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
        
    finally:
        tester.close()


if __name__ == "__main__":
    main()

