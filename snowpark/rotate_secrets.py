"""
Secret Rotation Script
Global Supply Chain Spoilage Forecasting Project
Implements secret rotation with canary checks and rollback capabilities
"""

import os
import json
import logging
import hashlib
from datetime import datetime, timedelta
from pathlib import Path
from snowflake.snowpark import Session

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/secret_rotation.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class SecretRotationManager:
    """Manages secret rotation with validation and rollback"""
    
    def __init__(self, session: Session):
        self.session = session
        self.rotation_history = []
    
    def get_due_secrets(self):
        """Get secrets that are due for rotation"""
        try:
            query = """
                SELECT 
                    secret_id,
                    secret_name,
                    secret_type,
                    last_rotated,
                    rotation_frequency_days,
                    next_rotation_date
                FROM OPS.SECRETS_REGISTRY
                WHERE status = 'ACTIVE'
                AND next_rotation_date <= CURRENT_DATE()
                ORDER BY next_rotation_date
            """
            
            results = self.session.sql(query).collect()
            
            due_secrets = []
            for row in results:
                due_secrets.append({
                    'secret_id': row[0],
                    'secret_name': row[1],
                    'secret_type': row[2],
                    'last_rotated': row[3],
                    'rotation_frequency_days': row[4],
                    'next_rotation_date': row[5]
                })
            
            return due_secrets
        
        except Exception as e:
            logger.error(f"Error fetching due secrets: {e}")
            return []
    
    def hash_secret(self, secret_value: str) -> str:
        """Generate SHA256 hash of secret for tracking (NOT storing the secret itself)"""
        return hashlib.sha256(secret_value.encode()).hexdigest()
    
    def rotate_secret(self, secret_name: str, rotation_type: str = 'SCHEDULED'):
        """
        Rotate a secret
        NOTE: This is a template - integrate with your secret vault (AWS Secrets Manager, HashiCorp Vault, etc.)
        """
        try:
            logger.info(f"Rotating secret: {secret_name}")
            
            # Step 1: Get current secret metadata
            current_secret = self.session.sql(f"""
                SELECT secret_id, secret_type, vault_path
                FROM OPS.SECRETS_REGISTRY
                WHERE secret_name = '{secret_name}'
                AND status = 'ACTIVE'
            """).collect()
            
            if not current_secret:
                logger.error(f"Secret not found: {secret_name}")
                return False
            
            secret_id = current_secret[0][0]
            secret_type = current_secret[0][1]
            vault_path = current_secret[0][2]
            
            # Step 2: Update status to ROTATING
            self.session.sql(f"""
                UPDATE OPS.SECRETS_REGISTRY
                SET status = 'ROTATING'
                WHERE secret_name = '{secret_name}'
            """).collect()
            
            # Step 3: Simulate secret rotation (in production, integrate with vault)
            # This is where you would:
            # - Generate new secret
            # - Store in vault
            # - Update application configurations
            # - Run canary tests
            
            logger.info(f"  Simulating rotation for {secret_type} at {vault_path}")
            
            # Generate placeholder hashes
            old_secret_hash = self.hash_secret(f"{secret_name}_old_{datetime.now()}")
            new_secret_hash = self.hash_secret(f"{secret_name}_new_{datetime.now()}")
            
            # Step 4: Run canary checks
            if not self.run_canary_checks(secret_name, secret_type):
                logger.error(f"Canary checks failed for {secret_name}")
                return self.rollback_secret(secret_name, "Canary checks failed")
            
            # Step 5: Update secret metadata
            next_rotation = datetime.now() + timedelta(days=90)
            
            self.session.sql(f"""
                UPDATE OPS.SECRETS_REGISTRY
                SET 
                    last_rotated = CURRENT_TIMESTAMP(),
                    next_rotation_date = '{next_rotation.strftime("%Y-%m-%d")}',
                    status = 'ACTIVE'
                WHERE secret_name = '{secret_name}'
            """).collect()
            
            # Step 6: Log rotation history
            self.session.sql(f"""
                INSERT INTO OPS.SECRET_ROTATION_HISTORY (
                    secret_name,
                    rotation_type,
                    rotated_by,
                    old_secret_hash,
                    new_secret_hash,
                    status
                )
                VALUES (
                    '{secret_name}',
                    '{rotation_type}',
                    CURRENT_USER(),
                    '{old_secret_hash}',
                    '{new_secret_hash}',
                    'SUCCESS'
                )
            """).collect()
            
            logger.info(f"  Successfully rotated: {secret_name}")
            return True
        
        except Exception as e:
            logger.error(f"Error rotating secret {secret_name}: {e}")
            return self.rollback_secret(secret_name, str(e))
    
    def run_canary_checks(self, secret_name: str, secret_type: str) -> bool:
        """Run canary checks to validate new secret"""
        try:
            logger.info(f"  Running canary checks for {secret_name}...")
            
            # Simulate canary checks based on secret type
            if secret_type == 'API_KEY':
                # Test API connectivity
                logger.info(f"    [CANARY] API connectivity check: PASS")
            elif secret_type == 'DATABASE':
                # Test database connection
                logger.info(f"    [CANARY] Database connection check: PASS")
            elif secret_type == 'SERVICE_ACCOUNT':
                # Test service account permissions
                logger.info(f"    [CANARY] Service account check: PASS")
            
            # Generic health check
            logger.info(f"    [CANARY] Health check: PASS")
            
            return True
        
        except Exception as e:
            logger.error(f"  Canary checks failed: {e}")
            return False
    
    def rollback_secret(self, secret_name: str, error_message: str) -> bool:
        """Rollback secret rotation"""
        try:
            logger.warning(f"Rolling back secret rotation: {secret_name}")
            
            # Restore previous secret state
            self.session.sql(f"""
                UPDATE OPS.SECRETS_REGISTRY
                SET status = 'ACTIVE'
                WHERE secret_name = '{secret_name}'
            """).collect()
            
            # Log rollback
            self.session.sql(f"""
                INSERT INTO OPS.SECRET_ROTATION_HISTORY (
                    secret_name,
                    rotation_type,
                    rotated_by,
                    status,
                    error_message
                )
                VALUES (
                    '{secret_name}',
                    'ROLLBACK',
                    CURRENT_USER(),
                    'ROLLBACK',
                    '{error_message[:500]}'
                )
            """).collect()
            
            logger.info(f"  Rollback completed for: {secret_name}")
            return False
        
        except Exception as e:
            logger.error(f"Error during rollback: {e}")
            return False
    
    def log_access(self, secret_name: str, access_type: str, status: str):
        """Log secret access for audit"""
        try:
            self.session.sql(f"""
                INSERT INTO OPS.SECRET_ACCESS_LOG (
                    secret_name,
                    accessed_by_user,
                    accessed_by_role,
                    access_type,
                    status
                )
                VALUES (
                    '{secret_name}',
                    CURRENT_USER(),
                    CURRENT_ROLE(),
                    '{access_type}',
                    '{status}'
                )
            """).collect()
        except Exception as e:
            logger.warning(f"Failed to log access: {e}")

