"""
Experiment 4 - Part A : Data cleaning
=====================================
Reviewed and corrected version of data_cleaning.py.

Fixes applied to the original script (see the running document for the review):
  1. Duplicate dates are removed BEFORE reindexing. The original crashed with
     "ValueError: cannot reindex on an axis with duplicate labels" when run
     against btc_flat_final_2.csv, which contains a duplicate date (2010-08-02).
  2. days_since_halving is preserved from the source and only recomputed for the
     rows that were inserted to fill gaps. The original replaced the column with
     groupby(...).cumcount(), which restarted the Genesis-era counter at 0 and
     changed the value on 666 rows.
  3. Interpolated (synthetic) rows are flagged with is_interpolated so that later
     experiments can tell a filled day from a traded one.
  4. The indicator burn-in is removed by position (the first N rows), not by the
     total null count of ma_200, which happened to work only because every null
     was at the head of the frame.
  5. OHLC consistency is re-validated AFTER interpolation, since the four price
     columns are interpolated independently and could in principle cross.
"""

import pandas as pd
import numpy as np

RAW_PATH   = "btc_flat_final_2.csv"
CLEAN_PATH = "btc_cleaned_v2.csv"
MA_LONG    = 200          # longest rolling window -> length of the burn-in period

pd.set_option("display.width", 140)
pd.set_option("display.max_columns", 25)

# =====================================================================
# STEP 1 : load and profile the raw data
# =====================================================================
df = pd.read_csv(RAW_PATH)
df["date"] = pd.to_datetime(df["date"])

print("=" * 70)
print("BEFORE CLEANING")
print("=" * 70)
print("Shape:", df.shape)
print("\nNull counts (non-zero only):")
print(df.isnull().sum()[lambda s: s > 0].to_string() or "  none")
print("\nFully duplicated rows :", int(df.duplicated().sum()))
print("Duplicated dates      :", int(df["date"].duplicated().sum()))
if df["date"].duplicated().any():
    dupes = df.loc[df["date"].duplicated(keep=False), "date"].dt.strftime("%Y-%m-%d").unique()
    print("  duplicated date(s)  :", ", ".join(dupes))
print("Sorted ascending      :", df["date"].is_monotonic_increasing)

full_range = pd.date_range(df["date"].min(), df["date"].max(), freq="D")
missing_dates = full_range.difference(df["date"])
print("Missing calendar days :", len(missing_dates))
print("  ", missing_dates.strftime("%Y-%m-%d").tolist()[:8], "..." if len(missing_dates) > 8 else "")

bad_high = df[(df["high"] < df["open"]) | (df["high"] < df["close"]) | (df["high"] < df["low"])]
bad_low  = df[(df["low"]  > df["open"]) | (df["low"]  > df["close"]) | (df["low"]  > df["high"])]
non_pos  = df[(df[["open", "high", "low", "close"]] <= 0).any(axis=1)]
print("High-rule violations  :", len(bad_high))
print("Low-rule violations   :", len(bad_low))
print("Non-positive prices   :", len(non_pos))

# =====================================================================
# STEP 2 : remove duplicate dates  (FIX 1 - must happen before reindex)
# =====================================================================
before = len(df)
df = (df.sort_values(["date", "daily_range"], ascending=[True, False])
        .drop_duplicates(subset="date", keep="first")
        .sort_values("date")
        .reset_index(drop=True))
print(f"\nDuplicate dates removed: {before - len(df)}  (kept the row with the wider traded range)")

# =====================================================================
# STEP 3 : fill the calendar gaps
# =====================================================================
df = df.set_index("date").reindex(full_range)
df.index.name = "date"

df["is_interpolated"] = df["close"].isna()          # FIX 3 - flag synthetic rows
df["ticker"]      = df["ticker"].ffill().bfill()
df["halving_era"] = df["halving_era"].ffill().bfill()

