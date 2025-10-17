# FinOps Runbook
## Global Supply Chain Spoilage Forecasting Project

### Overview
This runbook provides comprehensive financial operations (FinOps) procedures for cost monitoring, budget management, and cost optimization of the Global Supply Chain Spoilage Forecasting system.

### Cost Management Framework

#### Budget Structure
- **Production**: $150/month (50 credits)
- **Staging**: $60/month (20 credits)
- **Development**: $30/month (10 credits)
- **Total Budget**: $240/month (80 credits)

#### Cost Categories
- **Compute**: Warehouse usage (70%)
- **Storage**: Data storage (20%)
- **Network**: Data transfer (5%)
- **Services**: External services (5%)

### Cost Monitoring

#### Daily Cost Tracking
```bash
# Generate daily cost report
python ops/cost_report.py
```

**What it tracks:**
- Warehouse credit usage
- Storage costs
- Query performance
- Cost by query type
- Budget variance

#### Weekly Cost Analysis
```sql
-- Weekly cost summary
SELECT * FROM OPS.MONTHLY_COST_SUMMARY
WHERE WAREHOUSE_NAME IN ('COMPUTE_WH', 'COMPUTE_WH_STG', 'COMPUTE_WH_PRD');

-- Cost by query type
SELECT * FROM OPS.COST_BY_QUERY_TYPE
ORDER BY TOTAL_COST_USD DESC;
```

#### Monthly Cost Review
- **Budget vs Actual**: Variance analysis
- **Cost Trends**: Month-over-month changes
- **Optimization Opportunities**: Cost reduction areas
- **Forecasting**: Next month predictions

### Budget Management

#### Budget Tracking
```sql
-- Check budget status
SELECT * FROM OPS.BUDGET_TRACKING 
WHERE is_active = TRUE;

-- Check budget alerts
SELECT * FROM OPS.COST_ALERTS 
WHERE is_acknowledged = FALSE;
```

#### Budget Alerts
- **75% Threshold**: Warning alert
- **90% Threshold**: High alert
- **100% Threshold**: Critical alert
- **Over Budget**: Emergency alert

#### Budget Adjustments
1. **Monthly Review**
   - Analyze spending patterns
   - Identify optimization opportunities
   - Adjust budgets if needed

2. **Quarterly Planning**
   - Review annual budget
   - Plan for growth
   - Allocate resources

### Cost Optimization

#### Warehouse Optimization
```sql
-- Check warehouse efficiency
SELECT 
    WAREHOUSE_NAME,
    TOTAL_CREDITS,
    QUERY_COUNT,
    TOTAL_CREDITS / QUERY_COUNT AS CREDITS_PER_QUERY
FROM OPS.WH_COST_7D
ORDER BY CREDITS_PER_QUERY DESC;
```

**Optimization Strategies:**
- **Right-sizing**: Match warehouse size to workload
- **Auto-suspend**: Suspend unused warehouses
- **Query Optimization**: Improve query performance
- **Resource Sharing**: Share warehouses across teams

#### Query Optimization
```sql
-- Find expensive queries
SELECT 
    QUERY_TYPE,
    AVG_CREDITS_PER_QUERY,
    TOTAL_COST_USD
FROM OPS.COST_BY_QUERY_TYPE
WHERE AVG_CREDITS_PER_QUERY > 1.0
ORDER BY AVG_CREDITS_PER_QUERY DESC;
```

**Optimization Techniques:**
- **Query Tuning**: Optimize SQL queries
- **Indexing**: Add appropriate indexes
- **Partitioning**: Partition large tables
- **Caching**: Cache frequently accessed data

#### Storage Optimization
```sql
-- Check storage usage
SELECT 
    TABLE_CATALOG,
    TABLE_SCHEMA,
    TABLE_NAME,
    BYTES,
    ROW_COUNT
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
ORDER BY BYTES DESC;
```

**Optimization Strategies:**
- **Data Compression**: Compress large tables
- **Archiving**: Archive old data
- **Cleanup**: Remove unused data
- **Partitioning**: Partition by date/region

