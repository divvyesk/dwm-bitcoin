-- =====================================================================
-- Experiment 2 | Step 2 : staging table, dimension tables, fact table
-- Run inside btc_dw:   \c btc_dw    then   \i exp2_02_create_tables.sql
-- =====================================================================

-- Drop in dependency order (fact first, it references the dimensions)
DROP TABLE IF EXISTS fact_btc_daily      CASCADE;
DROP TABLE IF EXISTS dim_date            CASCADE;
DROP TABLE IF EXISTS dim_asset           CASCADE;
DROP TABLE IF EXISTS dim_halving_era     CASCADE;
DROP TABLE IF EXISTS dim_market_state    CASCADE;
DROP TABLE IF EXISTS staging_btc_daily   CASCADE;

-- ---------------------------------------------------------------------
-- 2.1 STAGING LAYER : mirrors the CSV exactly, no constraints, no keys
-- ---------------------------------------------------------------------
CREATE TABLE staging_btc_daily (
    date                DATE,
    ticker              VARCHAR(10),
    halving_era         VARCHAR(40),
    days_since_halving  INTEGER,
    open                NUMERIC(14,4),
    high                NUMERIC(14,4),
    low                 NUMERIC(14,4),
    close               NUMERIC(14,4),
    daily_change        NUMERIC(14,4),
    daily_pct_change    NUMERIC(12,4),
    daily_range         NUMERIC(14,4),
    ma_7                NUMERIC(14,4),
    ma_30               NUMERIC(14,4),
    ma_200              NUMERIC(14,4),
    volatility_30d      NUMERIC(12,4),
    ema_12              NUMERIC(14,4),
    ema_26              NUMERIC(14,4),
    macd                NUMERIC(14,4),
    macd_signal         NUMERIC(14,4),
    rsi_14              NUMERIC(8,4)
);

-- ---------------------------------------------------------------------
-- 2.2 DIMENSION TABLES (star schema - denormalised, surrogate keys)
-- ---------------------------------------------------------------------
CREATE TABLE dim_date (
    date_key        INTEGER      PRIMARY KEY,          -- yyyymmdd smart key
    full_date       DATE         NOT NULL UNIQUE,
    day_of_month    SMALLINT     NOT NULL,
    month_no        SMALLINT     NOT NULL,
    month_name      VARCHAR(12)  NOT NULL,
    quarter         SMALLINT     NOT NULL,
    year            SMALLINT     NOT NULL,
    day_of_week     VARCHAR(10)  NOT NULL,
    week_of_year    SMALLINT     NOT NULL,
    is_month_end    BOOLEAN      NOT NULL,
    is_weekend      BOOLEAN      NOT NULL
);

CREATE TABLE dim_asset (
    asset_key       SERIAL       PRIMARY KEY,
    ticker          VARCHAR(10)  NOT NULL UNIQUE,
    asset_name      VARCHAR(40)  NOT NULL,
    asset_type      VARCHAR(30)  NOT NULL,
    quote_currency  VARCHAR(10)  NOT NULL
);

CREATE TABLE dim_halving_era (
    era_key          SERIAL        PRIMARY KEY,
    era_name         VARCHAR(40)   NOT NULL UNIQUE,
    era_sequence     SMALLINT      NOT NULL,
    block_reward_btc NUMERIC(8,4)  NOT NULL,
    era_start_date   DATE          NOT NULL,
    era_end_date     DATE          NOT NULL,
    era_days         INTEGER       NOT NULL
);

CREATE TABLE dim_market_state (
    state_key        SERIAL       PRIMARY KEY,
    direction        VARCHAR(10)  NOT NULL,   -- Up / Down / Flat
    volatility_band  VARCHAR(10)  NOT NULL,   -- Low / Medium / High
    rsi_zone         VARCHAR(12)  NOT NULL,   -- Oversold / Neutral / Overbought / Unknown
    state_label      VARCHAR(60)  NOT NULL,
    CONSTRAINT uq_market_state UNIQUE (direction, volatility_band, rsi_zone),
    CONSTRAINT chk_direction  CHECK (direction  IN ('Up','Down','Flat')),
    CONSTRAINT chk_vol_band   CHECK (volatility_band IN ('Low','Medium','High')),
    CONSTRAINT chk_rsi_zone   CHECK (rsi_zone  IN ('Oversold','Neutral','Overbought','Unknown'))
);

-- ---------------------------------------------------------------------
-- 2.3 FACT TABLE : grain = one asset on one calendar day
-- ---------------------------------------------------------------------
CREATE TABLE fact_btc_daily (
    fact_key            BIGSERIAL     PRIMARY KEY,
    date_key            INTEGER       NOT NULL REFERENCES dim_date(date_key),
    asset_key           INTEGER       NOT NULL REFERENCES dim_asset(asset_key),
    era_key             INTEGER       NOT NULL REFERENCES dim_halving_era(era_key),
    state_key           INTEGER       NOT NULL REFERENCES dim_market_state(state_key),
    days_since_halving  INTEGER       NOT NULL,     -- degenerate dimension
    open_price          NUMERIC(14,4) NOT NULL,
    high_price          NUMERIC(14,4),
    low_price           NUMERIC(14,4) NOT NULL,
    close_price         NUMERIC(14,4) NOT NULL,
    daily_change        NUMERIC(14,4) NOT NULL,
    daily_pct_change    NUMERIC(12,4) NOT NULL,
    daily_range         NUMERIC(14,4) NOT NULL,
    ma_7                NUMERIC(14,4),
    ma_30               NUMERIC(14,4),
    ma_200              NUMERIC(14,4),
    volatility_30d      NUMERIC(12,4),
    ema_12              NUMERIC(14,4),
    ema_26              NUMERIC(14,4),
    macd                NUMERIC(14,4),
    macd_signal         NUMERIC(14,4),
    rsi_14              NUMERIC(8,4),
    CONSTRAINT uq_fact_grain UNIQUE (date_key, asset_key),      -- enforces the grain
    CONSTRAINT chk_prices_positive CHECK (open_price > 0 AND close_price > 0 AND low_price > 0)
);

-- Indexes on the foreign keys - the join paths OLAP queries use
CREATE INDEX idx_fact_date_key  ON fact_btc_daily(date_key);
CREATE INDEX idx_fact_era_key   ON fact_btc_daily(era_key);
CREATE INDEX idx_fact_state_key ON fact_btc_daily(state_key);
CREATE INDEX idx_dim_date_year  ON dim_date(year, month_no);
