-- =====================================================================
-- Experiment 2 | Step 1 : create the data-mart database
-- Run from the psql client:   psql -U postgres -f exp2_01_create_database.sql
-- =====================================================================

DROP DATABASE IF EXISTS btc_dw;

CREATE DATABASE btc_dw
    WITH ENCODING = 'UTF8'
         TEMPLATE = template0;

COMMENT ON DATABASE btc_dw IS
    'Bitcoin daily price data mart - DWM Lab Experiment 2 (star schema)';

-- Connect to the new database before running step 2:
--   \c btc_dw