### Cost Reporting

#### Daily Reports
```bash
# Generate daily cost report
python ops/cost_report.py --daily
```

**Report Contents:**
- Daily credit usage
- Cost by warehouse
- Budget variance
- Alerts and warnings

#### Weekly Reports
```bash
# Generate weekly cost report
python ops/cost_report.py --weekly
```

**Report Contents:**
- Weekly cost summary
- Cost trends
- Optimization recommendations
- Budget status

#### Monthly Reports
```bash
# Generate monthly cost report
python ops/cost_report.py --monthly
```

**Report Contents:**
- Monthly cost analysis
- Budget vs actual
- Cost forecasting
- Optimization opportunities

### Cost Alerts

#### Alert Configuration
```sql
-- Configure cost alerts
INSERT INTO OPS.COST_ALERTS (
    alert_type, alert_severity, alert_message, 
    current_spend_usd, threshold_usd
) VALUES (
    'BUDGET_THRESHOLD', 'HIGH', 
    'Production warehouse approaching budget limit',
    120.00, 150.00
);
```

#### Alert Types
- **Budget Threshold**: Spending approaching limit
- **Unusual Spend**: Unexpected cost spikes
- **Resource Usage**: High resource consumption
- **Cost Anomaly**: Unusual cost patterns

#### Alert Response
1. **Immediate Response**
   - Acknowledge alert
   - Investigate cause
   - Take corrective action

2. **Follow-up Actions**
   - Analyze spending patterns
   - Implement optimizations
   - Update budgets if needed

### Cost Forecasting

#### Monthly Forecasting
```sql
-- Generate cost forecast
SELECT 
    WAREHOUSE_NAME,
    AVG(TOTAL_CREDITS) AS AVG_CREDITS,
    AVG(TOTAL_CREDITS) * 30 AS FORECASTED_CREDITS,
    AVG(TOTAL_CREDITS) * 30 * 3.0 AS FORECASTED_COST_USD
FROM OPS.WH_COST_7D
WHERE USAGE_DATE >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY WAREHOUSE_NAME;
```

#### Quarterly Planning
- **Q1**: Baseline costs and trends
- **Q2**: Growth projections
- **Q3**: Optimization opportunities
- **Q4**: Annual planning

### Cost Governance

#### Approval Process
1. **Budget Requests**
   - Submit budget increase request
   - Justify business need
   - Get management approval

2. **Cost Overruns**
   - Document overrun cause
   - Implement cost controls
   - Get approval for additional budget

#### Cost Controls
- **Automatic Suspension**: Suspend warehouses at budget limit
- **Resource Limits**: Set credit quotas
- **Approval Workflows**: Require approval for large expenses
- **Regular Reviews**: Monthly cost reviews

### Cost Optimization Best Practices

#### Warehouse Management
1. **Right-sizing**
   - Start with small warehouse
   - Scale up based on need
   - Use auto-suspend

2. **Query Optimization**
   - Use appropriate filters
   - Limit result sets
   - Use indexes effectively

3. **Resource Sharing**
   - Share warehouses across teams
   - Use multi-cluster warehouses
   - Implement resource queues

#### Data Management
1. **Storage Optimization**
   - Compress large tables
   - Archive old data
   - Use appropriate data types

2. **Query Efficiency**
   - Use columnar storage
   - Implement partitioning
   - Cache frequently accessed data

### Cost Reporting Automation

#### Automated Reports
```bash
# Daily cost report (6 AM UTC)
python ops/cost_report.py --daily --send-slack

# Weekly cost report (Monday 9 AM UTC)
python ops/cost_report.py --weekly --send-email

# Monthly cost report (1st of month)
python ops/cost_report.py --monthly --send-email
```

#### Report Recipients
- **Daily**: Engineering team
- **Weekly**: Management team
- **Monthly**: Finance team
- **Alerts**: On-call engineer

### Cost Analysis Tools

