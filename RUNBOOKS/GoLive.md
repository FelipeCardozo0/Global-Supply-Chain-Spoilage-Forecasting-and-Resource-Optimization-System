# Go-Live Runbook
## Global Supply Chain Spoilage Forecasting Project

### Overview
This runbook provides step-by-step procedures for the production go-live of the Global Supply Chain Spoilage Forecasting system.

### Pre-Go-Live Checklist

#### 1. Environment Readiness
- [ ] **DEV Environment**: All phases (1-8) completed successfully
- [ ] **STG Environment**: Cloned from DEV, validated
- [ ] **PRD Environment**: Cloned from STG, ready for deployment
- [ ] **Warehouses**: COMPUTE_WH, COMPUTE_WH_STG, COMPUTE_WH_PRD configured
- [ ] **Resource Monitors**: Attached to all warehouses
- [ ] **Network Policies**: Configured and active

#### 2. Data Readiness
- [ ] **RAW Data**: All source data loaded and validated
- [ ] **CORE Data**: Unified time series created and validated
- [ ] **FEAT Data**: Feature engineering completed
- [ ] **ML Data**: Models trained and validated
- [ ] **OPS Data**: Operations tables populated

#### 3. Security Readiness
- [ ] **RBAC**: All roles and permissions configured
- [ ] **Secrets**: All secrets rotated and updated
- [ ] **Tags**: Compliance tags applied
- [ ] **Audit**: Access history enabled
- [ ] **Network**: Security policies active

#### 4. Monitoring Readiness
- [ ] **Alerts**: Alert rules configured and tested
- [ ] **Dashboards**: Monitoring dashboards accessible
- [ ] **SLOs**: Service level objectives defined
- [ ] **KPIs**: Key performance indicators tracked
- [ ] **Cost**: Budget tracking and alerts configured

### Go-Live Procedure

#### Phase 1: Pre-Deployment (T-2 hours)
1. **Final Validation**
   ```bash
   python snowpark/execute_phase9.py --validate --environment production
   ```

2. **Backup Current State**
   ```bash
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
   ```

3. **Team Notification**
   - Notify all stakeholders of go-live start
   - Confirm all team members are available
   - Verify communication channels are open

#### Phase 2: Deployment (T-1 hour)
1. **Environment Promotion**
   ```bash
   python snowpark/execute_phase9.py --apply-all --environment production
   ```

2. **Validation Gates**
   - Check all GO/NO-GO gates pass
   - Verify critical tables have data
   - Confirm all services are accessible

3. **Canary Deployment**
   - Deploy to 10% of traffic initially
   - Monitor for 30 minutes
   - Check error rates and performance

#### Phase 3: Full Deployment (T-0)
1. **Traffic Ramp-up**
   - Increase to 50% traffic
   - Monitor for 15 minutes
   - Check system stability

2. **Full Traffic**
   - Route 100% traffic to new system
   - Monitor all metrics
   - Verify all functionality

3. **Post-Deployment Validation**
   - Run end-to-end tests
   - Verify all APIs are responding
   - Check data pipeline is working

#### Phase 4: Post-Go-Live (T+1 hour)
1. **Health Checks**
   - Verify all services are healthy
   - Check error rates are normal
   - Confirm all monitoring is working

2. **Performance Validation**
   - Check response times
   - Verify throughput is as expected
   - Monitor resource usage

3. **Data Validation**
   - Verify data is flowing correctly
   - Check predictions are being generated
   - Confirm alerts are working

### Rollback Procedure

#### Immediate Rollback (if critical issues)
1. **Stop Traffic**
   - Route traffic back to previous version
   - Disable new features
   - Notify users of maintenance

2. **Database Rollback**
   ```sql
   -- Rollback to previous version
   CALL OPS.SP_ROLLBACK_DEPLOY('ML.PREDICTIONS', 'Critical issue detected');
   ```

3. **Service Rollback**
   - Restart services with previous configuration
   - Verify rollback is successful
   - Monitor system stability

#### Gradual Rollback (if minor issues)
1. **Reduce Traffic**
   - Gradually reduce traffic to new system
   - Monitor for improvement
   - Keep some traffic on new system

2. **Fix Issues**
   - Identify and fix problems
   - Test fixes in staging
   - Prepare for re-deployment

3. **Re-deploy**
   - Deploy fixes to production
   - Gradually increase traffic
   - Monitor for stability

