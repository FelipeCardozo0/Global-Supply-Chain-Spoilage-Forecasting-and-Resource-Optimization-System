# Disaster Recovery Runbook
## Global Supply Chain Spoilage Forecasting Project

### Overview
This runbook provides comprehensive disaster recovery procedures for the Global Supply Chain Spoilage Forecasting system, including backup, restore, and failover procedures.

### DR Architecture

#### Primary Site (Production)
- **Database**: GLOBAL_SPOILAGE_DB_PRD
- **Warehouse**: COMPUTE_WH_PRD
- **Region**: [Primary Region]
- **Backup Frequency**: Daily full, hourly incremental
- **Retention**: 7 days time-travel, 30 days backups

#### DR Site (Disaster Recovery)
- **Database**: GLOBAL_SPOILAGE_DB_DR
- **Warehouse**: COMPUTE_WH_DR
- **Region**: [DR Region]
- **Replication**: Cross-region replication
- **Failover Time**: < 15 minutes

### Backup Procedures

#### Daily Full Backup
```sql
-- Execute daily backup
CALL OPS.SP_DAILY_BACKUP();
```

**What it backs up:**
- ML.PREDICTIONS (critical predictions)
- OPS.ALERT_QUEUE (active alerts)
- ML.MODEL_RESULTS (model performance)
- OPS.ALLOCATIONS (resource allocations)
- OPS.ENVIRONMENT_PROMOTIONS (deployment history)

**Backup Location:**
- S3: `s3://global-spoilage-backups/snowflake/backups/`
- Format: Compressed CSV with headers
- Retention: 30 days

#### Incremental Backup
```sql
-- Execute incremental backup
CALL OPS.SP_INCREMENTAL_BACKUP();
```

**What it backs up:**
- Recent changes (last 24 hours)
- New predictions and alerts
- Updated model results
- Changed allocations

#### Backup Validation
```sql
-- Check backup status
SELECT * FROM OPS.BACKUP_MONITORING 
WHERE backup_date = CURRENT_DATE();

-- Validate backup integrity
SELECT * FROM OPS.BACKUP_VALIDATION 
WHERE validation_status = 'PASS';
```

### Time-Travel Recovery

#### Point-in-Time Recovery
```sql
-- Recover to specific timestamp
CALL OPS.SP_TIME_TRAVEL_RECOVERY(
    'ML.PREDICTIONS',
    '2024-01-15 14:30:00'
);
```

#### Table-Level Recovery
```sql
-- Recover specific table
CREATE OR REPLACE TABLE ML.PREDICTIONS_RECOVERED AS
SELECT * FROM ML.PREDICTIONS 
AT(TIMESTAMP => '2024-01-15 14:30:00');
```

#### Database-Level Recovery
```sql
-- Recover entire database
CREATE OR REPLACE DATABASE GLOBAL_SPOILAGE_DB_RECOVERED 
CLONE GLOBAL_SPOILAGE_DB 
AT(TIMESTAMP => '2024-01-15 14:30:00');
```

### Failover Procedures

#### Automatic Failover (RTO: 15 minutes)
1. **Detection**
   - Monitor primary site health
   - Detect service unavailability
   - Trigger failover automatically

2. **Activation**
   - Activate DR site
   - Route traffic to DR
   - Update DNS records

3. **Validation**
   - Verify DR site is operational
   - Check data consistency
   - Validate all services

#### Manual Failover (RTO: 30 minutes)
1. **Decision**
   - Assess primary site issues
   - Determine failover necessity
   - Get management approval

2. **Execution**
   ```sql
   -- Activate DR site
   CALL OPS.SP_FAILOVER_DR();
   ```

3. **Verification**
   - Test all critical functions
   - Verify data integrity
   - Confirm user access

#### Failover Checklist
- [ ] Primary site confirmed down
- [ ] DR site activated
- [ ] Traffic routed to DR
- [ ] All services operational
- [ ] Data consistency verified
- [ ] Users notified
- [ ] Monitoring updated

### Failback Procedures

#### Automatic Failback (RTO: 30 minutes)
1. **Detection**
   - Monitor primary site recovery
   - Verify service stability
   - Prepare for failback

2. **Execution**
   ```sql
   -- Failback to primary
   CALL OPS.SP_FAILBACK_PRIMARY();
   ```

3. **Validation**
   - Verify primary site is stable
   - Check data synchronization
   - Confirm all services

#### Manual Failback (RTO: 60 minutes)
1. **Preparation**
   - Verify primary site is stable
   - Sync data from DR to primary
   - Prepare failback plan

2. **Execution**
   - Gradually route traffic back
   - Monitor system stability
   - Validate all functions

3. **Completion**
   - Full traffic on primary
   - DR site in standby
   - Update documentation

### DR Testing

#### Monthly DR Drill
```bash
# Run DR drill
python ops/failover_drill.py
```

**What it tests:**
- Backup accessibility
- Time-travel functionality
- Failover procedures
- Data consistency
- Service availability

#### Quarterly Full DR Test
1. **Preparation**
   - Schedule maintenance window
   - Notify all stakeholders
   - Prepare test scenarios

2. **Execution**
   - Simulate primary site failure
   - Activate DR site
   - Run full system tests
   - Validate all functions

3. **Recovery**
   - Restore primary site
   - Sync data back
   - Verify system stability

### Data Synchronization