# Bitcoin trades continuously, so a straight-line bridge between the last known
# price before a gap and the first known price after it is the simplest
# defensible estimate in the absence of the real historical quotes.
for col in ["open", "high", "low", "close"]:
    df[col] = df[col].interpolate(method="linear")

# FIX 2 - keep the source counter; only fill it for the inserted rows
df["days_since_halving"] = df["days_since_halving"].interpolate(method="linear").round().astype("Int64")

# FIX 5 - the four price columns were interpolated independently, so re-check
inconsistent = df[(df["high"] < df[["open", "close", "low"]].max(axis=1)) |
                  (df["low"]  > df[["open", "close", "high"]].min(axis=1))]
print(f"OHLC inconsistencies introduced by interpolation: {len(inconsistent)}")
if len(inconsistent):                                # repair rather than drop
    df["high"] = df[["open", "high", "low", "close"]].max(axis=1)
    df["low"]  = df[["open", "high", "low", "close"]].min(axis=1)
    print("  -> repaired by setting high = max(OHLC) and low = min(OHLC)")

# =====================================================================
# STEP 4 : recompute every derived column from the repaired prices
# =====================================================================
df["daily_change"]     = df["close"] - df["open"]
df["daily_pct_change"] = (df["close"] - df["open"]) / df["open"] * 100
df["daily_range"]      = df["high"] - df["low"]

df["ma_7"]           = df["close"].rolling(7).mean()
df["ma_30"]          = df["close"].rolling(30).mean()
df["ma_200"]         = df["close"].rolling(MA_LONG).mean()
df["volatility_30d"] = df["daily_pct_change"].rolling(30).std()

df["ema_12"]      = df["close"].ewm(span=12, adjust=False).mean()
df["ema_26"]      = df["close"].ewm(span=26, adjust=False).mean()
df["macd"]        = df["ema_12"] - df["ema_26"]
df["macd_signal"] = df["macd"].ewm(span=9, adjust=False).mean()

# Wilder's RSI: exponential averages of gains and losses with alpha = 1/14
delta    = df["close"].diff()
gain     = delta.clip(lower=0)
loss     = -delta.clip(upper=0)
avg_gain = gain.ewm(alpha=1 / 14, adjust=False).mean()
avg_loss = loss.ewm(alpha=1 / 14, adjust=False).mean()
df["rsi_14"] = 100 - (100 / (1 + avg_gain / avg_loss))

# =====================================================================
# STEP 5 : drop the indicator burn-in period  (FIX 4 - by position)
# =====================================================================
burn_in = MA_LONG - 1
df = df.iloc[burn_in:].copy().reset_index()
print(f"\nBurn-in rows dropped   : {burn_in} (the first {MA_LONG - 1} rows have no {MA_LONG}-day MA)")

# =====================================================================
# STEP 6 : profile the cleaned data and save
# =====================================================================
print("\n" + "=" * 70)
print("AFTER CLEANING")
print("=" * 70)
print("Shape:", df.shape)
print("\nNull counts (non-zero only):")
print(df.isnull().sum()[lambda s: s > 0].to_string() or "  none")
print("\nDuplicated dates      :", int(df["date"].duplicated().sum()))
after_range = pd.date_range(df["date"].min(), df["date"].max(), freq="D")
print("Remaining gaps        :", len(after_range.difference(df["date"])))
bad_h = df[(df["high"] < df[["open", "close", "low"]].max(axis=1))]
bad_l = df[(df["low"]  > df[["open", "close", "high"]].min(axis=1))]
print("OHLC violations       :", len(bad_h) + len(bad_l))
print("Interpolated rows kept:", int(df["is_interpolated"].sum()))
print("Date range            :", df["date"].min().date(), "to", df["date"].max().date())
print("\n", df[["date", "close", "daily_pct_change", "ma_200", "rsi_14", "is_interpolated"]].head())

df.to_csv(CLEAN_PATH, index=False)
print(f"\nSaved cleaned dataset to {CLEAN_PATH}  ({len(df)} rows, {df.shape[1]} columns)")
