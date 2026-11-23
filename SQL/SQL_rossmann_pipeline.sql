/* ============================================================================
   PROJECT: Rossmann Store Sales — Retail Analytics Pipeline
   DATABASE: MySQL 8.0
   AUTHOR: Oleksandr Muntian
   DESCRIPTION: 
     End-to-end SQL script covering database setup, CSV ingestion with NULL 
     handling, retail KPI analysis (Promo Lift, Store Formats, Competition, 
     MoM Seasonality), and BI views preparation.
============================================================================ */

-- ============================================================================
-- PART 1: DATABASE SETUP & DATA INGESTION
-- ============================================================================

CREATE DATABASE IF NOT EXISTS rossmann_db;
USE rossmann_db;

SET GLOBAL local_infile = 1;

-- 1.1 Store master data table
DROP TABLE IF EXISTS store;
CREATE TABLE store (
    Store INT PRIMARY KEY,
    StoreType VARCHAR(5),
    Assortment VARCHAR(5),
    CompetitionDistance INT,
    CompetitionOpenSinceMonth INT,
    CompetitionOpenSinceYear INT,
    Promo2 INT,
    Promo2SinceWeek INT,
    Promo2SinceYear INT,
    PromoInterval VARCHAR(30)
);

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/store.csv'
INTO TABLE store
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(
    Store, 
    StoreType, 
    Assortment, 
    @comp_dist, 
    @comp_month, 
    @comp_year, 
    Promo2, 
    @promo2_week, 
    @promo2_year, 
    @promo_interval
)
SET 
    CompetitionDistance = NULLIF(@comp_dist, ''),
    CompetitionOpenSinceMonth = NULLIF(@comp_month, ''),
    CompetitionOpenSinceYear = NULLIF(@comp_year, ''),
    Promo2SinceWeek = NULLIF(@promo2_week, ''),
    Promo2SinceYear = NULLIF(@promo2_year, ''),
    PromoInterval = NULLIF(TRIM(TRAILING '\r' FROM @promo_interval), '');

-- 1.2 Historical daily sales table (Train)
DROP TABLE IF EXISTS train;
CREATE TABLE train (
    Store INT,
    DayOfWeek INT,
    Date DATE,
    Sales INT,
    Customers INT,
    Open INT,
    Promo INT,
    StateHoliday VARCHAR(10),
    SchoolHoliday INT
);
LOAD DATA INFILE 'C:/Programdata/MySQL/MySQL Server 8.0/uploads/train.csv'
INTO TABLE train
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- 1.3 Test dataset table (Future period without Sales)
DROP TABLE IF EXISTS test;
CREATE TABLE test (
    Id INT,
    Store INT,
    DayOfWeek INT,
    Date DATE,
    Open INT,
    Promo INT,
    StateHoliday VARCHAR(10),
    SchoolHoliday INT
);

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/test.csv'
INTO TABLE test
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(Id, Store, DayOfWeek, Date, @open, Promo, StateHoliday, SchoolHoliday)
SET Open = NULLIF(@open, '');

SET GLOBAL local_infile = 0;

SELECT * FROM store LIMIT 10;
SELECT * FROM train LIMIT 10;
SELECT * FROM test LIMIT 10;


-- ============================================================================
-- PART 2: BUSINESS KPI ANALYSIS (AD-HOC QUERIES)
-- Note: Closed store days (Open = 0 or Sales = 0) are excluded to avoid 
-- downward bias in daily averages.
-- ============================================================================

/* ----------------------------------------------------------------------------
   2.1 Promo & Promo2 Effectiveness (Promo Lift)
   Business Question: How strongly do short-term promotions (Promo) and 
   continuous coupon campaigns (Promo2) drive daily revenue, customer traffic, 
   and average basket size?
   Key Finding: [TODO: Add your exact % lift after running the query]
---------------------------------------------------------------------------- */
SELECT 
    t.Promo,
    s.Promo2,
    COUNT(*) AS active_store_days,
    ROUND(AVG(t.Sales), 2) AS avg_daily_sales,
    ROUND(AVG(t.Customers), 0) AS avg_daily_customers,
    ROUND(SUM(t.Sales) / SUM(t.Customers), 2) AS avg_basket_size
