"""
EWS Engine - Early Warning System Engine
Global Supply Chain Spoilage Forecasting Project
Rule evaluation, deduplication, enqueue, and escalation
"""

import os
import json
import logging
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from pathlib import Path
from snowflake.snowpark import Session
from typing import Dict, List, Optional, Tuple

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/ews_engine.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class EWSEngine:
    """Early Warning System Engine for alert processing"""
    
    def __init__(self, session: Session):
        self.session = session
        self.alert_rules = {}
        self.watchlists = {}
        self.load_configuration()
    
    def load_configuration(self):
        """Load EWS configuration from database"""
        try:
            # Load alert rules
            rules_df = self.session.table("OPS.ALERT_RULES").to_pandas()
            self.alert_rules = rules_df.set_index('rule_id').to_dict('index')
            logger.info(f"Loaded {len(self.alert_rules)} alert rules")
            
            # Load watchlists
            watchlists_df = self.session.table("OPS.WATCHLISTS").to_pandas()
            self.watchlists = watchlists_df.set_index('watch_id').to_dict('index')
            logger.info(f"Loaded {len(self.watchlists)} watchlist entries")
            
        except Exception as e:
            logger.error(f"Error loading EWS configuration: {e}")
            raise
    
    def get_candidates(self) -> pd.DataFrame:
        """Get alert candidates from the database"""
        try:
            candidates_df = self.session.table("OPS.ALERT_CANDIDATES").to_pandas()
            logger.info(f"Retrieved {len(candidates_df)} alert candidates")
            return candidates_df
        except Exception as e:
            logger.error(f"Error retrieving alert candidates: {e}")
            return pd.DataFrame()
    
    def evaluate_rules(self, candidates_df: pd.DataFrame) -> pd.DataFrame:
        """Evaluate alert rules against candidates"""
        try:
            if candidates_df.empty:
                return pd.DataFrame()
            
            # Apply each rule
            rule_results = []
            
            for rule_id, rule in self.alert_rules.items():
                if not rule['enabled']:
                    continue
                
                # Apply rule predicate (simplified evaluation)
                rule_matches = self._apply_rule_predicate(candidates_df, rule)
                
                if not rule_matches.empty:
                    rule_matches['rule_id'] = rule_id
                    rule_matches['rule_name'] = rule['name']
                    rule_matches['severity'] = rule['severity']
                    rule_matches['escalation_policy'] = rule['escalation_policy']
                    rule_results.append(rule_matches)
            
            if rule_results:
                result_df = pd.concat(rule_results, ignore_index=True)
                logger.info(f"Rule evaluation produced {len(result_df)} matches")
                return result_df
            else:
                return pd.DataFrame()
                
        except Exception as e:
            logger.error(f"Error evaluating rules: {e}")
            return pd.DataFrame()
    
    def _apply_rule_predicate(self, candidates_df: pd.DataFrame, rule: Dict) -> pd.DataFrame:
        """Apply a single rule predicate to candidates"""
        try:
            # Simplified rule evaluation (in production, would use SQL evaluation)
            if rule['name'] == 'HIGH_RISK_IMMEDIATE':
                return candidates_df[
                    (candidates_df['probability'] >= 0.80) & 
                    (candidates_df['is_watched'] == True)
                ]
            elif rule['name'] == 'HIGH_RISK_WEEKLY':
                return candidates_df[
                    (candidates_df['probability'] >= 0.75) & 
                    (candidates_df['is_watched'] == True)
                ]
            elif rule['name'] == 'MEDIUM_RISK_MONTHLY':
                return candidates_df[
                    (candidates_df['probability'] >= 0.60) & 
                    (candidates_df['is_watched'] == True)
                ]
            elif rule['name'] == 'LOW_RISK_QUARTERLY':
                return candidates_df[
                    (candidates_df['probability'] >= 0.40) & 
                    (candidates_df['is_watched'] == True)
                ]
            elif rule['name'] == 'CRITICAL_COUNTRY_RISK':
                critical_countries = ['US', 'CN', 'DE', 'JP', 'GB']
                return candidates_df[
                    (candidates_df['probability'] >= 0.70) & 
                    (candidates_df['country'].isin(critical_countries))
                ]
            elif rule['name'] == 'SUPPLY_CHAIN_DISRUPTION':
                critical_sectors = ['MANUFACTURING', 'LOGISTICS', 'AGRICULTURE']
                return candidates_df[
                    (candidates_df['probability'] >= 0.65) & 
                    (candidates_df['sector'].isin(critical_sectors))
                ]
            else:
                return pd.DataFrame()
                
        except Exception as e:
            logger.error(f"Error applying rule predicate: {e}")
            return pd.DataFrame()
    
    def deduplicate_alerts(self, alerts_df: pd.DataFrame) -> pd.DataFrame:
        """Remove duplicate alerts based on dedup_key"""
        try:
            if alerts_df.empty:
                return pd.DataFrame()
            
            # Check for existing alerts in queue
            existing_alerts = self.session.sql("""
                SELECT dedup_key, status 
                FROM OPS.ALERT_QUEUE 
                WHERE status IN ('NEW', 'ACKNOWLEDGED', 'INVESTIGATING')
            """).to_pandas()
            
            if not existing_alerts.empty:
                existing_keys = set(existing_alerts['dedup_key'])
                # Filter out duplicates
                new_alerts = alerts_df[~alerts_df['dedup_key'].isin(existing_keys)]
                logger.info(f"Deduplication: {len(alerts_df)} -> {len(new_alerts)} alerts")
                return new_alerts
            else:
                return alerts_df
                
        except Exception as e:
            logger.error(f"Error deduplicating alerts: {e}")
            return alerts_df
    
    def enqueue_alerts(self, alerts_df: pd.DataFrame) -> int:
        """Enqueue new alerts to the alert queue"""
        try:
            if alerts_df.empty:
                logger.info("No alerts to enqueue")
                return 0
            
            # Prepare alert data for insertion
            alert_data = []
            for _, alert in alerts_df.iterrows():
                alert_data.append({
                    'rule_id': alert.get('rule_id', 'AUTO_RULE'),
                    'date': alert['date'],
                    'country': alert['country'],
                    'sector': alert.get('sector', 'UNKNOWN'),
                    'product': alert.get('product', 'UNKNOWN'),
                    'risk_score': alert['risk_score'],
                    'probability': alert['probability'],
                    'severity': alert['severity'],
                    'dedup_key': alert['dedup_key'],
                    'routed_to': alert.get('escalation_policy', 'EMAIL')
                })
            
            # Insert alerts using stored procedure
            result = self.session.call('OPS.SP_EWS_ENQUEUE')
            logger.info(f"Enqueued alerts: {result}")
            
            return len(alert_data)
            
        except Exception as e:
            logger.error(f"Error enqueueing alerts: {e}")
            return 0
    
    def escalate_alerts(self) -> int:
        """Escalate overdue alerts"""
        try:
            result = self.session.call('OPS.SP_ESCALATE_ALERTS')
            logger.info(f"Escalation result: {result}")
            return 1  # Success indicator
        except Exception as e:
            logger.error(f"Error escalating alerts: {e}")
            return 0
    
    def get_metrics(self) -> Dict:
        """Get EWS performance metrics"""
        try:
            metrics_query = """
                SELECT
                    COUNT_IF(severity='P1') AS p1_count,
                    COUNT_IF(severity='P2') AS p2_count,
                    COUNT_IF(severity='P3') AS p3_count,
                    COUNT(*) AS total_alerts,
                    COUNT_IF(status='NEW') AS new_count,
                    COUNT_IF(status='ACKNOWLEDGED') AS acknowledged_count,
                    COUNT_IF(status='RESOLVED') AS resolved_count,
                    AVG(DATEDIFF('minute', created_at, COALESCE(acknowledged_at, CURRENT_TIMESTAMP()))) AS avg_mtta_minutes,
                    AVG(DATEDIFF('minute', created_at, COALESCE(resolved_at, CURRENT_TIMESTAMP()))) AS avg_mttr_minutes
                FROM OPS.ALERT_QUEUE
                WHERE created_at >= DATEADD(day, -30, CURRENT_TIMESTAMP())
            """
            
            metrics_df = self.session.sql(metrics_query).to_pandas()
            
            if not metrics_df.empty:
                metrics = metrics_df.iloc[0].to_dict()
                logger.info(f"EWS metrics: {metrics}")
                return metrics
            else:
                return {}
                
        except Exception as e:
            logger.error(f"Error getting EWS metrics: {e}")
            return {}
    
    def get_alert_summary(self) -> Dict:
        """Get alert summary for dashboard"""
        try:
            summary_query = """
                SELECT
                    DATE(created_at) as alert_date,
                    severity,
                    COUNT(*) as alert_count,
                    COUNT_IF(status='NEW') as new_count,
                    COUNT_IF(status='ACKNOWLEDGED') as acknowledged_count,
                    COUNT_IF(status='RESOLVED') as resolved_count
                FROM OPS.ALERT_QUEUE
                WHERE created_at >= DATEADD(day, -7, CURRENT_TIMESTAMP())
                GROUP BY DATE(created_at), severity
                ORDER BY alert_date DESC, severity
            """
            
            summary_df = self.session.sql(summary_query).to_pandas()
            return summary_df.to_dict('records')
            
        except Exception as e:
            logger.error(f"Error getting alert summary: {e}")
            return []
    
    def get_country_risk_summary(self) -> Dict:
        """Get country-level risk summary"""
        try:
            country_query = """
                SELECT
                    country,
                    COUNT(*) as alert_count,
                    AVG(risk_score) as avg_risk_score,
                    MAX(risk_score) as max_risk_score,
                    COUNT_IF(severity='P1') as p1_count,
                    COUNT_IF(severity='P2') as p2_count,
                    COUNT_IF(severity='P3') as p3_count
                FROM OPS.ALERT_QUEUE
                WHERE created_at >= DATEADD(day, -7, CURRENT_TIMESTAMP())
                GROUP BY country
                ORDER BY alert_count DESC, avg_risk_score DESC
            """
            
            country_df = self.session.sql(country_query).to_pandas()
            return country_df.to_dict('records')
            
        except Exception as e:
            logger.error(f"Error getting country risk summary: {e}")
            return []
    
    def process_ews_cycle(self) -> Dict:
        """Run complete EWS processing cycle"""
        try:
            logger.info("Starting EWS processing cycle")
            
            # Step 1: Get candidates
            candidates = self.get_candidates()
            if candidates.empty:
                logger.info("No candidates to process")
                return {'status': 'SUCCESS', 'alerts_processed': 0}
            
            # Step 2: Evaluate rules
            rule_matches = self.evaluate_rules(candidates)
            if rule_matches.empty:
                logger.info("No rule matches found")
                return {'status': 'SUCCESS', 'alerts_processed': 0}
            
            # Step 3: Deduplicate
            new_alerts = self.deduplicate_alerts(rule_matches)
            if new_alerts.empty:
                logger.info("No new alerts after deduplication")
                return {'status': 'SUCCESS', 'alerts_processed': 0}
            
            # Step 4: Enqueue
            enqueued_count = self.enqueue_alerts(new_alerts)
            
            # Step 5: Escalate
            escalation_result = self.escalate_alerts()
            
            # Step 6: Get metrics
            metrics = self.get_metrics()
            
            result = {
                'status': 'SUCCESS',
                'alerts_processed': enqueued_count,
                'escalations': escalation_result,
                'metrics': metrics,
                'timestamp': datetime.now().isoformat()
            }
            
            logger.info(f"EWS cycle completed: {result}")
            return result
            
        except Exception as e:
            logger.error(f"Error in EWS processing cycle: {e}")
            return {'status': 'ERROR', 'error': str(e)}
    
    def run_ews_now(self) -> Dict:
        """Run EWS processing immediately"""
        try:
            logger.info("Running EWS processing now")
            
            # Refresh candidates
            self.session.sql("""
                TRUNCATE TABLE OPS.ALERT_CANDIDATES;
                INSERT INTO OPS.ALERT_CANDIDATES 
                SELECT
                    HASH(TO_VARCHAR(date) || country || TO_VARCHAR(risk_score) || TO_VARCHAR(probability)) AS dedup_key,
                    date, country, sector, product, risk_score, probability, model_version,
                    CASE 
                        WHEN probability >= 0.80 THEN 'P1'
                        WHEN probability >= 0.60 THEN 'P2'
                        WHEN probability >= 0.40 THEN 'P3'
                        ELSE 'P4'
                    END AS severity,
                    is_watched, watch_priority, CURRENT_TIMESTAMP() as candidate_ts
                FROM OPS.PREDICTIONS_WATCHED
                WHERE probability >= 0.40
            """).collect()
            
            # Process EWS cycle
            result = self.process_ews_cycle()
            
            return result
            
        except Exception as e:
            logger.error(f"Error running EWS now: {e}")
            return {'status': 'ERROR', 'error': str(e)}

def main():
    """Main EWS engine execution"""
    logger.info("=" * 80)
    logger.info("EWS ENGINE - EARLY WARNING SYSTEM")
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
        # Initialize EWS engine
        ews_engine = EWSEngine(session)
        
        # Run EWS processing
        result = ews_engine.run_ews_now()
        
        logger.info(f"EWS processing result: {result}")
        
        # Get metrics
        metrics = ews_engine.get_metrics()
        logger.info(f"EWS metrics: {metrics}")
        
        # Get summaries
        alert_summary = ews_engine.get_alert_summary()
        country_summary = ews_engine.get_country_risk_summary()
        
        logger.info(f"Alert summary: {len(alert_summary)} entries")
        logger.info(f"Country summary: {len(country_summary)} entries")
        
    except Exception as e:
        logger.error(f"EWS engine error: {e}")
    finally:
        session.close()
        logger.info("Disconnected from Snowflake")

if __name__ == "__main__":
    main()
