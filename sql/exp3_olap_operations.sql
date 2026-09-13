-- =====================================================================
-- Experiment 3 | OLAP operations on the Bitcoin star schema (btc_dw)
--   Roll-up, Drill-down, Slice, Dice, Pivot (+ CUBE and GROUPING SETS)
-- Run:  psql -d btc_dw -f exp3_olap_operations.sql
-- =====================================================================

\echo '================ 1. ROLL-UP : day -> month -> quarter -> year ================'
-- Roll-up climbs the DIM_DATE hierarchy, summarising the daily facts to
-- a coarser level. Here: yearly summary of the daily facts.
SELECT d.year,
       COUNT(*)                                AS trading_days,
       ROUND(AVG(f.close_price), 2)            AS avg_close,
       ROUND(MIN(f.low_price), 2)              AS year_low,
       ROUND(MAX(f.high_price), 2)             AS year_high,
       ROUND(AVG(ABS(f.daily_pct_change)), 3)  AS avg_abs_move_pct
FROM   fact_btc_daily f
JOIN   dim_date d ON d.date_key = f.date_key
WHERE  d.year BETWEEN 2021 AND 2026
GROUP  BY d.year
ORDER  BY d.year;

\echo ''
\echo '---- 1b. ROLL-UP with the ROLLUP operator (year -> quarter -> grand total) ----'
SELECT COALESCE(d.year::TEXT, 'ALL YEARS')      AS year,
       COALESCE(d.quarter::TEXT, 'ALL Q')       AS quarter,
       COUNT(*)                                 AS days,
       ROUND(AVG(f.close_price), 2)             AS avg_close
FROM   fact_btc_daily f
JOIN   dim_date d ON d.date_key = f.date_key
WHERE  d.year BETWEEN 2024 AND 2025
GROUP  BY ROLLUP (d.year, d.quarter)
ORDER  BY d.year NULLS LAST, d.quarter NULLS LAST;

\echo ''
\echo '================ 2. DRILL-DOWN : era -> year -> quarter -> month ================'
-- Drill-down is the reverse of roll-up: the same measure shown at a finer
-- level of the hierarchy. Starting point (coarse) - by halving era:
SELECT e.era_name, COUNT(*) AS days, ROUND(AVG(f.close_price), 2) AS avg_close
FROM   fact_btc_daily f
JOIN   dim_halving_era e ON e.era_key = f.era_key
GROUP  BY e.era_sequence, e.era_name
ORDER  BY e.era_sequence;

\echo ''
\echo '---- 2b. drill down into Post-Halving 4, by month ----'
SELECT d.year, d.month_no, d.month_name,
       COUNT(*)                          AS days,
       ROUND(AVG(f.close_price), 2)      AS avg_close,
       ROUND(SUM(f.daily_change), 2)     AS net_change_usd
FROM   fact_btc_daily f
JOIN   dim_date d        ON d.date_key = f.date_key
JOIN   dim_halving_era e ON e.era_key  = f.era_key
WHERE  e.era_name = 'Post-Halving 4 (3.125 BTC/block)'
GROUP  BY d.year, d.month_no, d.month_name
ORDER  BY d.year, d.month_no
LIMIT  12;

\echo ''
\echo '================ 3. SLICE : fix ONE dimension to a single value ================'
-- Slice = a sub-cube obtained by fixing one dimension. Here the market-state
-- dimension is fixed to direction = ''Down'', and the remaining dimensions
-- (time) stay free.
SELECT d.year,
       COUNT(*)                                 AS down_days,
       ROUND(AVG(f.daily_pct_change), 3)        AS avg_down_move_pct,
       ROUND(MIN(f.daily_pct_change), 2)        AS worst_day_pct
FROM   fact_btc_daily f
JOIN   dim_date d         ON d.date_key  = f.date_key
JOIN   dim_market_state m ON m.state_key = f.state_key
WHERE  m.direction = 'Down'                      -- <== the slice
GROUP  BY d.year
ORDER  BY d.year;

