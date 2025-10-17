-- =====================================================
-- PHASE 3: FEATURE ENGINEERING
-- Global Supply Chain Spoilage Forecasting Project
-- =====================================================

USE DATABASE GLOBAL_SPOILAGE_DB;
USE SCHEMA FEAT;

-- =====================================================
-- 1. ROLLING STATISTICS FEATURES
-- =====================================================

CREATE OR REPLACE TABLE FEAT.ROLLING_STATS AS
SELECT 
    date,
    year,
    month,
    quarter,
    
    -- Federal Funds Rate rolling statistics
    fedfunds_rate,
    AVG(fedfunds_rate) OVER (ORDER BY date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS fedfunds_3m_avg,
    AVG(fedfunds_rate) OVER (ORDER BY date ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS fedfunds_6m_avg,
    AVG(fedfunds_rate) OVER (ORDER BY date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS fedfunds_12m_avg,
    STDDEV(fedfunds_rate) OVER (ORDER BY date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS fedfunds_3m_std,
    STDDEV(fedfunds_rate) OVER (ORDER BY date ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS fedfunds_6m_std,
    STDDEV(fedfunds_rate) OVER (ORDER BY date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS fedfunds_12m_std,
    
    -- Retail Sales rolling statistics
    retail_sales,
    AVG(retail_sales) OVER (ORDER BY date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS retail_3m_avg,
    AVG(retail_sales) OVER (ORDER BY date ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS retail_6m_avg,
    AVG(retail_sales) OVER (ORDER BY date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS retail_12m_avg,
    STDDEV(retail_sales) OVER (ORDER BY date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS retail_3m_std,
    STDDEV(retail_sales) OVER (ORDER BY date ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS retail_6m_std,
    STDDEV(retail_sales) OVER (ORDER BY date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS retail_12m_std,
    
    -- Treasury 10Y rolling statistics
    treasury_10y_rate,
    AVG(treasury_10y_rate) OVER (ORDER BY date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS treasury_3m_avg,
    AVG(treasury_10y_rate) OVER (ORDER BY date ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS treasury_6m_avg,
    AVG(treasury_10y_rate) OVER (ORDER BY date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS treasury_12m_avg,
    STDDEV(treasury_10y_rate) OVER (ORDER BY date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS treasury_3m_std,
    STDDEV(treasury_10y_rate) OVER (ORDER BY date ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS treasury_6m_std,
    STDDEV(treasury_10y_rate) OVER (ORDER BY date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS treasury_12m_std,
    
    CURRENT_TIMESTAMP() AS created_at

FROM CORE.UNIFIED_TIME_SERIES
ORDER BY date;

-- =====================================================
-- 2. LAG FEATURES
-- =====================================================

CREATE OR REPLACE TABLE FEAT.LAG_FEATURES AS
SELECT 
    date,
    year,
    month,
    quarter,
    
    -- Federal Funds Rate lags
    fedfunds_rate,
    LAG(fedfunds_rate, 1) OVER (ORDER BY date) AS fedfunds_lag_1m,
    LAG(fedfunds_rate, 3) OVER (ORDER BY date) AS fedfunds_lag_3m,
    LAG(fedfunds_rate, 6) OVER (ORDER BY date) AS fedfunds_lag_6m,
    LAG(fedfunds_rate, 12) OVER (ORDER BY date) AS fedfunds_lag_12m,
    
    -- Retail Sales lags
    retail_sales,
    LAG(retail_sales, 1) OVER (ORDER BY date) AS retail_lag_1m,
    LAG(retail_sales, 3) OVER (ORDER BY date) AS retail_lag_3m,
    LAG(retail_sales, 6) OVER (ORDER BY date) AS retail_lag_6m,
    LAG(retail_sales, 12) OVER (ORDER BY date) AS retail_lag_12m,
    
    -- Treasury 10Y lags
    treasury_10y_rate,
    LAG(treasury_10y_rate, 1) OVER (ORDER BY date) AS treasury_lag_1m,
    LAG(treasury_10y_rate, 3) OVER (ORDER BY date) AS treasury_lag_3m,
    LAG(treasury_10y_rate, 6) OVER (ORDER BY date) AS treasury_lag_6m,
    LAG(treasury_10y_rate, 12) OVER (ORDER BY date) AS treasury_lag_12m,
    
    CURRENT_TIMESTAMP() AS created_at

FROM CORE.UNIFIED_TIME_SERIES
ORDER BY date;

-- =====================================================
-- 3. GROWTH RATE FEATURES
-- =====================================================

CREATE OR REPLACE TABLE FEAT.GROWTH_FEATURES AS
SELECT 
    date,
    year,
    month,
    quarter,
    
    -- Federal Funds Rate growth rates
    fedfunds_rate,
    (fedfunds_rate - LAG(fedfunds_rate, 1) OVER (ORDER BY date)) / NULLIF(LAG(fedfunds_rate, 1) OVER (ORDER BY date), 0) * 100 AS fedfunds_growth_1m,
    (fedfunds_rate - LAG(fedfunds_rate, 3) OVER (ORDER BY date)) / NULLIF(LAG(fedfunds_rate, 3) OVER (ORDER BY date), 0) * 100 AS fedfunds_growth_3m,
    (fedfunds_rate - LAG(fedfunds_rate, 6) OVER (ORDER BY date)) / NULLIF(LAG(fedfunds_rate, 6) OVER (ORDER BY date), 0) * 100 AS fedfunds_growth_6m,
    (fedfunds_rate - LAG(fedfunds_rate, 12) OVER (ORDER BY date)) / NULLIF(LAG(fedfunds_rate, 12) OVER (ORDER BY date), 0) * 100 AS fedfunds_growth_12m,
    
    -- Retail Sales growth rates
    retail_sales,
    (retail_sales - LAG(retail_sales, 1) OVER (ORDER BY date)) / NULLIF(LAG(retail_sales, 1) OVER (ORDER BY date), 0) * 100 AS retail_growth_1m,
    (retail_sales - LAG(retail_sales, 3) OVER (ORDER BY date)) / NULLIF(LAG(retail_sales, 3) OVER (ORDER BY date), 0) * 100 AS retail_growth_3m,
    (retail_sales - LAG(retail_sales, 6) OVER (ORDER BY date)) / NULLIF(LAG(retail_sales, 6) OVER (ORDER BY date), 0) * 100 AS retail_growth_6m,
    (retail_sales - LAG(retail_sales, 12) OVER (ORDER BY date)) / NULLIF(LAG(retail_sales, 12) OVER (ORDER BY date), 0) * 100 AS retail_growth_12m,
    
    -- Treasury 10Y growth rates
    treasury_10y_rate,
    (treasury_10y_rate - LAG(treasury_10y_rate, 1) OVER (ORDER BY date)) / NULLIF(LAG(treasury_10y_rate, 1) OVER (ORDER BY date), 0) * 100 AS treasury_growth_1m,
    (treasury_10y_rate - LAG(treasury_10y_rate, 3) OVER (ORDER BY date)) / NULLIF(LAG(treasury_10y_rate, 3) OVER (ORDER BY date), 0) * 100 AS treasury_growth_3m,
    (treasury_10y_rate - LAG(treasury_10y_rate, 6) OVER (ORDER BY date)) / NULLIF(LAG(treasury_10y_rate, 6) OVER (ORDER BY date), 0) * 100 AS treasury_growth_6m,
    (treasury_10y_rate - LAG(treasury_10y_rate, 12) OVER (ORDER BY date)) / NULLIF(LAG(treasury_10y_rate, 12) OVER (ORDER BY date), 0) * 100 AS treasury_growth_12m,
    
    CURRENT_TIMESTAMP() AS created_at

FROM CORE.UNIFIED_TIME_SERIES
ORDER BY date;

-- =====================================================
-- 4. VOLATILITY FEATURES
-- =====================================================

CREATE OR REPLACE TABLE FEAT.VOLATILITY_FEATURES AS
SELECT 
    date,
    year,
    month,
    quarter,
    
    -- Federal Funds Rate volatility
    fedfunds_rate,
    STDDEV(fedfunds_rate) OVER (ORDER BY date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) / NULLIF(AVG(fedfunds_rate) OVER (ORDER BY date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS fedfunds_volatility_3m,
    STDDEV(fedfunds_rate) OVER (ORDER BY date ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) / NULLIF(AVG(fedfunds_rate) OVER (ORDER BY date ROWS BETWEEN 5 PRECEDING AND CURRENT ROW), 0) AS fedfunds_volatility_6m,
    STDDEV(fedfunds_rate) OVER (ORDER BY date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) / NULLIF(AVG(fedfunds_rate) OVER (ORDER BY date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW), 0) AS fedfunds_volatility_12m,
    
    -- Retail Sales volatility
    retail_sales,
    STDDEV(retail_sales) OVER (ORDER BY date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) / NULLIF(AVG(retail_sales) OVER (ORDER BY date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS retail_volatility_3m,
    STDDEV(retail_sales) OVER (ORDER BY date ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) / NULLIF(AVG(retail_sales) OVER (ORDER BY date ROWS BETWEEN 5 PRECEDING AND CURRENT ROW), 0) AS retail_volatility_6m,
    STDDEV(retail_sales) OVER (ORDER BY date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) / NULLIF(AVG(retail_sales) OVER (ORDER BY date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW), 0) AS retail_volatility_12m,
    
    -- Treasury 10Y volatility
    treasury_10y_rate,
    STDDEV(treasury_10y_rate) OVER (ORDER BY date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) / NULLIF(AVG(treasury_10y_rate) OVER (ORDER BY date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS treasury_volatility_3m,
    STDDEV(treasury_10y_rate) OVER (ORDER BY date ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) / NULLIF(AVG(treasury_10y_rate) OVER (ORDER BY date ROWS BETWEEN 5 PRECEDING AND CURRENT ROW), 0) AS treasury_volatility_6m,
    STDDEV(treasury_10y_rate) OVER (ORDER BY date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) / NULLIF(AVG(treasury_10y_rate) OVER (ORDER BY date ROWS BETWEEN 11 PRECEDING AND CURRENT ROW), 0) AS treasury_volatility_12m,
    
    CURRENT_TIMESTAMP() AS created_at

FROM CORE.UNIFIED_TIME_SERIES
ORDER BY date;

-- =====================================================
-- 5. MASTER FEATURES TABLE
-- =====================================================

CREATE OR REPLACE TABLE FEAT.MASTER_FEATURES AS
SELECT 
    uts.date,
    uts.year,
    uts.month,
    uts.quarter,
    uts.day_of_week,
    uts.day_of_year,
    
    -- Original economic indicators
    uts.fedfunds_rate,
    uts.retail_sales,
    uts.treasury_10y_rate,
    uts.population,
    uts.gdp_per_capita,
    uts.inflation_rate,
    uts.unemployment_rate,
    
    -- Rolling statistics
    rs.fedfunds_3m_avg,
    rs.fedfunds_6m_avg,
    rs.fedfunds_12m_avg,
    rs.fedfunds_3m_std,
    rs.fedfunds_6m_std,
    rs.fedfunds_12m_std,
    rs.retail_3m_avg,
    rs.retail_6m_avg,
    rs.retail_12m_avg,
    rs.retail_3m_std,
    rs.retail_6m_std,
    rs.retail_12m_std,
    rs.treasury_3m_avg,
    rs.treasury_6m_avg,
    rs.treasury_12m_avg,
    rs.treasury_3m_std,
    rs.treasury_6m_std,
    rs.treasury_12m_std,
    
    -- Lag features
    lf.fedfunds_lag_1m,
    lf.fedfunds_lag_3m,
    lf.fedfunds_lag_6m,
    lf.fedfunds_lag_12m,
    lf.retail_lag_1m,
    lf.retail_lag_3m,
    lf.retail_lag_6m,
    lf.retail_lag_12m,
    lf.treasury_lag_1m,
    lf.treasury_lag_3m,
    lf.treasury_lag_6m,
    lf.treasury_lag_12m,
    
    -- Growth features
    gf.fedfunds_growth_1m,
    gf.fedfunds_growth_3m,
    gf.fedfunds_growth_6m,
    gf.fedfunds_growth_12m,
    gf.retail_growth_1m,
    gf.retail_growth_3m,
    gf.retail_growth_6m,
    gf.retail_growth_12m,
    gf.treasury_growth_1m,
    gf.treasury_growth_3m,
    gf.treasury_growth_6m,
    gf.treasury_growth_12m,
    
    -- Volatility features
    vf.fedfunds_volatility_3m,
    vf.fedfunds_volatility_6m,
    vf.fedfunds_volatility_12m,
    vf.retail_volatility_3m,
    vf.retail_volatility_6m,
    vf.retail_volatility_12m,
    vf.treasury_volatility_3m,
    vf.treasury_volatility_6m,
    vf.treasury_volatility_12m,
    
    -- Derived features
    CASE WHEN uts.fedfunds_rate > uts.treasury_10y_rate THEN 1 ELSE 0 END AS yield_curve_inversion,
    uts.fedfunds_rate - uts.treasury_10y_rate AS yield_spread,
    uts.retail_sales / NULLIF(uts.population, 0) AS retail_sales_per_capita,
    uts.gdp_per_capita * uts.population AS total_gdp,
    
    CURRENT_TIMESTAMP() AS created_at

FROM CORE.UNIFIED_TIME_SERIES uts
LEFT JOIN FEAT.ROLLING_STATS rs ON uts.date = rs.date
LEFT JOIN FEAT.LAG_FEATURES lf ON uts.date = lf.date
LEFT JOIN FEAT.GROWTH_FEATURES gf ON uts.date = gf.date
LEFT JOIN FEAT.VOLATILITY_FEATURES vf ON uts.date = vf.date
ORDER BY uts.date;

-- =====================================================
-- 6. FEATURE AUDIT TABLE
-- =====================================================

CREATE OR REPLACE TABLE FEAT.FEATURE_AUDIT AS
SELECT 
    'MASTER_FEATURES' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(CASE WHEN fedfunds_rate IS NOT NULL THEN 1 END) AS non_null_fedfunds,
    COUNT(CASE WHEN retail_sales IS NOT NULL THEN 1 END) AS non_null_retail,
    COUNT(CASE WHEN treasury_10y_rate IS NOT NULL THEN 1 END) AS non_null_treasury,
    MIN(date) AS min_date,
    MAX(date) AS max_date,
    CURRENT_TIMESTAMP() AS created_at
FROM FEAT.MASTER_FEATURES

UNION ALL

SELECT 
    'ROLLING_STATS' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(CASE WHEN fedfunds_3m_avg IS NOT NULL THEN 1 END) AS non_null_3m_avg,
    COUNT(CASE WHEN fedfunds_6m_avg IS NOT NULL THEN 1 END) AS non_null_6m_avg,
    COUNT(CASE WHEN fedfunds_12m_avg IS NOT NULL THEN 1 END) AS non_null_12m_avg,
    MIN(date) AS min_date,
    MAX(date) AS max_date,
    CURRENT_TIMESTAMP() AS created_at
FROM FEAT.ROLLING_STATS;

-- =====================================================
-- 7. AUDIT LOG
-- =====================================================

INSERT INTO OPS.LOAD_AUDIT (
    execution_id,
    phase,
    step,
    execution_ts,
    status,
    rows_affected,
    execution_time_seconds,
    error_message
) VALUES (
    'PHASE3_' || CURRENT_TIMESTAMP()::STRING,
    'PHASE_3',
    'FEATURE_ENGINEERING',
    CURRENT_TIMESTAMP(),
    'SUCCESS',
    (SELECT COUNT(*) FROM FEAT.MASTER_FEATURES),
    0,
    NULL
);

-- Success message
SELECT 'Phase 3: Feature Engineering completed successfully!' AS status;
