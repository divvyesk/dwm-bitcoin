-- =====================================================================
-- Experiment 2 | Step 4 : ETL - populate the dimensions, then the fact
-- Order matters: dimensions must exist before the fact can resolve keys
-- =====================================================================

-- ---------------------------------------------------------------------
-- 4.1 DIM_DATE : generated for every calendar day in the loaded range
--      (generated, not extracted - a date dimension must be gap-free)
-- ---------------------------------------------------------------------
TRUNCATE dim_date CASCADE;

INSERT INTO dim_date (date_key, full_date, day_of_month, month_no, month_name,
                      quarter, year, day_of_week, week_of_year, is_month_end, is_weekend)
SELECT TO_CHAR(d, 'YYYYMMDD')::INT,
       d::DATE,
       EXTRACT(DAY   FROM d)::SMALLINT,
       EXTRACT(MONTH FROM d)::SMALLINT,
       TRIM(TO_CHAR(d, 'Month')),
       EXTRACT(QUARTER FROM d)::SMALLINT,
       EXTRACT(YEAR  FROM d)::SMALLINT,
       TRIM(TO_CHAR(d, 'Day')),
       EXTRACT(WEEK  FROM d)::SMALLINT,
       (d::DATE = (DATE_TRUNC('month', d) + INTERVAL '1 month - 1 day')::DATE),
       EXTRACT(ISODOW FROM d) IN (6, 7)
FROM generate_series(
        (SELECT MIN(date) FROM staging_btc_daily),
        (SELECT MAX(date) FROM staging_btc_daily),
        INTERVAL '1 day') AS d;

-- ---------------------------------------------------------------------
-- 4.2 DIM_ASSET : deduplicated from staging
-- ---------------------------------------------------------------------
TRUNCATE dim_asset RESTART IDENTITY CASCADE;

INSERT INTO dim_asset (ticker, asset_name, asset_type, quote_currency)
SELECT DISTINCT COALESCE(ticker, 'BTC'), 'Bitcoin', 'Cryptocurrency', 'USD'
FROM staging_btc_daily;

-- ---------------------------------------------------------------------
-- 4.3 DIM_HALVING_ERA : one row per era, with its span derived from data
--      and the block reward parsed out of the era name
-- ---------------------------------------------------------------------
TRUNCATE dim_halving_era RESTART IDENTITY CASCADE;

INSERT INTO dim_halving_era (era_name, era_sequence, block_reward_btc,
                             era_start_date, era_end_date, era_days)
SELECT halving_era,
       ROW_NUMBER() OVER (ORDER BY MIN(date))::SMALLINT,
       SUBSTRING(halving_era FROM '([0-9]+\.?[0-9]*) BTC')::NUMERIC,
       MIN(date),
       MAX(date),
       (MAX(date) - MIN(date) + 1)
FROM staging_btc_daily
GROUP BY halving_era;

-- ---------------------------------------------------------------------
-- 4.4 DIM_MARKET_STATE : the full cross product of the three descriptive
--      attributes (3 x 3 x 4 = 36 possible states)
-- ---------------------------------------------------------------------
TRUNCATE dim_market_state RESTART IDENTITY CASCADE;

INSERT INTO dim_market_state (direction, volatility_band, rsi_zone, state_label)
SELECT dir, vol, rsi, dir || ' / ' || vol || ' volatility / ' || rsi
FROM   (VALUES ('Up'), ('Down'), ('Flat'))                                  AS d(dir)
CROSS JOIN (VALUES ('Low'), ('Medium'), ('High'))                           AS v(vol)
CROSS JOIN (VALUES ('Oversold'), ('Neutral'), ('Overbought'), ('Unknown'))  AS r(rsi);

-- ---------------------------------------------------------------------
-- 4.5 FACT_BTC_DAILY : surrogate-key resolution against all 4 dimensions
--      De-duplication rule: if a date appears twice in staging, keep the
--      row with the larger traded range (the more complete record).
-- ---------------------------------------------------------------------
TRUNCATE fact_btc_daily RESTART IDENTITY;

WITH deduped AS (
    SELECT DISTINCT ON (date) *
    FROM   staging_btc_daily
    ORDER  BY date, daily_range DESC NULLS LAST
),
classified AS (
    SELECT s.*,
           CASE WHEN s.daily_pct_change >  0.5 THEN 'Up'
                WHEN s.daily_pct_change < -0.5 THEN 'Down'
                ELSE 'Flat' END                                       AS direction,
           CASE WHEN s.daily_range / NULLIF(s.open,0) * 100 <  3 THEN 'Low'
                WHEN s.daily_range / NULLIF(s.open,0) * 100 <= 8 THEN 'Medium'
                ELSE 'High' END                                       AS volatility_band,
           CASE WHEN s.rsi_14 IS NULL   THEN 'Unknown'
                WHEN s.rsi_14 < 30      THEN 'Oversold'
                WHEN s.rsi_14 > 70      THEN 'Overbought'
                ELSE 'Neutral' END                                    AS rsi_zone
    FROM deduped s
)
INSERT INTO fact_btc_daily (
    date_key, asset_key, era_key, state_key, days_since_halving,
    open_price, high_price, low_price, close_price,
    daily_change, daily_pct_change, daily_range,
    ma_7, ma_30, ma_200, volatility_30d, ema_12, ema_26, macd, macd_signal, rsi_14)
SELECT dd.date_key,
       da.asset_key,
       de.era_key,
       ms.state_key,
       c.days_since_halving,
       c.open, c.high, c.low, c.close,
       c.daily_change, c.daily_pct_change, c.daily_range,
       c.ma_7, c.ma_30, c.ma_200, c.volatility_30d,
       c.ema_12, c.ema_26, c.macd, c.macd_signal, c.rsi_14
FROM   classified c
JOIN   dim_date         dd ON dd.full_date = c.date
JOIN   dim_asset        da ON da.ticker    = COALESCE(c.ticker, 'BTC')
JOIN   dim_halving_era  de ON de.era_name  = c.halving_era
JOIN   dim_market_state ms ON ms.direction       = c.direction
                          AND ms.volatility_band = c.volatility_band
                          AND ms.rsi_zone        = c.rsi_zone;