FROM train AS t
JOIN store AS s ON t.Store = s.Store
WHERE t.Open = 1 AND t.Sales > 0
GROUP BY t.Promo, s.Promo2
ORDER BY t.Promo DESC, s.Promo2 DESC;
/* ----------------------------------------------------------------------------
Query Output Snapshot:
   Promo | Promo2 | active_store_days | avg_daily_sales | avg_daily_customers | avg_basket_size
   ------+--------+-------------------+-----------------+---------------------+----------------
     1   |   1    |            187870 |         7836.67 |                 760 |           10.31
     1   |   0    |            189005 |         8618.45 |                 929 |            9.28
     0   |   1    |            233176 |         5529.57 |                 618 |            8.94
     0   |   0    |            234287 |         6328.19 |                 775 |            8.16

   Key Finding: Short-term promotions (Promo=1) boost average daily sales by 
   +36.2% (from 6,328 to 8,618 without Promo2) and +41.7% (from 5,530 to 7,837 
   with Promo2), driven by both higher foot traffic (+20-23%) and larger basket 
   size (+14-15%). Promo2=1 stores show lower overall daily sales due to lower 
   baseline customer traffic (selection bias toward slower stores), yet achieve 
   the highest average basket size (10.31 vs 9.28).
---------------------------------------------------------------------------- */



/* ----------------------------------------------------------------------------
   2.2 Store Format & Assortment Performance
   Business Question: Which combinations of StoreType (a, b, c, d) and 
   Assortment (a = basic, b = extra, c = extended) generate the highest revenue 
   share and per-store efficiency?
   Key Finding: [TODO: Add top-performing format and revenue share %]
---------------------------------------------------------------------------- */
SELECT 
    s.StoreType,
    s.Assortment,
    COUNT(DISTINCT s.Store) AS stores_count,
    ROUND(SUM(t.Sales) / 1000000, 2) AS total_sales_mln,
    ROUND(SUM(t.Sales) * 100.0 / SUM(SUM(t.Sales)) OVER (), 2) AS share_of_total_sales_pct,
    ROUND(AVG(t.Sales), 2) AS avg_daily_sales_per_store,
    ROUND(SUM(t.Sales) / SUM(t.Customers), 2) AS avg_basket_size
FROM train AS t
JOIN store AS s ON t.Store = s.Store
WHERE t.Open = 1 AND t.Sales > 0
GROUP BY s.StoreType, s.Assortment
ORDER BY total_sales_mln DESC;
/* ----------------------------------------------------------------------------
Query Output Snapshot:
   StoreType | Assortment | stores_count | total_sales_mln | share_of_total_sales_pct | avg_daily_sales_per_store | avg_basket_size
   ----------+------------+--------------+-----------------+--------------------------+---------------------------+----------------
   a         | a          |          381 |         1870.11 |                    31.84 |                   6538.19 |            8.61
   a         | c          |          221 |         1295.23 |                    22.05 |                   7573.82 |            8.85
   d         | c          |          220 |         1161.37 |                    19.77 |                   7043.53 |           11.38
   d         | a          |          128 |          604.03 |                    10.28 |                   6433.76 |           11.02
   c         | a          |           77 |          400.26 |                     6.82 |                   6835.75 |            8.14
   c         | c          |           71 |          382.96 |                     6.52 |                   7037.91 |            8.92
   b         | a          |            7 |           71.36 |                     1.21 |                  11133.99 |            6.17
   b         | b          |            9 |           70.95 |                     1.21 |                   8642.50 |            4.18
   b         | c          |            1 |           16.93 |                     0.29 |                  17969.56 |            5.79

   Key Finding: StoreType 'a' drives the bulk of total revenue (53.89% 
   combined across assortments 'a' and 'c'), while StoreType 'd' delivers the 
   highest average basket size (11.02-11.38). StoreType 'b' represents a 
   small niche (17 stores) with high daily sales per store (up to 17,969.56) 
   and smaller baskets (4.18-6.17). Across StoreTypes 'a', 'c', and 'd', 
   extended assortment ('c') consistently yields higher daily revenue per 
   store than basic assortment ('a').
---------------------------------------------------------------------------- */



/* ----------------------------------------------------------------------------
   2.3 Competition Proximity Impact
   Business Question: Does proximity to the nearest competitor cannibalize 
   store sales, or do high-density urban locations offset competition?
   Key Finding: [TODO: Add comparison between <500m and >5km zones]
---------------------------------------------------------------------------- */
SELECT 
    CASE 
        WHEN s.CompetitionDistance IS NULL THEN '0. Unknown'
        WHEN s.CompetitionDistance <= 500 THEN '1. Up to 500m (Very Close)'
        WHEN s.CompetitionDistance <= 2000 THEN '2. 500m - 2km (Close)'
        WHEN s.CompetitionDistance <= 5000 THEN '3. 2km - 5km (Moderate)'
        ELSE '4. Over 5km (Far)'
    END AS competition_zone,
    COUNT(DISTINCT s.Store) AS stores_count,
    ROUND(AVG(t.Sales), 2) AS avg_daily_sales,
    ROUND(AVG(t.Customers), 0) AS avg_daily_customers,
    ROUND(SUM(t.Sales) / SUM(t.Customers), 2) AS avg_basket_size