\echo ''
\echo '================ 4. DICE : restrict SEVERAL dimensions at once ================'
-- Dice = a sub-cube obtained by selecting ranges/values on two or more
-- dimensions: time 2020-2022, high volatility, and an upward move.
SELECT d.full_date, e.era_name, m.volatility_band, m.rsi_zone,
       ROUND(f.daily_pct_change, 2)                          AS pct_change,
       ROUND(f.daily_range / f.open_price * 100, 2)          AS range_pct,
       ROUND(f.close_price, 2)                               AS close_price
FROM   fact_btc_daily f
JOIN   dim_date d         ON d.date_key  = f.date_key
JOIN   dim_halving_era e  ON e.era_key   = f.era_key
JOIN   dim_market_state m ON m.state_key = f.state_key
WHERE  d.year BETWEEN 2020 AND 2022                 -- dimension 1: time
  AND  m.volatility_band = 'High'                   -- dimension 2: market state
  AND  m.direction       = 'Up'                     -- dimension 2 (2nd attribute)
ORDER  BY f.daily_pct_change DESC
LIMIT  10;

\echo ''
\echo '================ 5. PIVOT (rotate) : year x direction cross-tab ================'
-- Pivot rotates the cube so that the values of one dimension become columns.
-- FILTER is the standard-SQL way to do this in PostgreSQL.
SELECT d.year,
       COUNT(*) FILTER (WHERE m.direction = 'Up')    AS up_days,
       COUNT(*) FILTER (WHERE m.direction = 'Flat')  AS flat_days,
       COUNT(*) FILTER (WHERE m.direction = 'Down')  AS down_days,
       COUNT(*)                                      AS total_days,
       ROUND(100.0 * COUNT(*) FILTER (WHERE m.direction = 'Up') / COUNT(*), 1) AS pct_up
FROM   fact_btc_daily f
JOIN   dim_date d         ON d.date_key  = f.date_key
JOIN   dim_market_state m ON m.state_key = f.state_key
WHERE  d.year >= 2019
GROUP  BY d.year
ORDER  BY d.year;

\echo ''
\echo '---- 5b. PIVOT : halving era x volatility band (average absolute move %) ----'
SELECT e.era_name,
       ROUND(AVG(ABS(f.daily_pct_change)) FILTER (WHERE m.volatility_band = 'Low'), 2)    AS low_vol,
       ROUND(AVG(ABS(f.daily_pct_change)) FILTER (WHERE m.volatility_band = 'Medium'), 2) AS medium_vol,
       ROUND(AVG(ABS(f.daily_pct_change)) FILTER (WHERE m.volatility_band = 'High'), 2)   AS high_vol,
       COUNT(*) FILTER (WHERE m.volatility_band = 'High') AS high_vol_days
FROM   fact_btc_daily f
JOIN   dim_halving_era e  ON e.era_key   = f.era_key
JOIN   dim_market_state m ON m.state_key = f.state_key
GROUP  BY e.era_sequence, e.era_name
ORDER  BY e.era_sequence;

\echo ''
\echo '================ 6. CUBE : all aggregation combinations ================'
-- CUBE produces every combination of the grouping columns, i.e. the full
-- multidimensional cube of (era x direction) including both margins.
SELECT COALESCE(e.era_name, 'ALL ERAS')   AS era,
       COALESCE(m.direction, 'ALL')       AS direction,
       COUNT(*)                           AS days,
       ROUND(AVG(f.daily_pct_change), 3)  AS avg_pct_change
FROM   fact_btc_daily f
JOIN   dim_halving_era e  ON e.era_key   = f.era_key
JOIN   dim_market_state m ON m.state_key = f.state_key
WHERE  e.era_sequence >= 4
GROUP  BY CUBE (e.era_name, m.direction)
ORDER  BY era, direction;