### Monitoring and Alerting

#### Key Metrics to Monitor
- **System Health**: CPU, memory, disk usage
- **Database**: Connection count, query performance
- **API**: Response times, error rates
- **Data Pipeline**: Processing time, data quality
- **ML Models**: Prediction accuracy, model drift
- **Costs**: Credit usage, budget consumption

#### Alert Thresholds
- **Critical**: System down, data corruption, security breach
- **High**: High error rates, performance degradation
- **Medium**: Resource usage high, cost over budget
- **Low**: Minor issues, informational alerts

#### Escalation Procedures
1. **Level 1**: On-call engineer (0-15 minutes)
2. **Level 2**: Senior engineer (15-30 minutes)
3. **Level 3**: Engineering manager (30-60 minutes)
4. **Level 4**: Director/VP (60+ minutes)

### Communication Plan

#### Stakeholder Updates
- **T-2 hours**: Go-live start notification
- **T-1 hour**: Deployment in progress
- **T-0**: Go-live complete
- **T+1 hour**: Post-go-live status
- **T+24 hours**: 24-hour summary

#### Communication Channels
- **Slack**: #global-spoilage-alerts
- **Email**: engineering-team@company.com
- **Phone**: On-call rotation
- **Dashboard**: Real-time status page

### Success Criteria

#### Technical Success
- [ ] All services are running
- [ ] All APIs are responding
- [ ] Data pipeline is working
- [ ] ML models are predicting
- [ ] Alerts are functioning
- [ ] Monitoring is active

#### Business Success
- [ ] Users can access the system
- [ ] Predictions are being generated
- [ ] Alerts are being sent
- [ ] Dashboards are accessible
- [ ] Reports are being generated
- [ ] Cost is within budget

#### Operational Success
- [ ] All team members are trained
- [ ] Documentation is complete
- [ ] Runbooks are accessible
- [ ] Escalation procedures are clear
- [ ] Monitoring is comprehensive
- [ ] Support processes are in place

### Post-Go-Live Activities

#### Immediate (First 24 hours)
- Monitor system health continuously
- Respond to any alerts immediately
- Document any issues encountered
- Update stakeholders on status
- Prepare 24-hour summary report

#### Short-term (First week)
- Daily health checks
- Performance optimization
- User feedback collection
- Issue resolution
- Documentation updates

#### Long-term (First month)
- Weekly performance reviews
- Cost optimization
- Feature enhancements
- Process improvements
- Team training updates

### Emergency Contacts

#### Technical Team
- **Lead Engineer**: [Name] - [Phone] - [Email]
- **Database Admin**: [Name] - [Phone] - [Email]
- **ML Engineer**: [Name] - [Phone] - [Email]
- **DevOps Engineer**: [Name] - [Phone] - [Email]

#### Management
- **Engineering Manager**: [Name] - [Phone] - [Email]
- **Product Manager**: [Name] - [Phone] - [Email]
- **Project Sponsor**: [Name] - [Phone] - [Email]

#### External Support
- **Snowflake Support**: [Support Portal]
- **Cloud Provider**: [Support Portal]
- **Third-party Services**: [Support Contacts]

### Appendix

#### A. Command Reference
```bash
# Validate system
python snowpark/execute_phase9.py --validate

# Deploy to production
python snowpark/execute_phase9.py --apply-all --environment production

# Run DR drill
python snowpark/execute_phase9.py --dr-drill

# Generate cost report
python snowpark/execute_phase9.py --cost-report

# Rotate secrets
python snowpark/execute_phase9.py --rotate-secrets
```

#### B. SQL Commands
```sql
-- Check system health
SELECT * FROM OPS.ENVIRONMENT_HEALTH;

-- Check validation results
SELECT * FROM OPS.PHASE9_VALIDATION_SUMMARY;

-- Check cost metrics
SELECT * FROM OPS.FINOPS_DASHBOARD;

-- Check compliance status
SELECT * FROM OPS.COMPLIANCE_SUMMARY;
```

#### C. Monitoring URLs
- **System Dashboard**: [URL]
- **Cost Dashboard**: [URL]
- **Alert Dashboard**: [URL]
- **Performance Dashboard**: [URL]

---

**Document Version**: 1.0  
**Last Updated**: [Date]  
**Next Review**: [Date]  
**Owner**: Engineering Team