FROM train AS t
JOIN store AS s ON t.Store = s.Store
WHERE t.Open = 1 AND t.Sales > 0
GROUP BY competition_zone
ORDER BY competition_zone;
/* ----------------------------------------------------------------------------
Query Output Snapshot:
   competition_zone             | stores_count | avg_daily_sales | avg_daily_customers | avg_basket_size
   -----------------------------+--------------+-----------------+---------------------+----------------
   0. Unknown                   |            3 |         5482.08 |                 553 |            9.92
   1. Up to 500m (Very Close)   |          220 |         7610.89 |                 969 |            7.86
   2. 500m - 2km (Close)        |          282 |         6920.35 |                 813 |            8.51
   3. 2km - 5km (Moderate)      |          261 |         6678.54 |                 692 |            9.65
   4. Over 5km (Far)            |          349 |         6787.07 |                 646 |           10.50

   Key Finding: Stores within 500m of a competitor generate the highest average 
   daily sales (7,610.89) and foot traffic (969 customers/day), indicating 
   competitors cluster in high-traffic commercial locations rather than 
   cannibalizing baseline demand. Conversely, average basket size increases 
   steadily with distance—from 7.86 (<=500m) to 10.50 (>5km, +33.6%)—pointing 
   to more consolidated trips in less dense or more remote areas.
---------------------------------------------------------------------------- */



/* ----------------------------------------------------------------------------
   2.4 Monthly Revenue Trend & Month-over-Month (MoM) Growth
   Business Question: What are the seasonal peaks across the year, and how 
   does monthly revenue per active store fluctuate over time?
   Key Finding: [TODO: Highlight December peak and MoM growth]
---------------------------------------------------------------------------- */
WITH monthly_sales AS (
    SELECT 
        DATE_FORMAT(Date, '%Y-%m-01') AS sales_month,
        SUM(Sales) AS total_sales,
        SUM(Customers) AS total_customers,
        COUNT(DISTINCT Store) AS active_stores
    FROM train
    WHERE Open = 1 AND Sales > 0
    GROUP BY DATE_FORMAT(Date, '%Y-%m-01')
)
SELECT 
    sales_month,
    ROUND(total_sales / 1000000, 2) AS sales_mln,
    ROUND(total_sales / active_stores, 0) AS avg_sales_per_store,
    ROUND(
        (total_sales - LAG(total_sales) OVER (ORDER BY sales_month)) 
        * 100.0 / LAG(total_sales) OVER (ORDER BY sales_month), 
    2) AS mom_growth_pct
FROM monthly_sales
ORDER BY sales_month;
/* ----------------------------------------------------------------------------
 Key Rows Snapshot (Jan 2013 - Jul 2015, 31 months total; avg 189.46M/mo):
   sales_month | sales_mln | avg_sales_per_store | mom_growth_pct
   ------------+-----------+---------------------+---------------
   2013-01-01  |    180.13 |              161989 |           NULL
   2013-03-01  |    201.18 |              180918 |          17.28
   2013-07-01  |    208.84 |              187304 |          15.57
   2013-12-01  |    231.71 |              207812 |          18.12
   2014-01-01  |    187.75 |              168388 |         -18.97
   2014-08-01  |    163.75 |              175320 |          -5.83
   2014-12-01  |    202.12 |              216172 |          16.61
   2015-07-01  |    212.32 |              190424 |           2.39

   Key Finding: Sales peak strongly in December (231.71M total in Dec 2013, 
   +18.12% MoM; highest per-store monthly average of 216,172 in Dec 2014, 
   +16.61% MoM), followed by sharp post-holiday drops in January (-18.97% MoM 
   in Jan 2014). March and summer months show recurring upswings, while total 
   monthly sales dipped to 163.75M in Aug 2014; diverging total vs. per-store 
   trends in Jul 2014 warrant a check on active store counts in Python.
 ---------------------------------------------------------------------------- */



-- ============================================================================
-- PART 3: ANALYTICAL VIEWS FOR BI DASHBOARDS (Power BI / Tableau)
-- ============================================================================

CREATE OR REPLACE VIEW v_sales_enriched AS
SELECT 
    t.Date,
    YEAR(t.Date) AS SalesYear,
    MONTH(t.Date) AS SalesMonth,
    t.DayOfWeek,
    t.Store,
    s.StoreType,
    s.Assortment,
    s.CompetitionDistance,
    t.Open,
    t.Promo,
    s.Promo2,
    t.StateHoliday,
    t.SchoolHoliday,
    t.Sales,
    t.Customers,
    CASE 
        WHEN t.Customers > 0 THEN ROUND(t.Sales / t.Customers, 2) 
        ELSE 0 
    END AS AvgBasketSize
FROM train AS t
JOIN store s ON t.Store = s.Store;

SELECT *
FROM v_sales_enriched;