#### Snowflake Cost Views
```sql
-- Warehouse cost analysis
SELECT * FROM OPS.WH_COST_7D;

-- Monthly cost summary
SELECT * FROM OPS.MONTHLY_COST_SUMMARY;

-- Cost by query type
SELECT * FROM OPS.COST_BY_QUERY_TYPE;

-- FinOps dashboard
SELECT * FROM OPS.FINOPS_DASHBOARD;
```

#### External Tools
- **Snowflake Cost Management**: Native cost tracking
- **Cloud Cost Tools**: AWS/Azure cost analysis
- **Third-party Tools**: Cost optimization platforms

### Cost Optimization Recommendations

#### Immediate Actions (0-30 days)
1. **Enable Auto-suspend**
   ```sql
   ALTER WAREHOUSE COMPUTE_WH SET AUTO_SUSPEND = 300;
   ```

2. **Optimize Queries**
   - Review expensive queries
   - Add appropriate filters
   - Use indexes effectively

3. **Right-size Warehouses**
   - Start with small size
   - Scale based on need
   - Monitor performance

#### Medium-term Actions (30-90 days)
1. **Implement Resource Sharing**
   - Share warehouses across teams
   - Use multi-cluster warehouses
   - Monitor usage

2. **Optimize Storage**
   - Compress large tables
   - Archive old data
   - Use appropriate data types

#### Long-term Actions (90+ days)
1. **Architecture Optimization**
   - Review data architecture
   - Implement data partitioning
   - Optimize data flows

2. **Process Improvement**
   - Implement cost governance
   - Regular cost reviews
   - Continuous optimization

### Cost Monitoring Dashboard

#### Key Metrics
- **Daily Cost**: Current day spending
- **Monthly Cost**: Month-to-date spending
- **Budget Variance**: Actual vs budget
- **Cost Trends**: Month-over-month changes
- **Optimization Score**: Cost efficiency rating

#### Alerts and Warnings
- **Budget Alerts**: Approaching limits
- **Cost Spikes**: Unusual spending
- **Resource Usage**: High consumption
- **Optimization Opportunities**: Cost reduction areas

### Cost Governance Framework

#### Roles and Responsibilities
- **Engineering Team**: Cost optimization
- **Finance Team**: Budget management
- **Management**: Cost approval
- **Operations**: Cost monitoring

#### Decision Making
1. **Cost Thresholds**
   - < $100: Engineering approval
   - $100-$500: Manager approval
   - > $500: Director approval

2. **Budget Changes**
   - < 10%: Manager approval
   - 10-25%: Director approval
   - > 25%: VP approval

### Cost Optimization Success Metrics

#### Key Performance Indicators
- **Cost per Prediction**: Cost efficiency
- **Budget Variance**: Actual vs planned
- **Optimization ROI**: Savings achieved
- **Cost Trends**: Month-over-month changes

#### Success Criteria
- **Cost Reduction**: 10% year-over-year
- **Budget Adherence**: Within 5% of budget
- **Efficiency Improvement**: 20% cost per unit
- **Optimization Rate**: 5% monthly savings

### Appendix

#### A. Command Reference
```bash
# Generate cost report
python ops/cost_report.py

# Generate daily report
python ops/cost_report.py --daily

# Generate weekly report
python ops/cost_report.py --weekly

# Generate monthly report
python ops/cost_report.py --monthly

# Send to Slack
python ops/cost_report.py --send-slack

# Send to email
python ops/cost_report.py --send-email
```

#### B. SQL Commands
```sql
-- Check warehouse costs
SELECT * FROM OPS.WH_COST_7D;

-- Check budget status
SELECT * FROM OPS.BUDGET_TRACKING;

-- Check cost alerts
SELECT * FROM OPS.COST_ALERTS;

-- Check optimization recommendations
SELECT * FROM OPS.COST_OPTIMIZATION_RECOMMENDATIONS;
```

#### C. Monitoring URLs
- **Cost Dashboard**: [URL]
- **Budget Dashboard**: [URL]
- **Optimization Dashboard**: [URL]
- **Alert Dashboard**: [URL]

---

**Document Version**: 1.0  
**Last Updated**: [Date]  
**Next Review**: [Date]  
**Owner**: Engineering Team