#### Real-time Replication
- **Method**: Cross-region replication
- **Latency**: < 5 minutes
- **Coverage**: All critical tables
- **Monitoring**: Automated alerts

#### Batch Synchronization
- **Frequency**: Every 6 hours
- **Method**: ETL processes
- **Validation**: Data quality checks
- **Monitoring**: Success/failure alerts

### Recovery Time Objectives (RTO)

#### Critical Systems
- **ML Predictions**: 5 minutes
- **Alert System**: 10 minutes
- **API Services**: 15 minutes
- **Dashboards**: 20 minutes

#### Non-Critical Systems
- **Reporting**: 60 minutes
- **Analytics**: 120 minutes
- **Archives**: 240 minutes

### Recovery Point Objectives (RPO)

#### Data Loss Tolerance
- **Critical Data**: 0 minutes (real-time)
- **Important Data**: 15 minutes
- **Standard Data**: 60 minutes
- **Archive Data**: 240 minutes

### DR Monitoring

#### Health Checks
```sql
-- Check DR site health
SELECT * FROM OPS.ENVIRONMENT_HEALTH 
WHERE environment = 'DR';

-- Check replication status
SELECT * FROM OPS.REPLICATION_STATUS;

-- Check backup status
SELECT * FROM OPS.BACKUP_MONITORING 
WHERE status = 'SUCCESS';
```

#### Alerting
- **Replication Lag**: > 10 minutes
- **Backup Failure**: Any backup fails
- **DR Site Down**: DR site unavailable
- **Data Inconsistency**: Data mismatch detected

### Emergency Procedures

#### Critical Data Loss
1. **Immediate Response**
   - Stop all data processing
   - Assess data loss scope
   - Notify management immediately

2. **Recovery Actions**
   - Restore from latest backup
   - Use time-travel if available
   - Re-process data if necessary

3. **Validation**
   - Verify data integrity
   - Check system functionality
   - Monitor for stability

#### Security Breach
1. **Immediate Response**
   - Isolate affected systems
   - Preserve evidence
   - Notify security team

2. **Recovery Actions**
   - Restore from clean backup
   - Rotate all secrets
   - Update security policies

3. **Validation**
   - Security scan all systems
   - Verify no backdoors
   - Monitor for anomalies

### DR Documentation

#### Runbook Updates
- **Frequency**: Monthly
- **Trigger**: After any DR event
- **Owner**: Engineering Team
- **Review**: Management approval

#### Training
- **Frequency**: Quarterly
- **Participants**: All team members
- **Content**: DR procedures, tools, contacts
- **Testing**: Hands-on exercises

### DR Contacts

#### Technical Team
- **DR Lead**: [Name] - [Phone] - [Email]
- **Database Admin**: [Name] - [Phone] - [Email]
- **Infrastructure**: [Name] - [Phone] - [Email]
- **Security**: [Name] - [Phone] - [Email]

#### Management
- **Engineering Manager**: [Name] - [Phone] - [Email]
- **IT Director**: [Name] - [Phone] - [Email]
- **CISO**: [Name] - [Phone] - [Email]

#### External Support
- **Snowflake Support**: [Support Portal]
- **Cloud Provider**: [Support Portal]
- **DR Vendor**: [Support Contacts]

### DR Testing Schedule

#### Monthly Tests
- **Week 1**: Backup validation
- **Week 2**: Time-travel recovery
- **Week 3**: Failover procedures
- **Week 4**: Failback procedures

#### Quarterly Tests
- **Q1**: Full DR drill
- **Q2**: Security breach simulation
- **Q3**: Data corruption recovery
- **Q4**: Complete system failover

### DR Metrics

#### Key Performance Indicators
- **RTO Achievement**: Target vs actual
- **RPO Achievement**: Target vs actual
- **Test Success Rate**: % of successful tests
- **Recovery Time**: Time to full recovery
- **Data Loss**: Amount of data lost

#### Reporting
- **Frequency**: Monthly
- **Recipients**: Management, Engineering
- **Content**: Metrics, issues, improvements
- **Action Items**: Follow-up tasks

### Appendix

#### A. Command Reference
```bash
# Run DR drill
python ops/failover_drill.py

# Check backup status
python -c "
from snowflake.snowpark import Session
import json
with open('snowflake_config.json', 'r') as f:
    config = json.load(f)
session = Session.builder.configs(config).create()
result = session.call('OPS.SP_DAILY_BACKUP')
print(f'Backup result: {result}')
session.close()
"

# Test failover
python -c "
from snowflake.snowpark import Session
import json
with open('snowflake_config.json', 'r') as f:
    config = json.load(f)
session = Session.builder.configs(config).create()
result = session.call('OPS.SP_FAILOVER_DR')
print(f'Failover result: {result}')
session.close()
"
```

#### B. SQL Commands
```sql
-- Check backup status
SELECT * FROM OPS.BACKUP_MONITORING 
WHERE backup_date = CURRENT_DATE();

-- Check replication status
SELECT * FROM OPS.REPLICATION_STATUS;

-- Check DR site health
SELECT * FROM OPS.ENVIRONMENT_HEALTH 
WHERE environment = 'DR';
```

#### C. Monitoring URLs
- **DR Dashboard**: [URL]
- **Backup Status**: [URL]
- **Replication Status**: [URL]
- **Health Checks**: [URL]

---

**Document Version**: 1.0  
**Last Updated**: [Date]  
**Next Review**: [Date]  
**Owner**: Engineering Team
