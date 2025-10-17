"""
Model Registry Tools
Global Supply Chain Spoilage Forecasting Project
Artifact hashing, model promotion/demotion utilities
"""

import os
import json
import logging
import hashlib
from datetime import datetime
from pathlib import Path
from snowflake.snowpark import Session

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class ModelRegistryTools:
    """Utilities for model registry operations"""
    
    def __init__(self, session: Session):
        self.session = session
    
    def compute_artifact_hash(self, file_path: str) -> str:
        """Compute SHA256 hash of artifact file"""
        try:
            sha256_hash = hashlib.sha256()
            
            with open(file_path, "rb") as f:
                # Read file in chunks
                for byte_block in iter(lambda: f.read(4096), b""):
                    sha256_hash.update(byte_block)
            
            return sha256_hash.hexdigest()
        
        except Exception as e:
            logger.error(f"Error computing hash: {e}")
            return None
    
    def register_model(self, model_config: dict) -> str:
        """Register a new model in the registry"""
        try:
            logger.info(f"Registering model: {model_config['model_name']}")
            
            # Insert into registry
            result = self.session.sql(f"""
                INSERT INTO ML.MODEL_REGISTRY (
                    model_name,
                    model_version,
                    model_type,
                    algorithm,
                    framework,
                    created_by,
                    hyperparameters,
                    feature_list,
                    status,
                    environment,
                    description
                )
                VALUES (
                    '{model_config['model_name']}',
                    '{model_config['model_version']}',
                    '{model_config['model_type']}',
                    '{model_config['algorithm']}',
                    '{model_config.get('framework', 'SKLEARN')}',
                    CURRENT_USER(),
                    PARSE_JSON('{json.dumps(model_config.get('hyperparameters', {}))}'),
                    PARSE_JSON('{json.dumps(model_config.get('feature_list', []))}'),
                    'STAGING',
                    'DEV',
                    '{model_config.get('description', '')}'
                )
            """).collect()
            
            # Get the model_id
            model_id = self.session.sql(f"""
                SELECT model_id
                FROM ML.MODEL_REGISTRY
                WHERE model_name = '{model_config['model_name']}'
                AND model_version = '{model_config['model_version']}'
            """).collect()[0][0]
            
            logger.info(f"Model registered with ID: {model_id}")
            return model_id
        
        except Exception as e:
            logger.error(f"Error registering model: {e}")
            return None
    
    def promote_model(self, model_id: str, target_env: str, promoted_by: str = None):
        """Promote model to target environment"""
        try:
            if promoted_by is None:
                promoted_by = "SYSTEM"
            
            logger.info(f"Promoting model {model_id} to {target_env}")
            
            # Call stored procedure
            result = self.session.call(
                'ML.PROMOTE_MODEL',
                model_id,
                'STG' if target_env == 'PRD' else 'DEV',
                target_env,
                promoted_by
            )
            
            logger.info(f"Promotion result: {result}")
            return True
        
        except Exception as e:
            logger.error(f"Error promoting model: {e}")
            return False
    
    def rollback_model(self, model_id: str, rollback_to_model_id: str, rolled_back_by: str = None):
        """Rollback to previous model version"""
        try:
            if rolled_back_by is None:
                rolled_back_by = "SYSTEM"
            
            logger.info(f"Rolling back from {model_id} to {rollback_to_model_id}")
            
            # Call stored procedure
            result = self.session.call(
                'ML.ROLLBACK_MODEL',
                model_id,
                rollback_to_model_id,
                rolled_back_by
            )
            
            logger.info(f"Rollback result: {result}")
            return True
        
        except Exception as e:
            logger.error(f"Error rolling back model: {e}")
            return False
    
    def register_artifact(self, model_id: str, artifact_path: str, artifact_type: str):
        """Register model artifact with hash"""
        try:
            artifact_name = os.path.basename(artifact_path)
            
            # Compute hash
            artifact_hash = self.compute_artifact_hash(artifact_path)
            if not artifact_hash:
                logger.error("Failed to compute artifact hash")
                return False
            
            logger.info(f"Registering artifact: {artifact_name}")
            logger.info(f"  Hash: {artifact_hash}")
            
            # Register artifact
            result = self.session.call(
                'ML.REGISTER_ARTIFACT',
                model_id,
                artifact_name,
                artifact_type,
                f"@ML.MODEL_ARTIFACTS_STAGE/{artifact_name}",
                artifact_hash
            )
            
            logger.info(f"Artifact registration result: {result}")
            return True
        
        except Exception as e:
            logger.error(f"Error registering artifact: {e}")
            return False
    
    def list_models(self, environment: str = None, status: str = None):
        """List models with optional filters"""
        try:
            query = "SELECT model_id, model_name, model_version, status, environment FROM ML.MODEL_REGISTRY WHERE 1=1"
            
            if environment:
                query += f" AND environment = '{environment}'"
            if status:
                query += f" AND status = '{status}'"
            
            query += " ORDER BY created_timestamp DESC"
            
            results = self.session.sql(query).collect()
            
            models = []
            for row in results:
                models.append({
                    'model_id': row[0],
                    'model_name': row[1],
                    'model_version': row[2],
                    'status': row[3],
                    'environment': row[4]
                })
            
            return models
        
        except Exception as e:
            logger.error(f"Error listing models: {e}")
            return []
    
    def get_model_metrics(self, model_id: str):
        """Get performance metrics for a model"""
        try:
            query = f"""
                SELECT 
                    metric_name,
                    metric_value,
                    dataset_type
                FROM ML.MODEL_PERFORMANCE_METRICS
                WHERE model_id = '{model_id}'
                ORDER BY evaluation_timestamp DESC
            """
            
            results = self.session.sql(query).collect()
            
            metrics = []
            for row in results:
                metrics.append({
                    'metric_name': row[0],
                    'metric_value': row[1],
                    'dataset_type': row[2]
                })
            
            return metrics
        
        except Exception as e:
            logger.error(f"Error fetching metrics: {e}")
            return []
    
    def compare_models(self, model_id_1: str, model_id_2: str):
        """Compare performance metrics of two models"""
        try:
            metrics_1 = self.get_model_metrics(model_id_1)
            metrics_2 = self.get_model_metrics(model_id_2)
            
            logger.info(f"\nModel Comparison:")
            logger.info(f"  Model 1: {model_id_1}")
            logger.info(f"    Metrics: {len(metrics_1)}")
            
            logger.info(f"  Model 2: {model_id_2}")
            logger.info(f"    Metrics: {len(metrics_2)}")
            
            # Simple comparison
            comparison = {
                'model_1': model_id_1,
                'model_2': model_id_2,
                'metrics_1': metrics_1,
                'metrics_2': metrics_2
            }
            
            return comparison
        
        except Exception as e:
            logger.error(f"Error comparing models: {e}")
            return None

def main():
    """CLI for model registry tools"""
    logger.info("=" * 80)
    logger.info("MODEL REGISTRY TOOLS")
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
        # Initialize tools
        tools = ModelRegistryTools(session)
        
        # List all production models
        logger.info("\nProduction Models:")
        prod_models = tools.list_models(environment='PRD', status='PRODUCTION')
        
        for model in prod_models:
            logger.info(f"  {model['model_name']} v{model['model_version']}")
            logger.info(f"    ID: {model['model_id']}")
            logger.info(f"    Status: {model['status']}")
            
            # Get metrics
            metrics = tools.get_model_metrics(model['model_id'])
            if metrics:
                logger.info(f"    Metrics:")
                for metric in metrics[:3]:  # Show first 3 metrics
                    logger.info(f"      {metric['metric_name']}: {metric['metric_value']:.4f}")
            logger.info("")
        
        logger.info(f"\nTotal production models: {len(prod_models)}")
    
    except Exception as e:
        logger.error(f"Error: {e}")
    finally:
        session.close()
        logger.info("\nDisconnected from Snowflake")

if __name__ == "__main__":
    main()
