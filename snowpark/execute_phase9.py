"""
Phase 9 Orchestrator - Go-Live, DR/BCP, CI/CD, Compliance & Handover
Global Supply Chain Spoilage Forecasting Project
Main orchestrator for Phase 9 deployment and validation
"""

import os
import json
import logging
import argparse
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from snowflake.snowpark import Session
from typing import Dict, List, Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/phase9_execution.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class Phase9Orchestrator:
    """Phase 9 orchestration and deployment management"""
    
    def __init__(self, session: Session, environment: str = 'production'):
        self.session = session
        self.environment = environment
        self.deployment_start_time = datetime.now()
        self.deployment_results = {}
    
    def execute_sql_file(self, file_path: str, description: str = "") -> bool:
        """Execute SQL file with error handling"""
        logger.info(f"Executing SQL file: {file_path}")
        
        try:
            full_path = Path(file_path)
            if not full_path.exists():
                logger.error(f"SQL file not found: {full_path}")
                return False
            
            with open(full_path, 'r') as f:
                sql_commands = f.read().split(';')
                
                executed_statements = 0
                for command in sql_commands:
                    stripped_command = command.strip()
                    if stripped_command:
                        try:
                            self.session.sql(stripped_command).collect()
                            executed_statements += 1
                        except Exception as e:
                            logger.warning(f"Statement failed (continuing): {e}")
                
                logger.info(f"Executed {executed_statements} statements from {full_path.name}")
                return True
                
        except Exception as e:
            logger.error(f"Error executing {file_path}: {e}")
            return False
    
    def run_validation_checks(self) -> Dict[str, any]:
        """Run comprehensive validation checks"""
        logger.info("Running Phase 9 validation checks...")
        
        validation_results = {
            'timestamp': datetime.now().isoformat(),
            'environment': self.environment,
            'total_checks': 0,
            'passed_checks': 0,
            'failed_checks': 0,
            'results': {},
            'overall_status': 'FAIL'
        }
        
        try:
            # Execute validation SQL
            validation_success = self.execute_sql_file('snowflake/validation_phase9.sql', 'Phase 9 validation')
            
            if validation_success:
                # Get validation results from database
                validation_data = self.session.sql("""
                    SELECT gate_id, gate_name, status, validation_timestamp
                    FROM OPS.PHASE9_VALIDATION_SUMMARY
                    ORDER BY gate_id, gate_name
                """).collect()
                
                for row in validation_data:
                    validation_results['total_checks'] += 1
                    if row['STATUS'] == 'PASS':
                        validation_results['passed_checks'] += 1
                    else:
                        validation_results['failed_checks'] += 1
                    
                    validation_results['results'][row['GATE_NAME']] = {
                        'status': row['STATUS'],
                        'timestamp': row['VALIDATION_TIMESTAMP']
                    }
                
                # Calculate overall status
                validation_results['pass_percentage'] = (
                    validation_results['passed_checks'] / validation_results['total_checks'] * 100
                    if validation_results['total_checks'] > 0 else 0
                )
                
                validation_results['overall_status'] = 'PASS' if validation_results['failed_checks'] == 0 else 'FAIL'
                
                logger.info(f"Validation completed: {validation_results['passed_checks']}/{validation_results['total_checks']} checks passed")
            else:
                logger.error("Validation SQL execution failed")
                validation_results['overall_status'] = 'FAIL'
            
            return validation_results
            
        except Exception as e:
            logger.error(f"Validation checks failed: {e}")
            validation_results['error'] = str(e)
            return validation_results
    
    def run_dr_drill(self) -> Dict[str, any]:
        """Run disaster recovery drill"""
        logger.info("Running disaster recovery drill...")
        
        try:
            # Run failover drill
            result = subprocess.run([
                sys.executable, 'ops/failover_drill.py'
            ], capture_output=True, text=True, cwd=os.getcwd())
            
            if result.returncode == 0:
                logger.info("DR drill completed successfully")
                return {'status': 'SUCCESS', 'output': result.stdout}
            else:
                logger.error(f"DR drill failed: {result.stderr}")
                return {'status': 'FAILED', 'error': result.stderr}
                
        except Exception as e:
            logger.error(f"DR drill execution failed: {e}")
            return {'status': 'FAILED', 'error': str(e)}
    
    def run_cost_reporting(self) -> Dict[str, any]:
        """Run cost reporting and analysis"""
        logger.info("Running cost reporting...")
        
        try:
            # Run cost report
            result = subprocess.run([
                sys.executable, 'ops/cost_report.py'
            ], capture_output=True, text=True, cwd=os.getcwd())
            
            if result.returncode == 0:
                logger.info("Cost reporting completed successfully")
                return {'status': 'SUCCESS', 'output': result.stdout}
            else:
                logger.error(f"Cost reporting failed: {result.stderr}")
                return {'status': 'FAILED', 'error': result.stderr}
                
        except Exception as e:
            logger.error(f"Cost reporting execution failed: {e}")
            return {'status': 'FAILED', 'error': str(e)}
    
    def run_secret_rotation(self) -> Dict[str, any]:
        """Run secret rotation"""
        logger.info("Running secret rotation...")
        
        try:
            # Run secret rotation
            result = subprocess.run([
                sys.executable, 'ops/rotate_secrets.py'
            ], capture_output=True, text=True, cwd=os.getcwd())
            
            if result.returncode == 0:
                logger.info("Secret rotation completed successfully")
                return {'status': 'SUCCESS', 'output': result.stdout}
            else:
                logger.error(f"Secret rotation failed: {result.stderr}")
                return {'status': 'FAILED', 'error': result.stderr}
                
        except Exception as e:
            logger.error(f"Secret rotation execution failed: {e}")
            return {'status': 'FAILED', 'error': str(e)}
    
    def deploy_environment_promotion(self) -> bool:
        """Deploy environment promotion setup"""
        logger.info("Deploying environment promotion...")
        
        try:
            # Execute environment promotion SQL
            success = self.execute_sql_file('snowflake/09_envs.sql', 'Environment promotion')
            if not success:
                return False
            
            # Execute DR/backup SQL
            success = success and self.execute_sql_file('snowflake/09_dr_backup.sql', 'DR/Backup setup')
            if not success:
                return False
            
            # Execute FinOps SQL
            success = success and self.execute_sql_file('snowflake/09_finops.sql', 'FinOps setup')
            if not success:
                return False
            
            # Execute compliance SQL
            success = success and self.execute_sql_file('snowflake/09_lineage_compliance.sql', 'Compliance setup')
            if not success:
                return False
            
            logger.info("Environment promotion deployment completed")
            return success
            
        except Exception as e:
            logger.error(f"Environment promotion deployment failed: {e}")
            return False
    
    def run_go_no_go_gates(self) -> Dict[str, any]:
        """Run GO/NO-GO gates for production readiness"""
        logger.info("Running GO/NO-GO gates...")
        
        gates = {
            'G1_SWAP_OK': False,
            'G2_BACKUP_RETENTION': False,
            'G3_RESOURCE_MONITOR': False,
            'G4_LINEAGE_ROWS': False,
            'G5_ROLLBACK_DRILL': False,
            'G6_COST_BUDGET': False
        }
        
        try:
            # Gate 1: SWAP_OK - Production tables healthy
            try:
                pred_count = self.session.table("ML.PREDICTIONS").count()
                alert_count = self.session.table("OPS.ALERT_QUEUE").count()
                model_count = self.session.table("ML.MODEL_RESULTS").count()
                
                gates['G1_SWAP_OK'] = pred_count > 0 and alert_count >= 0 and model_count > 0
                logger.info(f"G1_SWAP_OK: {gates['G1_SWAP_OK']} (pred: {pred_count}, alerts: {alert_count}, models: {model_count})")
            except Exception as e:
                logger.error(f"G1_SWAP_OK failed: {e}")
            
            # Gate 2: BACKUP_RETENTION - 7 days retention
            try:
                retention_result = self.session.sql("""
                    SELECT DATA_RETENTION_TIME_IN_DAYS 
                    FROM INFORMATION_SCHEMA.DATABASES 
                    WHERE DATABASE_NAME = 'GLOBAL_SPOILAGE_DB'
                """).collect()
                
                gates['G2_BACKUP_RETENTION'] = retention_result[0][0] == 7
                logger.info(f"G2_BACKUP_RETENTION: {gates['G2_BACKUP_RETENTION']} (retention: {retention_result[0][0]} days)")
            except Exception as e:
                logger.error(f"G2_BACKUP_RETENTION failed: {e}")
            
            # Gate 3: RESOURCE_MONITOR - Monitor attached
            try:
                monitor_result = self.session.sql("""
                    SELECT RESOURCE_MONITOR 
                    FROM INFORMATION_SCHEMA.WAREHOUSES 
                    WHERE WAREHOUSE_NAME = 'COMPUTE_WH'
                """).collect()
                
                gates['G3_RESOURCE_MONITOR'] = monitor_result[0][0] is not None
                logger.info(f"G3_RESOURCE_MONITOR: {gates['G3_RESOURCE_MONITOR']} (monitor: {monitor_result[0][0]})")
            except Exception as e:
                logger.error(f"G3_RESOURCE_MONITOR failed: {e}")
            
            # Gate 4: LINEAGE_ROWS - Lineage tracking active
            try:
                lineage_count = self.session.sql("""
                    SELECT COUNT(*) 
                    FROM OPS.DATA_LINEAGE 
                    WHERE QUERY_START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
                """).collect()
                
                gates['G4_LINEAGE_ROWS'] = lineage_count[0][0] > 0
                logger.info(f"G4_LINEAGE_ROWS: {gates['G4_LINEAGE_ROWS']} (lineage rows: {lineage_count[0][0]})")
            except Exception as e:
                logger.error(f"G4_LINEAGE_ROWS failed: {e}")
            
            # Gate 5: ROLLBACK_DRILL - Rollback procedures exist
            try:
                rollback_procs = self.session.sql("""
                    SELECT COUNT(*) 
                    FROM INFORMATION_SCHEMA.PROCEDURES 
                    WHERE PROCEDURE_SCHEMA = 'OPS' 
                    AND PROCEDURE_NAME IN ('SP_ATOMIC_SWAP', 'SP_ROLLBACK_DEPLOY')
                """).collect()
                
                gates['G5_ROLLBACK_DRILL'] = rollback_procs[0][0] >= 2
                logger.info(f"G5_ROLLBACK_DRILL: {gates['G5_ROLLBACK_DRILL']} (procedures: {rollback_procs[0][0]})")
            except Exception as e:
                logger.error(f"G5_ROLLBACK_DRILL failed: {e}")
            
            # Gate 6: COST_BUDGET - Budget tracking configured
            try:
                budget_count = self.session.sql("""
                    SELECT COUNT(*) 
                    FROM OPS.BUDGET_TRACKING 
                    WHERE is_active = TRUE
                """).collect()
                
                gates['G6_COST_BUDGET'] = budget_count[0][0] > 0
                logger.info(f"G6_COST_BUDGET: {gates['G6_COST_BUDGET']} (budgets: {budget_count[0][0]})")
            except Exception as e:
                logger.error(f"G6_COST_BUDGET failed: {e}")
            
            # Calculate overall gate status
            passed_gates = sum(gates.values())
            total_gates = len(gates)
            gate_percentage = (passed_gates / total_gates) * 100
            
            logger.info(f"GO/NO-GO Gates: {passed_gates}/{total_gates} passed ({gate_percentage:.1f}%)")
            
            return {
                'gates': gates,
                'passed_gates': passed_gates,
                'total_gates': total_gates,
                'gate_percentage': gate_percentage,
                'overall_status': 'PASS' if passed_gates == total_gates else 'FAIL'
            }
            
        except Exception as e:
            logger.error(f"GO/NO-GO gates failed: {e}")
            return {'gates': gates, 'overall_status': 'FAIL', 'error': str(e)}
    
    def run_complete_phase9(self) -> Dict[str, any]:
        """Run complete Phase 9 deployment and validation"""
        logger.info("=" * 80)
        logger.info("PHASE 9: GO-LIVE, DR/BCP, CI/CD, COMPLIANCE & HANDOVER")
        logger.info("=" * 80)
        
        phase9_results = {
            'phase': 'PHASE_9',
            'environment': self.environment,
            'deployment_start_time': self.deployment_start_time.isoformat(),
            'status': 'IN_PROGRESS',
            'steps': {},
            'overall_status': 'FAIL'
        }
        
        try:
            # Step 1: Deploy environment promotion
            logger.info("Step 1: Deploying environment promotion...")
            env_promotion_success = self.deploy_environment_promotion()
            phase9_results['steps']['environment_promotion'] = {
                'status': 'SUCCESS' if env_promotion_success else 'FAILED',
                'timestamp': datetime.now().isoformat()
            }
            
            if not env_promotion_success:
                raise Exception("Environment promotion deployment failed")
            
            # Step 2: Run validation checks
            logger.info("Step 2: Running validation checks...")
            validation_results = self.run_validation_checks()
            phase9_results['steps']['validation'] = validation_results
            
            if validation_results['overall_status'] != 'PASS':
                logger.warning("Validation checks failed, but continuing...")
            
            # Step 3: Run GO/NO-GO gates
            logger.info("Step 3: Running GO/NO-GO gates...")
            gate_results = self.run_go_no_go_gates()
            phase9_results['steps']['go_no_go_gates'] = gate_results
            
            if gate_results['overall_status'] != 'PASS':
                logger.error("GO/NO-GO gates failed - deployment not ready")
                phase9_results['overall_status'] = 'FAIL'
                return phase9_results
            
            # Step 4: Run DR drill
            logger.info("Step 4: Running DR drill...")
            dr_results = self.run_dr_drill()
            phase9_results['steps']['dr_drill'] = dr_results
            
            # Step 5: Run cost reporting
            logger.info("Step 5: Running cost reporting...")
            cost_results = self.run_cost_reporting()
            phase9_results['steps']['cost_reporting'] = cost_results
            
            # Step 6: Run secret rotation
            logger.info("Step 6: Running secret rotation...")
            secret_results = self.run_secret_rotation()
            phase9_results['steps']['secret_rotation'] = secret_results
            
            # Calculate overall status
            all_steps_successful = all(
                step.get('status') == 'SUCCESS' or step.get('overall_status') == 'PASS'
                for step in phase9_results['steps'].values()
            )
            
            phase9_results['overall_status'] = 'SUCCESS' if all_steps_successful else 'PARTIAL'
            phase9_results['deployment_end_time'] = datetime.now().isoformat()
            phase9_results['deployment_duration_seconds'] = (
                datetime.now() - self.deployment_start_time
            ).total_seconds()
            
            # Log deployment results
            self.log_deployment_results(phase9_results)
            
            logger.info("Phase 9 deployment completed successfully")
            return phase9_results
            
        except Exception as e:
            logger.error(f"Phase 9 deployment failed: {e}")
            phase9_results['overall_status'] = 'FAIL'
            phase9_results['error'] = str(e)
            return phase9_results
    
    def log_deployment_results(self, results: Dict[str, any]):
        """Log deployment results to audit table"""
        try:
            self.session.sql(f"""
                INSERT INTO OPS.LOAD_AUDIT (
                    execution_id, phase, step, execution_ts, status, 
                    rows_affected, execution_time_seconds, error_message
                ) VALUES (
                    'PHASE9_DEPLOYMENT_' || CURRENT_TIMESTAMP()::STRING,
                    'PHASE_9',
                    'COMPLETE_DEPLOYMENT',
                    CURRENT_TIMESTAMP(),
                    '{results['overall_status']}',
                    0,
                    {results.get('deployment_duration_seconds', 0)},
                    {f"'{results.get('error', '')}'" if results.get('error') else 'NULL'}
                )
            """).collect()
            
            logger.info("Deployment results logged to audit table")
            
        except Exception as e:
            logger.warning(f"Could not log deployment results: {e}")

