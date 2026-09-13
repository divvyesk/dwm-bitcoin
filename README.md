# DWM Lab — Final Codebase
Bitcoin price case study · Lab Code 2115120 · Semester V
Divvye Kansara (2403080) · Jai Kukreja (2403090)

Run everything with this folder as the working directory — every path below is relative to it.

## Order to run

| # | File | Experiment | Reads | Writes |
|---|------|-----------|-------|--------|
| 1 | `sql/exp2_01_create_database.sql` … `exp2_05_verify.sql` | 2 | `btc_flat_final_2.csv` | PostgreSQL database `btc_dw` |
| 2 | `sql/exp3_olap_operations.sql` | 3 | `btc_dw` | query output |
| 3 | `data_cleaning_v2.py` | 4 (Part A) | `btc_flat_final_2.csv` | `btc_cleaned_v2.csv` |
| 4 | `experiment_4_preprocessing.ipynb` | 4 (Part B) | `btc_flat_final_2.csv`, `btc_cleaned_v2.csv` | `btc_preprocessed_v1.csv`, `exp4_outputs/` |
| 5 | `experiment_5.ipynb` | 4 (Part C) | `btc_cleaned.csv` | inline graphs |
| 6 | `experiment_5_naive_bayes_tree.ipynb` | 5 | `btc_preprocessed_v1.csv` | `exp5_outputs/` |
| 7 | `exp6_paper_example.py` | 6 (paper example) | `btc_cleaned.csv` | console output |
| 8 | `experiment_6_kmeans.ipynb` | 6 | `btc_cleaned.csv` | `exp6_outputs/` |
| 9 | `experiment_7_hierarchical_clustering.ipynb` | 7 | `btc_preprocessed_v1.csv` | `exp7_outputs/` |
| 10 | `experiment_8_apriori.ipynb` | 8 | `btc_preprocessed_v1.csv` | `exp8_outputs/`, `exp8_association_rules.csv` |

Experiments 2 and 3 are independent of the Python chain; 4 must run before 5, 7 and 8.

## SQL setup (Experiments 2 and 3)

```bash
psql -U postgres -f sql/exp2_01_create_database.sql
psql -d btc_dw -f sql/exp2_02_create_tables.sql
# in psql, client-side load (no superuser needed):
#   \copy staging_btc_daily FROM 'btc_flat_final_2.csv' WITH (FORMAT csv, HEADER true, NULL '')
psql -d btc_dw -f sql/exp2_04_etl.sql
psql -d btc_dw -f sql/exp2_05_verify.sql
psql -d btc_dw -f sql/exp3_olap_operations.sql
```

`exp2_03_load_staging.sql` uses a server-side `COPY` from an absolute path; the `\copy` line above is
the client-side equivalent and is usually the easier one to run locally.

## Python dependencies

```
pandas  numpy  matplotlib  seaborn  scipy  scikit-learn  jupyter
```

scikit-learn is used **only** to verify the from-scratch implementations (Experiments 5, 6, 7) — no
experiment depends on it for its result.

## Data files

| File | What it is |
|------|-----------|
| `btc_flat_final_2.csv` | raw source, 5,684 rows, 20 columns (has 1 duplicate date and 50 calendar gaps) |
| `btc_cleaned.csv` | earlier cleaned file produced by the original `data_cleaning.py`; used by Experiments 5 (Part C) and 6 |
| `btc_cleaned_v2.csv` | output of `data_cleaning_v2.py` — same numbers, plus `is_interpolated`, with the halving counter preserved |
| `btc_preprocessed_v1.csv` | Experiment 4 output — cleaned, normalised, discretized; input to Experiments 5, 7 and 8 |

The superseded originals (`data_cleaning.py`, `k_means.py`, `btc_flat_final.csv`) were left in the parent
DWM folder rather than moved here.
