"""
Scenario Simulator - Stress Testing Engine
Global Supply Chain Spoilage Forecasting Project
Feature perturbations and re-scoring for scenario analysis
"""

import os
import json
import logging
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from pathlib import Path
from snowflake.snowpark import Session
from typing import Dict, List, Optional, Any

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/scenario_sim.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class ScenarioSimulator:
    """Scenario simulation engine for stress testing"""
    
    def __init__(self, session: Session):
        self.session = session
        self.scenario_templates = {}
        self.load_templates()
    
    def load_templates(self):
        """Load scenario templates from database"""
        try:
            templates_df = self.session.table("OPS.SCENARIO_TEMPLATES").to_pandas()
            self.scenario_templates = templates_df.set_index('template_id').to_dict('index')
            logger.info(f"Loaded {len(self.scenario_templates)} scenario templates")
        except Exception as e:
            logger.error(f"Error loading scenario templates: {e}")
            self.scenario_templates = {}
    
    def _load_base_data(self) -> pd.DataFrame:
        """Load base data for scenario simulation"""
        try:
            # Load the master feature dataset
            base_df = self.session.table("ML.ML_READY_MASTER").to_pandas()
            logger.info(f"Loaded base dataset with {len(base_df)} records")
            return base_df
        except Exception as e:
            logger.error(f"Error loading base data: {e}")
            return pd.DataFrame()
    
    def apply_shocks(self, df: pd.DataFrame, params: Dict[str, Any]) -> pd.DataFrame:
        """Apply economic and climate shocks to the dataset"""
        try:
            sim_df = df.copy()
            
            # Economic shocks
            if 'fedfunds_bp' in params:
                bp_change = params['fedfunds_bp'] / 10000.0  # Convert basis points to decimal
                sim_df['fedfunds_rate'] = sim_df['fedfunds_rate'] + bp_change
                logger.info(f"Applied Fed funds rate shock: +{params['fedfunds_bp']} bp")
            
            if 'retail_yoy' in params:
                yoy_change = params['retail_yoy']
                sim_df['retail_sales'] = sim_df['retail_sales'] * (1 + yoy_change)
                logger.info(f"Applied retail sales shock: {yoy_change*100:.1f}% YoY")
            
            if 'unemployment_delta' in params:
                unemp_change = params['unemployment_delta']
                sim_df['unemployment_rate'] = sim_df['unemployment_rate'] + unemp_change
                logger.info(f"Applied unemployment shock: +{unemp_change*100:.1f}%")
            
            # Climate shocks
            if 'temp_delta' in params:
                temp_change = params['temp_delta']
                # Simulate temperature impact on various sectors
                sim_df['temp_anomaly'] = sim_df.get('temp_anomaly', 0) + temp_change
                logger.info(f"Applied temperature shock: +{temp_change:.1f}°C")
            
            if 'precipitation_delta' in params:
                precip_change = params['precipitation_delta']
                sim_df['precipitation_anomaly'] = sim_df.get('precipitation_anomaly', 0) + precip_change
                logger.info(f"Applied precipitation shock: +{precip_change*100:.1f}%")
            
            if 'extreme_weather_freq' in params:
                weather_mult = params['extreme_weather_freq']
                sim_df['extreme_weather_risk'] = sim_df.get('extreme_weather_risk', 0) * weather_mult
                logger.info(f"Applied extreme weather shock: {weather_mult}x frequency")
            
            # Supply chain shocks
            if 'logistics_cost_delta' in params:
                logistics_change = params['logistics_cost_delta']
                sim_df['logistics_cost'] = sim_df.get('logistics_cost', 0) * (1 + logistics_change)
                logger.info(f"Applied logistics cost shock: +{logistics_change*100:.1f}%")
            
            if 'supplier_reliability_delta' in params:
                supplier_change = params['supplier_reliability_delta']
                sim_df['supplier_reliability'] = sim_df.get('supplier_reliability', 1.0) + supplier_change
                logger.info(f"Applied supplier reliability shock: {supplier_change*100:.1f}%")
            
            if 'inventory_turnover_delta' in params:
                inventory_change = params['inventory_turnover_delta']
                sim_df['inventory_turnover'] = sim_df.get('inventory_turnover', 1.0) + inventory_change
                logger.info(f"Applied inventory turnover shock: {inventory_change*100:.1f}%")
            
            # Policy shocks
            if 'treasury_spread_delta' in params:
                spread_change = params['treasury_spread_delta']
                sim_df['treasury_10y_rate'] = sim_df['treasury_10y_rate'] + spread_change
                logger.info(f"Applied treasury spread shock: +{spread_change*100:.1f}%")
            
            if 'credit_availability_delta' in params:
                credit_change = params['credit_availability_delta']
                sim_df['credit_availability'] = sim_df.get('credit_availability', 1.0) + credit_change
                logger.info(f"Applied credit availability shock: {credit_change*100:.1f}%")
            
            # Demand shocks
            if 'consumer_confidence_delta' in params:
                confidence_change = params['consumer_confidence_delta']
                sim_df['consumer_confidence'] = sim_df.get('consumer_confidence', 100) + confidence_change
                logger.info(f"Applied consumer confidence shock: {confidence_change:.1f} points")
            
            if 'disposable_income_delta' in params:
                income_change = params['disposable_income_delta']
                sim_df['disposable_income'] = sim_df.get('disposable_income', 1.0) + income_change
                logger.info(f"Applied disposable income shock: {income_change*100:.1f}%")
            
            return sim_df
            
        except Exception as e:
            logger.error(f"Error applying shocks: {e}")
            return df
    
    def score_scenario(self, sim_df: pd.DataFrame, model_version: str = 'latest') -> pd.DataFrame:
        """Score the scenario using the production model"""
        try:
            # In a real implementation, this would call the actual ML model
            # For now, we'll simulate scoring with some business logic
            
            # Simulate risk score calculation based on perturbed features
            base_risk = 0.5  # Base risk score
            
            # Economic factors
            if 'fedfunds_rate' in sim_df.columns:
                fed_impact = np.clip((sim_df['fedfunds_rate'] - 0.02) * 2, -0.3, 0.3)
                base_risk += fed_impact
            
            if 'retail_sales' in sim_df.columns:
                retail_impact = np.clip((sim_df['retail_sales'] - 1.0) * 0.5, -0.2, 0.2)
                base_risk += retail_impact
            
            if 'unemployment_rate' in sim_df.columns:
                unemp_impact = np.clip((sim_df['unemployment_rate'] - 0.05) * 3, -0.3, 0.3)
                base_risk += unemp_impact
            
            # Climate factors
            if 'temp_anomaly' in sim_df.columns:
                temp_impact = np.clip(sim_df['temp_anomaly'] * 0.1, -0.2, 0.2)
                base_risk += temp_impact
            
            if 'extreme_weather_risk' in sim_df.columns:
                weather_impact = np.clip((sim_df['extreme_weather_risk'] - 1.0) * 0.2, -0.2, 0.2)
                base_risk += weather_impact
            
            # Supply chain factors
            if 'logistics_cost' in sim_df.columns:
                logistics_impact = np.clip((sim_df['logistics_cost'] - 1.0) * 0.3, -0.2, 0.2)
                base_risk += logistics_impact
            
            if 'supplier_reliability' in sim_df.columns:
                supplier_impact = np.clip((1.0 - sim_df['supplier_reliability']) * 0.5, -0.3, 0.3)
                base_risk += supplier_impact
            
            # Add some randomness for realism
            noise = np.random.normal(0, 0.05, len(sim_df))
            base_risk += noise
            
            # Ensure risk scores are between 0 and 1
            scenario_risk_score = np.clip(base_risk, 0, 1)
            
            # Calculate probability (simplified)
            scenario_probability = scenario_risk_score ** 1.5  # Non-linear relationship
            
            # Create results dataframe
            results_df = pd.DataFrame({
                'date': sim_df['date'],
                'country': sim_df.get('country', 'UNKNOWN'),
                'sector': sim_df.get('sector', 'UNKNOWN'),
                'product': sim_df.get('product', 'UNKNOWN'),
                'scenario_risk_score': scenario_risk_score,
                'scenario_probability': scenario_probability,
                'model_version': model_version
            })
            
            logger.info(f"Scored scenario with {len(results_df)} results")
            return results_df
            
        except Exception as e:
            logger.error(f"Error scoring scenario: {e}")
            return pd.DataFrame()
    
    def run_scenario(self, name: str, horizon_months: int, params: Dict[str, Any], 
                    description: str = None, template_id: str = None) -> str:
        """Run a complete scenario simulation"""
        try:
            logger.info(f"Running scenario: {name}")
            logger.info(f"Parameters: {params}")
            
            # Load base data
            base_df = self._load_base_data()
            if base_df.empty:
                raise ValueError("No base data available")
            
            # Filter to horizon
            end_date = datetime.now() + timedelta(days=horizon_months * 30)
            base_df = base_df[base_df['date'] <= end_date]
            
            # Apply shocks
            sim_df = self.apply_shocks(base_df, params)
            
            # Score scenario
            results_df = self.score_scenario(sim_df)
            
            if results_df.empty:
                raise ValueError("No results generated")
            
            # Generate run ID
            run_id = self.session.sql("SELECT UUID_STRING()").collect()[0][0]
            
            # Store scenario run metadata
            self.session.sql(f"""
                INSERT INTO OPS.SCENARIO_RUNS (
                    run_id, name, description, horizon_months, params, status, created_by
                ) VALUES (
                    '{run_id}',
                    '{name}',
                    '{description or ''}',
                    {horizon_months},
                    PARSE_JSON('{json.dumps(params)}'),
                    'RUNNING',
                    CURRENT_ROLE()
                )
            """).collect()
            
            # Store scenario results
            results_df['run_id'] = run_id
            results_df['base_risk_score'] = 0.5  # Placeholder base score
            results_df['delta_vs_base'] = results_df['scenario_risk_score'] - results_df['base_risk_score']
            results_df['confidence_interval_lower'] = results_df['scenario_risk_score'] - 0.05
            results_df['confidence_interval_upper'] = results_df['scenario_risk_score'] + 0.05
            results_df['model_version'] = 'scenario_v1.0'
            
            # Convert to Snowpark DataFrame and save
            results_snowpark = self.session.create_dataframe(results_df)
            results_snowpark.write.mode("append").save_as_table("OPS.SCENARIO_RESULTS")
            
            # Update run status
            self.session.sql(f"""
                UPDATE OPS.SCENARIO_RUNS 
                SET status = 'COMPLETED', completed_at = CURRENT_TIMESTAMP()
                WHERE run_id = '{run_id}'
            """).collect()
            
            logger.info(f"Scenario {name} completed with run_id: {run_id}")
            return run_id
            
        except Exception as e:
            logger.error(f"Error running scenario: {e}")
            # Update run status to failed
            if 'run_id' in locals():
                self.session.sql(f"""
                    UPDATE OPS.SCENARIO_RUNS 
                    SET status = 'FAILED'
                    WHERE run_id = '{run_id}'
                """).collect()
            raise
    
    def run_template_scenario(self, template_id: str, custom_params: Dict[str, Any] = None) -> str:
        """Run a scenario from a template"""
        try:
            if template_id not in self.scenario_templates:
                raise ValueError(f"Template {template_id} not found")
            
            template = self.scenario_templates[template_id]
            params = template['params_template'].copy()
            
            # Override with custom parameters
            if custom_params:
                params.update(custom_params)
            
            return self.run_scenario(
                name=template['name'],
                horizon_months=template['horizon_months'],
                params=params,
                description=template['description']
            )
            
        except Exception as e:
            logger.error(f"Error running template scenario: {e}")
            raise
    
    def get_scenario_results(self, run_id: str) -> pd.DataFrame:
        """Get results for a specific scenario run"""
        try:
            results_df = self.session.sql(f"""
                SELECT * FROM OPS.SCENARIO_RESULTS 
                WHERE run_id = '{run_id}'
                ORDER BY date DESC, delta_vs_base DESC
            """).to_pandas()
            
            return results_df
            
        except Exception as e:
            logger.error(f"Error getting scenario results: {e}")
            return pd.DataFrame()
    
    def compare_scenarios(self, run_ids: List[str]) -> pd.DataFrame:
        """Compare multiple scenario runs"""
        try:
            if len(run_ids) < 2:
                raise ValueError("Need at least 2 scenarios to compare")
            
            comparison_data = []
            
            for run_id in run_ids:
                # Get scenario metadata
                run_info = self.session.sql(f"""
                    SELECT name, params, created_at FROM OPS.SCENARIO_RUNS 
                    WHERE run_id = '{run_id}'
                """).to_pandas()
                
                if run_info.empty:
                    continue
                
                # Get results
                results = self.get_scenario_results(run_id)
                if results.empty:
                    continue
                
                # Aggregate results
                summary = {
                    'run_id': run_id,
                    'name': run_info.iloc[0]['name'],
                    'created_at': run_info.iloc[0]['created_at'],
                    'total_countries': results['country'].nunique(),
                    'avg_risk_score': results['scenario_risk_score'].mean(),
                    'max_risk_score': results['scenario_risk_score'].max(),
                    'avg_delta': results['delta_vs_base'].mean(),
                    'max_delta': results['delta_vs_base'].max(),
                    'high_risk_count': (results['scenario_risk_score'] > 0.7).sum()
                }
                
                comparison_data.append(summary)
            
            comparison_df = pd.DataFrame(comparison_data)
            return comparison_df
            
        except Exception as e:
            logger.error(f"Error comparing scenarios: {e}")
            return pd.DataFrame()
    
    def get_scenario_summary(self) -> pd.DataFrame:
        """Get summary of all scenario runs"""
        try:
            summary_df = self.session.sql("""
                SELECT 
                    sr.run_id,
                    sr.name,
                    sr.status,
                    sr.created_at,
                    sr.completed_at,
                    sr.horizon_months,
                    COUNT(sr2.result_id) as result_count,
                    AVG(sr2.delta_vs_base) as avg_delta,
                    MAX(sr2.delta_vs_base) as max_delta,
                    MIN(sr2.delta_vs_base) as min_delta
                FROM OPS.SCENARIO_RUNS sr
                LEFT JOIN OPS.SCENARIO_RESULTS sr2 ON sr.run_id = sr2.run_id
                WHERE sr.created_at >= DATEADD(month, -6, CURRENT_TIMESTAMP())
                GROUP BY sr.run_id, sr.name, sr.status, sr.created_at, sr.completed_at, sr.horizon_months
                ORDER BY sr.created_at DESC
            """).to_pandas()
            
            return summary_df
            
        except Exception as e:
            logger.error(f"Error getting scenario summary: {e}")
            return pd.DataFrame()