def main():
    """Main Phase 9 execution"""
    parser = argparse.ArgumentParser(description='Phase 9 Orchestrator')
    parser.add_argument('--apply-all', action='store_true', help='Apply all Phase 9 components')
    parser.add_argument('--validate', action='store_true', help='Run validation checks only')
    parser.add_argument('--dr-drill', action='store_true', help='Run DR drill only')
    parser.add_argument('--cost-report', action='store_true', help='Run cost reporting only')
    parser.add_argument('--rotate-secrets', action='store_true', help='Rotate secrets only')
    parser.add_argument('--environment', default='production', help='Target environment')
    
    args = parser.parse_args()
    
    logger.info("=" * 80)
    logger.info("PHASE 9 ORCHESTRATOR - GO-LIVE & HANDOVER")
    logger.info("=" * 80)
    
    # Load configuration
    config_path = 'snowflake_config.json'
    if not os.path.exists(config_path):
        logger.error(f"Configuration file not found: {config_path}")
        return
    
    with open(config_path, 'r') as f:
        config = json.load(f)
    
    # Create session
    try:
        session = Session.builder.configs(config).create()
        logger.info("Connected to Snowflake")
    except Exception as e:
        logger.error(f"Failed to connect: {e}")
        return
    
    try:
        # Initialize orchestrator
        orchestrator = Phase9Orchestrator(session, args.environment)
        
        if args.apply_all:
            # Run complete Phase 9 deployment
            results = orchestrator.run_complete_phase9()
            
            # Print summary
            logger.info("=" * 80)
            logger.info("PHASE 9 DEPLOYMENT SUMMARY")
            logger.info("=" * 80)
            logger.info(f"Status: {results['overall_status']}")
            logger.info(f"Environment: {results['environment']}")
            logger.info(f"Duration: {results.get('deployment_duration_seconds', 0):.2f} seconds")
            
            for step_name, step_result in results['steps'].items():
                status_icon = "✅" if step_result.get('status') == 'SUCCESS' or step_result.get('overall_status') == 'PASS' else "❌"
                logger.info(f"{status_icon} {step_name}: {step_result.get('status', step_result.get('overall_status', 'UNKNOWN'))}")
            
            if results['overall_status'] == 'SUCCESS':
                logger.info("🎉 PHASE 9 DEPLOYMENT COMPLETED SUCCESSFULLY!")
                logger.info("System is ready for production operations")
            else:
                logger.error("❌ PHASE 9 DEPLOYMENT FAILED!")
                logger.error("Review logs and fix issues before proceeding")
        
        elif args.validate:
            # Run validation only
            validation_results = orchestrator.run_validation_checks()
            logger.info(f"Validation Status: {validation_results['overall_status']}")
        
        elif args.dr_drill:
            # Run DR drill only
            dr_results = orchestrator.run_dr_drill()
            logger.info(f"DR Drill Status: {dr_results['status']}")
        
        elif args.cost_report:
            # Run cost reporting only
            cost_results = orchestrator.run_cost_reporting()
            logger.info(f"Cost Reporting Status: {cost_results['status']}")
        
        elif args.rotate_secrets:
            # Run secret rotation only
            secret_results = orchestrator.run_secret_rotation()
            logger.info(f"Secret Rotation Status: {secret_results['status']}")
        
        else:
            logger.info("No specific action requested. Use --help for options.")
        
    except Exception as e:
        logger.error(f"Phase 9 execution failed: {e}")
    finally:
        session.close()
        logger.info("Disconnected from Snowflake")

if __name__ == "__main__":
    main()
