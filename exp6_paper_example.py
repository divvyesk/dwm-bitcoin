"""
Experiment 6 - K-Means Clustering
Part A: Hand-solvable numerical example (verification of the paper working)

Eight Bitcoin trading days are described by two features:
    x = daily_pct_change   -> (close - open) / open * 100      [direction of the day]
    y = daily_range_pct    -> (high - low)   / open * 100      [intraday swing size]

The same eight points, the same initial centroids and the same rounding
(1 decimal place) are used in the handwritten writeup, so every distance
printed below can be checked against the journal by hand.

No clustering library is used - assignment, centroid update and the
convergence test are all written out explicitly.
"""

import csv
import math

CLEAN_PATH = "btc_cleaned.csv"

# Labels A..H are the point names used in the handwritten solution
SAMPLE_DATES = [
    ("A", "2022-01-18"),   # calm bull day
    ("B", "2025-03-01"),   # calm bull day
    ("C", "2019-09-10"),   # calm bear day
    ("D", "2017-12-17"),   # calm bear day
    ("E", "2013-11-29"),   # volatile bull day
    ("F", "2018-02-06"),   # volatile bull day
    ("G", "2013-12-07"),   # crash day
    ("H", "2020-03-12"),   # crash day  ("Black Thursday")
]


def load_sample(path, dates):
    """Pull the eight chosen days out of the cleaned dataset and build (x, y)."""
    wanted = {d for _, d in dates}
    found = {}
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            if row["date"] in wanted:
                x = float(row["daily_pct_change"])
                y = float(row["daily_range"]) / float(row["open"]) * 100
                found[row["date"]] = (round(x, 1), round(y, 1))
    return [found[d] for _, d in dates]


def euclidean(p, q):
    return math.sqrt((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2)


def assign_clusters(points, centroids):
    """Nearest-centroid assignment. Returns (labels, distance table)."""
    labels, table = [], []
    for p in points:
        dists = [euclidean(p, c) for c in centroids]
        nearest = dists.index(min(dists))
        labels.append(nearest)
        table.append([round(d, 2) for d in dists])
    return labels, table


def recompute_centroids(points, labels, k, old_centroids):
    """New centroid = arithmetic mean of the points assigned to that cluster."""
    sums = [[0.0, 0.0] for _ in range(k)]
    counts = [0] * k
    for p, c in zip(points, labels):
        sums[c][0] += p[0]
        sums[c][1] += p[1]
        counts[c] += 1
    new = []
    for i in range(k):
        if counts[i] == 0:                 # empty cluster -> keep the old centroid
            new.append(old_centroids[i])
        else:
            new.append((round(sums[i][0] / counts[i], 2),
                        round(sums[i][1] / counts[i], 2)))
    return new


def sse(points, labels, centroids):
    """Sum of Squared Errors - the objective K-Means minimises."""
    return round(sum(euclidean(p, centroids[c]) ** 2 for p, c in zip(points, labels)), 2)


def kmeans(points, names, k, initial_centroids, max_iter=10):
    centroids = list(initial_centroids)
    labels = None
    for it in range(1, max_iter + 1):
        labels, table = assign_clusters(points, centroids)

        print(f"\n{'-' * 66}")
        print(f"ITERATION {it}")
        print(f"{'-' * 66}")
        print("Centroids used:", "  ".join(f"C{i+1}={c}" for i, c in enumerate(centroids)))
        header = f"{'Pt':<4}{'(x, y)':<18}" + "".join(f"{'d(C'+str(i+1)+')':<10}" for i in range(k)) + "Cluster"
        print(header)
        for name, p, row, lab in zip(names, points, table, labels):
            line = f"{name:<4}{str(p):<18}" + "".join(f"{d:<10}" for d in row) + f"C{lab+1}"
            print(line)

        for i in range(k):
            members = [names[j] for j, lab in enumerate(labels) if lab == i]
            print(f"  Cluster {i+1}: {{{', '.join(members)}}}")
        print(f"  SSE = {sse(points, labels, centroids)}")

        new_centroids = recompute_centroids(points, labels, k, centroids)
        print("Recomputed centroids:", "  ".join(f"C{i+1}={c}" for i, c in enumerate(new_centroids)))

        if new_centroids == centroids:
            print(f"\n>> Centroids unchanged -> converged after {it} iteration(s).")
            return centroids, labels, it
        centroids = new_centroids

    return centroids, labels, max_iter


def main():
    names = [n for n, _ in SAMPLE_DATES]
    points = load_sample(CLEAN_PATH, SAMPLE_DATES)

    print("=" * 66)
    print("K-MEANS BY HAND - 8 BITCOIN TRADING DAYS  (k = 2)")
    print("=" * 66)
    print(f"{'Pt':<4}{'Date':<14}{'x = daily %chg':<18}{'y = range % of open':<20}")
    for (name, date), p in zip(SAMPLE_DATES, points):
        print(f"{name:<4}{date:<14}{p[0]:<18}{p[1]:<20}")

    k = 2
    initial = [points[0], points[2]]     # C1 = A (2022-01-18), C2 = C (2019-09-10)
    print(f"\nInitial centroids (points A and C):  C1 = {initial[0]}   C2 = {initial[1]}")

    centroids, labels, iters = kmeans(points, names, k, initial)

    print("\n" + "=" * 66)
    print("FINAL RESULT")
    print("=" * 66)
    for i in range(k):
        members = [f"{names[j]} ({SAMPLE_DATES[j][1]})" for j, lab in enumerate(labels) if lab == i]
        print(f"Cluster {i+1}  centroid {centroids[i]}")
        for m in members:
            print(f"    - {m}")
    print(f"\nIterations to converge : {iters}")
    print(f"Final SSE              : {sse(points, labels, centroids)}")
    print("\nInterpretation:")
    print("  Cluster 1 = ordinary trading days  - small % change, narrow intraday range")
    print("  Cluster 2 = turbulent / crash days - large negative change, very wide range")

    # ---- Sensitivity check: the same 8 points seeded differently --------
    print("\n" + "=" * 66)
    print("SENSITIVITY OF K-MEANS TO THE INITIAL CENTROIDS")
    print("=" * 66)
    for seed_a, seed_b in [("A", "C"), ("B", "E"), ("A", "G")]:
        ia, ib = names.index(seed_a), names.index(seed_b)
        c = [points[ia], points[ib]]
        for it in range(1, 20):
            lab, _ = assign_clusters(points, c)
            nc = recompute_centroids(points, lab, 2, c)
            if nc == c:
                break
            c = nc
        groups = ["".join(names[j] for j, l in enumerate(lab) if l == i) for i in range(2)]
        print(f"  seeds ({seed_a}, {seed_b}): {it} iterations -> "
              f"{{{groups[0]}}} | {{{groups[1]}}}   SSE = {sse(points, lab, c)}")
    print("\n  Different seeds can settle on different local optima; the partition")
    print("  with the lower SSE is the better one, which is why K-Means is normally")
    print("  restarted several times and the best run is kept.")


if __name__ == "__main__":
    main()
