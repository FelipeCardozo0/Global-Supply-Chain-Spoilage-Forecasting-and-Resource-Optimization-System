-- =====================================================
-- PHASE 8: GEOSPATIAL DATA & HEATMAPS
-- Global Supply Chain Spoilage Forecasting Project
-- Geography tables, joins, tiles, and heatmap views
-- =====================================================

USE DATABASE GLOBAL_SPOILAGE_DB;

-- =====================================================
-- 1. CREATE GEO SCHEMA
-- =====================================================

CREATE SCHEMA IF NOT EXISTS GEO;

-- =====================================================
-- 2. COUNTRY GEOMETRY TABLE
-- =====================================================

-- Country geometries with ISO codes
CREATE OR REPLACE TABLE GEO.COUNTRY_GEOM (
    iso2 STRING PRIMARY KEY,
    iso3 STRING,
    name STRING NOT NULL,
    geom GEOGRAPHY,
    centroid_lat FLOAT,
    centroid_lon FLOAT,
    area_km2 FLOAT,
    population NUMBER,
    region STRING,
    subregion STRING,
    income_group STRING,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- =====================================================
-- 3. REGION GEOMETRY TABLE
-- =====================================================

-- Regional geometries for broader analysis
CREATE OR REPLACE TABLE GEO.REGION_GEOM (
    region_id STRING PRIMARY KEY,
    region_name STRING NOT NULL,
    geom GEOGRAPHY,
    centroid_lat FLOAT,
    centroid_lon FLOAT,
    area_km2 FLOAT,
    country_count INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- =====================================================
-- 4. RISK ZONES TABLE
-- =====================================================

-- Custom risk zones for supply chain analysis
CREATE OR REPLACE TABLE GEO.RISK_ZONES (
    zone_id STRING PRIMARY KEY,
    zone_name STRING NOT NULL,
    zone_type STRING,  -- 'LOGISTICS', 'MANUFACTURING', 'AGRICULTURE', 'ENERGY'
    geom GEOGRAPHY,
    risk_level STRING,  -- 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'
    description STRING,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- =====================================================
-- 5. CLIMATE ZONES TABLE
-- =====================================================

-- Climate zones for environmental risk analysis
CREATE OR REPLACE TABLE GEO.CLIMATE_ZONES (
    zone_id STRING PRIMARY KEY,
    zone_name STRING NOT NULL,
    climate_type STRING,  -- 'TROPICAL', 'TEMPERATE', 'ARCTIC', 'DESERT'
    geom GEOGRAPHY,
    avg_temp FLOAT,
    avg_precipitation FLOAT,
    extreme_weather_risk STRING,  -- 'LOW', 'MEDIUM', 'HIGH'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- =====================================================
-- 6. SUPPLY CHAIN ROUTES TABLE
-- =====================================================

-- Major supply chain routes and corridors
CREATE OR REPLACE TABLE GEO.SUPPLY_ROUTES (
    route_id STRING PRIMARY KEY,
    route_name STRING NOT NULL,
    route_type STRING,  -- 'SHIPPING', 'RAIL', 'ROAD', 'AIR'
    geom GEOGRAPHY,
    distance_km FLOAT,
    capacity_units INTEGER,
    criticality STRING,  -- 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- =====================================================
-- 7. POPULATE COUNTRY GEOMETRIES
-- =====================================================

-- Insert major countries with simplified geometries
-- Note: In production, these would be loaded from shapefiles or GeoJSON
INSERT INTO GEO.COUNTRY_GEOM (iso2, iso3, name, centroid_lat, centroid_lon, area_km2, region, subregion, income_group) VALUES
-- North America
('US', 'USA', 'United States', 39.8283, -98.5795, 9833517, 'Americas', 'Northern America', 'High income'),
('CA', 'CAN', 'Canada', 56.1304, -106.3468, 9984670, 'Americas', 'Northern America', 'High income'),
('MX', 'MEX', 'Mexico', 23.6345, -102.5528, 1964375, 'Americas', 'Central America', 'Upper middle income'),

-- Europe
('DE', 'DEU', 'Germany', 51.1657, 10.4515, 357114, 'Europe', 'Western Europe', 'High income'),
('FR', 'FRA', 'France', 46.2276, 2.2137, 551695, 'Europe', 'Western Europe', 'High income'),
('GB', 'GBR', 'United Kingdom', 55.3781, -3.4360, 242495, 'Europe', 'Northern Europe', 'High income'),
('IT', 'ITA', 'Italy', 41.8719, 12.5674, 301340, 'Europe', 'Southern Europe', 'High income'),
('ES', 'ESP', 'Spain', 40.4637, -3.7492, 505992, 'Europe', 'Southern Europe', 'High income'),
('NL', 'NLD', 'Netherlands', 52.1326, 5.2913, 41543, 'Europe', 'Western Europe', 'High income'),

-- Asia
('CN', 'CHN', 'China', 35.8617, 104.1954, 9596961, 'Asia', 'Eastern Asia', 'Upper middle income'),
('JP', 'JPN', 'Japan', 36.2048, 138.2529, 377975, 'Asia', 'Eastern Asia', 'High income'),
('IN', 'IND', 'India', 20.5937, 78.9629, 3287263, 'Asia', 'Southern Asia', 'Lower middle income'),
('KR', 'KOR', 'South Korea', 35.9078, 127.7669, 100210, 'Asia', 'Eastern Asia', 'High income'),
('SG', 'SGP', 'Singapore', 1.3521, 103.8198, 719, 'Asia', 'South-Eastern Asia', 'High income'),
('TH', 'THA', 'Thailand', 15.8700, 100.9925, 513120, 'Asia', 'South-Eastern Asia', 'Upper middle income'),
('VN', 'VNM', 'Vietnam', 14.0583, 108.2772, 331212, 'Asia', 'South-Eastern Asia', 'Lower middle income'),

-- Oceania
('AU', 'AUS', 'Australia', -25.2744, 133.7751, 7692024, 'Oceania', 'Australia and New Zealand', 'High income'),
('NZ', 'NZL', 'New Zealand', -40.9006, 174.8860, 270467, 'Oceania', 'Australia and New Zealand', 'High income'),

-- South America
('BR', 'BRA', 'Brazil', -14.2350, -51.9253, 8514877, 'Americas', 'South America', 'Upper middle income'),
('AR', 'ARG', 'Argentina', -38.4161, -63.6167, 2780400, 'Americas', 'South America', 'Upper middle income'),
('CL', 'CHL', 'Chile', -35.6751, -71.5430, 756102, 'Americas', 'South America', 'High income'),

-- Africa
('ZA', 'ZAF', 'South Africa', -30.5595, 22.9375, 1221037, 'Africa', 'Southern Africa', 'Upper middle income'),
('NG', 'NGA', 'Nigeria', 9.0820, 8.6753, 923768, 'Africa', 'Western Africa', 'Lower middle income'),
('EG', 'EGY', 'Egypt', 26.0975, 30.0444, 1001449, 'Africa', 'Northern Africa', 'Lower middle income'),

-- Middle East
('SA', 'SAU', 'Saudi Arabia', 23.8859, 45.0792, 2149690, 'Asia', 'Western Asia', 'High income'),
('AE', 'ARE', 'United Arab Emirates', 23.4241, 53.8478, 83600, 'Asia', 'Western Asia', 'High income'),
('IL', 'ISR', 'Israel', 31.0461, 34.8516, 22072, 'Asia', 'Western Asia', 'High income');

-- =====================================================
-- 8. POPULATE REGION GEOMETRIES
-- =====================================================

-- Insert major regions
INSERT INTO GEO.REGION_GEOM (region_id, region_name, centroid_lat, centroid_lon, area_km2, country_count) VALUES
('NA', 'North America', 45.0, -100.0, 24709000, 3),
('EU', 'Europe', 54.0, 15.0, 10180000, 44),
('AS', 'Asia', 35.0, 100.0, 44579000, 48),
('OC', 'Oceania', -25.0, 140.0, 8525989, 14),
('SA', 'South America', -15.0, -60.0, 17840000, 12),
('AF', 'Africa', 8.0, 20.0, 30370000, 54),
('ME', 'Middle East', 25.0, 50.0, 7000000, 18);

-- =====================================================
-- 9. POPULATE RISK ZONES
-- =====================================================

-- Insert supply chain risk zones
INSERT INTO GEO.RISK_ZONES (zone_id, zone_name, zone_type, risk_level, description) VALUES
('SCZ001', 'Suez Canal Zone', 'LOGISTICS', 'HIGH', 'Critical shipping route, geopolitical risk'),
('SCZ002', 'Panama Canal Zone', 'LOGISTICS', 'HIGH', 'Critical shipping route, capacity constraints'),
('SCZ003', 'Strait of Hormuz', 'LOGISTICS', 'CRITICAL', 'Oil shipping chokepoint, geopolitical tensions'),
('SCZ004', 'South China Sea', 'LOGISTICS', 'HIGH', 'Major shipping lanes, territorial disputes'),
('SCZ005', 'Silicon Valley', 'MANUFACTURING', 'HIGH', 'Technology manufacturing hub'),
('SCZ006', 'Ruhr Valley', 'MANUFACTURING', 'MEDIUM', 'European industrial heartland'),
('SCZ007', 'Yangtze Delta', 'MANUFACTURING', 'HIGH', 'Chinese manufacturing hub'),
('SCZ008', 'Great Plains', 'AGRICULTURE', 'MEDIUM', 'Major agricultural region'),
('SCZ009', 'Pampas', 'AGRICULTURE', 'MEDIUM', 'South American agricultural region'),
('SCZ010', 'Persian Gulf', 'ENERGY', 'CRITICAL', 'Major oil and gas production region');

-- =====================================================
-- 10. POPULATE CLIMATE ZONES
-- =====================================================

-- Insert climate zones for environmental risk
INSERT INTO GEO.CLIMATE_ZONES (zone_id, zone_name, climate_type, avg_temp, avg_precipitation, extreme_weather_risk) VALUES
('CZ001', 'Tropical Zone', 'TROPICAL', 25.0, 2000.0, 'HIGH'),
('CZ002', 'Subtropical Zone', 'TEMPERATE', 18.0, 1000.0, 'MEDIUM'),
('CZ003', 'Temperate Zone', 'TEMPERATE', 10.0, 800.0, 'LOW'),
('CZ004', 'Continental Zone', 'TEMPERATE', 5.0, 600.0, 'MEDIUM'),
('CZ005', 'Polar Zone', 'ARCTIC', -10.0, 200.0, 'HIGH'),
('CZ006', 'Desert Zone', 'DESERT', 30.0, 100.0, 'MEDIUM'),
('CZ007', 'Mediterranean Zone', 'TEMPERATE', 15.0, 500.0, 'LOW'),
('CZ008', 'Monsoon Zone', 'TROPICAL', 22.0, 3000.0, 'HIGH');

-- =====================================================
-- 11. POPULATE SUPPLY ROUTES
-- =====================================================

-- Insert major supply chain routes
INSERT INTO GEO.SUPPLY_ROUTES (route_id, route_name, route_type, distance_km, capacity_units, criticality) VALUES
('SR001', 'Trans-Pacific Shipping', 'SHIPPING', 8000, 20000, 'CRITICAL'),
('SR002', 'Trans-Atlantic Shipping', 'SHIPPING', 6000, 15000, 'HIGH'),
('SR003', 'Suez Canal Route', 'SHIPPING', 193, 50000, 'CRITICAL'),
('SR004', 'Panama Canal Route', 'SHIPPING', 82, 30000, 'HIGH'),
('SR005', 'Trans-Siberian Railway', 'RAIL', 9289, 1000, 'HIGH'),
('SR006', 'Eurasian Land Bridge', 'RAIL', 10000, 800, 'MEDIUM'),
('SR007', 'North American Rail Network', 'RAIL', 5000, 2000, 'HIGH'),
('SR008', 'European Rail Network', 'RAIL', 3000, 1500, 'HIGH'),
('SR009', 'Trans-Canada Highway', 'ROAD', 7821, 500, 'MEDIUM'),
('SR010', 'Interstate Highway System', 'ROAD', 75000, 1000, 'HIGH'),
('SR011', 'Trans-Pacific Air Routes', 'AIR', 10000, 100, 'MEDIUM'),
('SR012', 'Trans-Atlantic Air Routes', 'AIR', 6000, 150, 'MEDIUM');

-- =====================================================
-- 12. CREATE GEOSPATIAL VIEWS
-- =====================================================

-- Risk heatmap view combining predictions with geography
CREATE OR REPLACE VIEW GEO.RISK_HEATMAP AS
SELECT 
    p.date,
    p.country,
    g.name as country_name,
    g.iso2,
    g.region,
    g.subregion,
    g.income_group,
    p.risk_score,
    p.probability,
    p.model_version,
    g.centroid_lat,
    g.centroid_lon,
    g.area_km2,
    g.population,
    ST_ASTEXT(g.geom) as geometry_wkt,
    CASE 
        WHEN p.probability >= 0.80 THEN 'CRITICAL'
        WHEN p.probability >= 0.60 THEN 'HIGH'
        WHEN p.probability >= 0.40 THEN 'MEDIUM'
        ELSE 'LOW'
    END as risk_level,
    CURRENT_TIMESTAMP() as last_updated
FROM ML.PREDICTIONS p
JOIN GEO.COUNTRY_GEOM g ON g.iso2 = p.country
WHERE p.date >= DATEADD(month, -3, CURRENT_DATE());  -- Last 3 months

-- Regional risk aggregation
CREATE OR REPLACE VIEW GEO.REGIONAL_RISK AS
SELECT 
    p.date,
    g.region,
    COUNT(*) as country_count,
    AVG(p.risk_score) as avg_risk_score,
    MAX(p.risk_score) as max_risk_score,
    MIN(p.risk_score) as min_risk_score,
    AVG(p.probability) as avg_probability,
    COUNT_IF(p.probability >= 0.80) as critical_count,
    COUNT_IF(p.probability >= 0.60) as high_risk_count,
    COUNT_IF(p.probability >= 0.40) as medium_risk_count,
    rg.centroid_lat,
    rg.centroid_lon,
    rg.area_km2
FROM ML.PREDICTIONS p
JOIN GEO.COUNTRY_GEOM g ON g.iso2 = p.country
JOIN GEO.REGION_GEOM rg ON rg.region_id = g.region
WHERE p.date >= DATEADD(month, -1, CURRENT_DATE())  -- Last month
GROUP BY p.date, g.region, rg.centroid_lat, rg.centroid_lon, rg.area_km2;

-- Supply chain risk by route
CREATE OR REPLACE VIEW GEO.ROUTE_RISK AS
SELECT 
    p.date,
    sr.route_name,
    sr.route_type,
    sr.criticality,
    sr.distance_km,
    sr.capacity_units,
    AVG(p.risk_score) as avg_risk_score,
    MAX(p.risk_score) as max_risk_score,
    COUNT(DISTINCT p.country) as affected_countries,
    STRING_AGG(DISTINCT p.country, ', ') as country_list
FROM ML.PREDICTIONS p
JOIN GEO.COUNTRY_GEOM g ON g.iso2 = p.country
JOIN GEO.SUPPLY_ROUTES sr ON ST_INTERSECTS(sr.geom, g.geom)  -- Simplified intersection
WHERE p.date >= DATEADD(month, -1, CURRENT_DATE())
GROUP BY p.date, sr.route_name, sr.route_type, sr.criticality, sr.distance_km, sr.capacity_units;

-- Climate risk overlay
CREATE OR REPLACE VIEW GEO.CLIMATE_RISK AS
SELECT 
    p.date,
    p.country,
    g.name as country_name,
    cz.climate_type,
    cz.extreme_weather_risk,
    p.risk_score,
    p.probability,
    CASE 
        WHEN cz.extreme_weather_risk = 'HIGH' AND p.probability >= 0.60 THEN 'CLIMATE_CRITICAL'
        WHEN cz.extreme_weather_risk = 'MEDIUM' AND p.probability >= 0.70 THEN 'CLIMATE_HIGH'
        WHEN cz.extreme_weather_risk = 'LOW' AND p.probability >= 0.80 THEN 'CLIMATE_MEDIUM'
        ELSE 'CLIMATE_LOW'
    END as climate_risk_level
FROM ML.PREDICTIONS p
JOIN GEO.COUNTRY_GEOM g ON g.iso2 = p.country
JOIN GEO.CLIMATE_ZONES cz ON ST_INTERSECTS(cz.geom, g.geom)  -- Simplified intersection
WHERE p.date >= DATEADD(month, -1, CURRENT_DATE());

-- =====================================================
-- 13. CREATE GEOSPATIAL FUNCTIONS
-- =====================================================

-- Function to get countries within distance of a point
CREATE OR REPLACE FUNCTION GEO.COUNTRIES_WITHIN_DISTANCE(
    lat FLOAT, 
    lon FLOAT, 
    distance_km FLOAT
)
RETURNS TABLE (
    country STRING,
    name STRING,
    distance_km FLOAT
)
LANGUAGE SQL
AS
$$
SELECT 
    iso2,
    name,
    ST_DISTANCE(ST_POINT(lon, lat), centroid_lon, centroid_lat) / 1000 as distance_km
FROM GEO.COUNTRY_GEOM
WHERE ST_DWITHIN(ST_POINT(lon, lat), centroid_lon, centroid_lat, distance_km * 1000)
ORDER BY distance_km;
$$;

-- Function to get risk zones intersecting with a country
CREATE OR REPLACE FUNCTION GEO.RISK_ZONES_FOR_COUNTRY(country_iso STRING)
RETURNS TABLE (
    zone_id STRING,
    zone_name STRING,
    zone_type STRING,
    risk_level STRING
)
LANGUAGE SQL
AS
$$
SELECT 
    rz.zone_id,
    rz.zone_name,
    rz.zone_type,
    rz.risk_level
FROM GEO.RISK_ZONES rz
JOIN GEO.COUNTRY_GEOM cg ON cg.iso2 = country_iso
WHERE ST_INTERSECTS(rz.geom, cg.geom)  -- Simplified intersection
ORDER BY rz.risk_level DESC;
$$;

-- =====================================================
-- 14. CREATE DASHBOARD TILES
-- =====================================================

-- Tile for global risk overview
CREATE OR REPLACE VIEW GEO.GLOBAL_RISK_TILE AS
SELECT 
    CURRENT_DATE() as tile_date,
    COUNT(DISTINCT country) as total_countries,
    COUNT_IF(probability >= 0.80) as critical_countries,
    COUNT_IF(probability >= 0.60) as high_risk_countries,
    COUNT_IF(probability >= 0.40) as medium_risk_countries,
    AVG(risk_score) as global_avg_risk,
    MAX(risk_score) as global_max_risk,
    COUNT_IF(probability >= 0.80) * 100.0 / COUNT(DISTINCT country) as critical_percentage
FROM ML.PREDICTIONS
WHERE date = CURRENT_DATE();

-- Tile for regional breakdown
CREATE OR REPLACE VIEW GEO.REGIONAL_RISK_TILE AS
SELECT 
    CURRENT_DATE() as tile_date,
    g.region,
    COUNT(DISTINCT p.country) as country_count,
    AVG(p.risk_score) as avg_risk,
    MAX(p.risk_score) as max_risk,
    COUNT_IF(p.probability >= 0.80) as critical_count,
    COUNT_IF(p.probability >= 0.60) as high_risk_count
FROM ML.PREDICTIONS p
JOIN GEO.COUNTRY_GEOM g ON g.iso2 = p.country
WHERE p.date = CURRENT_DATE()
GROUP BY g.region;

-- Tile for supply chain risk
CREATE OR REPLACE VIEW GEO.SUPPLY_CHAIN_RISK_TILE AS
SELECT 
    CURRENT_DATE() as tile_date,
    COUNT(DISTINCT sr.route_id) as total_routes,
    COUNT_IF(sr.criticality = 'CRITICAL') as critical_routes,
    COUNT_IF(sr.criticality = 'HIGH') as high_priority_routes,
    AVG(rr.avg_risk_score) as avg_route_risk,
    MAX(rr.max_risk_score) as max_route_risk
FROM GEO.SUPPLY_ROUTES sr
LEFT JOIN GEO.ROUTE_RISK rr ON rr.route_name = sr.route_name AND rr.date = CURRENT_DATE();

-- =====================================================
-- 15. GRANT PERMISSIONS
-- =====================================================

-- Grant permissions to appropriate roles
GRANT USAGE ON SCHEMA GEO TO ROLE OPS_TASK_ROLE;
GRANT USAGE ON SCHEMA GEO TO ROLE OPS_MONITOR_ROLE;
GRANT USAGE ON SCHEMA GEO TO ROLE DASHBOARD_ROLE;
GRANT USAGE ON SCHEMA GEO TO ROLE DATA_SCIENTIST_ROLE;

GRANT SELECT ON ALL TABLES IN SCHEMA GEO TO ROLE OPS_MONITOR_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA GEO TO ROLE DASHBOARD_ROLE;
GRANT SELECT ON ALL TABLES IN SCHEMA GEO TO ROLE DATA_SCIENTIST_ROLE;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA GEO TO ROLE OPS_TASK_ROLE;

-- Grant function permissions
GRANT USAGE ON FUNCTION GEO.COUNTRIES_WITHIN_DISTANCE(FLOAT, FLOAT, FLOAT) TO ROLE DASHBOARD_ROLE;
GRANT USAGE ON FUNCTION GEO.RISK_ZONES_FOR_COUNTRY(STRING) TO ROLE DASHBOARD_ROLE;

-- =====================================================
-- 16. AUDIT LOG
-- =====================================================

INSERT INTO OPS.LOAD_AUDIT (
    execution_id, phase, step, execution_ts, status, rows_affected, execution_time_seconds, error_message
) VALUES (
    'PHASE8_GEO_' || CURRENT_TIMESTAMP()::STRING,
    'PHASE_8',
    'GEO_SETUP',
    CURRENT_TIMESTAMP(),
    'SUCCESS',
    (SELECT COUNT(*) FROM GEO.COUNTRY_GEOM) + (SELECT COUNT(*) FROM GEO.RISK_ZONES),
    0,
    NULL
);

-- Success message
SELECT 'Phase 8: Geospatial setup completed successfully!' AS status;
