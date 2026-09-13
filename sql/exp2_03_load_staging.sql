-- =====================================================================
-- Experiment 2 | Step 3 : load the raw CSV into the staging table
-- =====================================================================

TRUNCATE staging_btc_daily;

-- From the psql client (client-side path, no superuser needed):
--   \copy staging_btc_daily FROM 'btc_flat_final_2.csv' WITH (FORMAT csv, HEADER true, NULL '')
-- From the server (used here, file readable by the server process):
COPY staging_btc_daily
FROM '/tmp/btc_flat_final_2.csv'
WITH (FORMAT csv, HEADER true, NULL '');

-- Load audit
SELECT COUNT(*)                     AS rows_loaded,
       MIN(date)                    AS first_date,
       MAX(date)                    AS last_date,
       COUNT(DISTINCT date)         AS distinct_dates,
       COUNT(*) - COUNT(DISTINCT date) AS duplicate_dates,
       COUNT(*) FILTER (WHERE rsi_14 IS NULL)  AS null_rsi,
       COUNT(*) FILTER (WHERE ma_200 IS NULL)  AS null_ma200
FROM staging_btc_daily;