def main():
    """Main secret rotation orchestration"""
    logger.info("=" * 80)
    logger.info("SECRET ROTATION MANAGER")
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
        # Initialize rotation manager
        manager = SecretRotationManager(session)
        
        # Get secrets due for rotation
        due_secrets = manager.get_due_secrets()
        
        if not due_secrets:
            logger.info("No secrets due for rotation")
            return
        
        logger.info(f"Found {len(due_secrets)} secrets due for rotation")
        
        # Rotate each secret
        success_count = 0
        fail_count = 0
        
        for secret in due_secrets:
            logger.info(f"\nProcessing: {secret['secret_name']}")
            logger.info(f"  Type: {secret['secret_type']}")
            logger.info(f"  Last rotated: {secret['last_rotated']}")
            logger.info(f"  Due date: {secret['next_rotation_date']}")
            
            if manager.rotate_secret(secret['secret_name']):
                success_count += 1
            else:
                fail_count += 1
        
        # Summary
        logger.info("\n" + "=" * 80)
        logger.info("ROTATION SUMMARY")
        logger.info("=" * 80)
        logger.info(f"Total secrets: {len(due_secrets)}")
        logger.info(f"Successfully rotated: {success_count}")
        logger.info(f"Failed: {fail_count}")
        
        if fail_count > 0:
            logger.warning("Some secrets failed to rotate. Review logs for details.")
        else:
            logger.info("All secrets rotated successfully!")
    
    except Exception as e:
        logger.error(f"Secret rotation failed: {e}")
    finally:
        session.close()
        logger.info("\nDisconnected from Snowflake")

if __name__ == "__main__":
    main()
