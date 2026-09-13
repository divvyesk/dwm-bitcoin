-- =====================================================================
-- Experiment 2 | Step 5 : verification of the loaded star schema
-- =====================================================================

\echo '--- 5.1 Row counts in every table ---'
SELECT 'staging_btc_daily' AS table_name, COUNT(*) AS rows FROM staging_btc_daily
UNION ALL SELECT 'dim_date',          COUNT(*) FROM dim_date
UNION ALL SELECT 'dim_asset',         COUNT(*) FROM dim_asset
UNION ALL SELECT 'dim_halving_era',   COUNT(*) FROM dim_halving_era
UNION ALL SELECT 'dim_market_state',  COUNT(*) FROM dim_market_state
UNION ALL SELECT 'fact_btc_daily',    COUNT(*) FROM fact_btc_daily
ORDER BY 1;

\echo ''
\echo '--- 5.2 DIM_HALVING_ERA contents ---'
SELECT era_key, era_name, block_reward_btc, era_start_date, era_end_date, era_days
FROM dim_halving_era ORDER BY era_sequence;

\echo ''
\echo '--- 5.3 Referential integrity: orphan fact rows (must all be 0) ---'
SELECT (SELECT COUNT(*) FROM fact_btc_daily f LEFT JOIN dim_date         d ON f.date_key  = d.date_key  WHERE d.date_key  IS NULL) AS orphan_date,
       (SELECT COUNT(*) FROM fact_btc_daily f LEFT JOIN dim_asset        a ON f.asset_key = a.asset_key WHERE a.asset_key IS NULL) AS orphan_asset,
       (SELECT COUNT(*) FROM fact_btc_daily f LEFT JOIN dim_halving_era  e ON f.era_key   = e.era_key   WHERE e.era_key   IS NULL) AS orphan_era,
       (SELECT COUNT(*) FROM fact_btc_daily f LEFT JOIN dim_market_state m ON f.state_key = m.state_key WHERE m.state_key IS NULL) AS orphan_state;

\echo ''
\echo '--- 5.4 Grain check: no duplicate (date, asset) pairs ---'
SELECT COUNT(*) AS duplicate_grain_rows
FROM (SELECT date_key, asset_key FROM fact_btc_daily
      GROUP BY date_key, asset_key HAVING COUNT(*) > 1) t;

\echo ''
\echo '--- 5.5 Sample of the joined star (first 8 trading days of 2024) ---'
SELECT d.full_date, e.era_name, m.direction, m.volatility_band, m.rsi_zone,
       f.open_price, f.close_price, ROUND(f.daily_pct_change, 2) AS pct_change
FROM   fact_btc_daily f
JOIN   dim_date d         ON d.date_key  = f.date_key
JOIN   dim_halving_era e  ON e.era_key   = f.era_key
JOIN   dim_market_state m ON m.state_key = f.state_key
WHERE  d.year = 2024
ORDER  BY d.full_date
LIMIT  8;

\echo ''
\echo '--- 5.6 Business check: average close price per halving era ---'
SELECT e.era_name,
       COUNT(*)                                   AS trading_days,
       ROUND(AVG(f.close_price), 2)               AS avg_close,
       ROUND(MAX(f.high_price), 2)                AS era_high,
       ROUND(AVG(ABS(f.daily_pct_change)), 3)     AS avg_abs_move_pct
FROM   fact_btc_daily f
JOIN   dim_halving_era e ON e.era_key = f.era_key
GROUP  BY e.era_sequence, e.era_name
ORDER  BY e.era_sequence;

\echo ''
\echo '--- 5.7 Dates present in the date dimension but with no trading row ---'
SELECT COUNT(*) AS calendar_days_without_fact
FROM   dim_date d
LEFT   JOIN fact_btc_daily f ON f.date_key = d.date_key
WHERE  f.fact_key IS NULL;