def main():
    """Main scenario simulator execution"""
    logger.info("=" * 80)
    logger.info("SCENARIO SIMULATOR - STRESS TESTING ENGINE")
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
        # Initialize scenario simulator
        simulator = ScenarioSimulator(session)
        
        # Run example scenarios
        logger.info("Running example scenarios...")
        
        # Economic recession scenario
        recession_params = {
            'fedfunds_bp': 200,
            'retail_yoy': -0.05,
            'unemployment_delta': 0.03
        }
        
        recession_id = simulator.run_scenario(
            name='Economic Recession',
            horizon_months=24,
            params=recession_params,
            description='Simulate economic recession with high interest rates and declining retail sales'
        )
        
        logger.info(f"Recession scenario completed: {recession_id}")
        
        # Climate change scenario
        climate_params = {
            'temp_delta': 2.0,
            'precipitation_delta': 0.15,
            'extreme_weather_freq': 1.5
        }
        
        climate_id = simulator.run_scenario(
            name='Climate Change A2',
            horizon_months=36,
            params=climate_params,
            description='High emissions climate scenario with temperature and precipitation changes'
        )
        
        logger.info(f"Climate scenario completed: {climate_id}")
        
        # Get scenario summary
        summary = simulator.get_scenario_summary()
        logger.info(f"Scenario summary: {len(summary)} runs")
        
        # Compare scenarios
        comparison = simulator.compare_scenarios([recession_id, climate_id])
        logger.info(f"Scenario comparison: {len(comparison)} scenarios compared")
        
    except Exception as e:
        logger.error(f"Scenario simulator error: {e}")
    finally:
        session.close()
        logger.info("Disconnected from Snowflake")

if __name__ == "__main__":
    main()
