from itertools import combinations

import numpy as np
import matplotlib.pyplot as plt
from scipy import stats
from sklearn.covariance import MinCovDet

# Keep in sync with gp_infill_from_training_data.py (expanded after infill5 edge-saturation).
pitch_bounds = np.array([
    [0.60, 1.25],  # pitch_p1y
    [0.00, 1.00],  # pitch_y4
    [0.35, 0.75],  # pitch_p4x
    [0.05, 0.50],  # pitch_d1
    [0.05, 0.50],  # pitch_d2
    [0.40, 0.85],  # pitch_p7y
])

chord_bounds = np.array([
    [0.15, 0.30],  # chord_p1y
    [0.45, 0.85],  # chord_p4x
    [0.05, 0.50],  # chord_d1
    [0.25, 0.70],  # chord_y4
    [0.05, 0.30],  # chord_w56
])

bounds_all = np.vstack([pitch_bounds, chord_bounds])

feature_names = [
    "pitch_p1y", "pitch_y4", "pitch_p4x", "pitch_d1", "pitch_d2", "pitch_p7y",
    "chord_p1y", "chord_p4x", "chord_d1", "chord_y4", "chord_w56"
]
TOP_K_FEATURES = 4

X_raw = np.genfromtxt(
    # "gp_classifier_dataset_clean.txt",
    "generated_initial_sampling_control_points_tagged.txt",
    delimiter="|",
    skip_header=2,
    usecols=range(3, 14),
    autostrip=True,
)
y = np.genfromtxt(
    # "gp_classifier_dataset_clean.txt",
    "generated_initial_sampling_control_points_tagged.txt",
    delimiter="|",
    skip_header=2,
    usecols=14,
    autostrip=True,
)

# Optional normalization by bounds. This will not change MCD/Mahalanobis results here.
X = (X_raw - bounds_all[:, 0]) / (bounds_all[:, 1] - bounds_all[:, 0])

X_success = X[y == 0]
X_failed = X[y == 1]
failed_indices = np.where(y == 1)[0]

mcd = MinCovDet(random_state=0).fit(X_success)

T = mcd.location_
S = mcd.covariance_
A = np.linalg.pinv(S)

def mahalanobis_feature_contrib(X, T, A):
    D = X - T
    AD = D @ A.T
    contrib = D * AD
    rd2 = contrib.sum(axis=1)
    return rd2, contrib


def make_panel_grid(n_panels, ncols=3, panel_width=5.2, panel_height=4.2):
    ncols = min(ncols, max(1, n_panels))
    nrows = (n_panels + ncols - 1) // ncols
    fig, axes = plt.subplots(nrows, ncols, figsize=(panel_width * ncols, panel_height * nrows))
    axes = np.atleast_1d(axes).ravel()
    for ax in axes[n_panels:]:
        ax.set_visible(False)
    return fig, axes[:n_panels]

rd2_all, contrib_all = mahalanobis_feature_contrib(X, T, A)

sig = 0.05
p = X.shape[1]
threshold = stats.chi2.ppf(1 - sig, p)

outlier_mask = rd2_all > threshold
outlier_indices = np.where(outlier_mask)[0]
failed_outliers = np.intersect1d(outlier_indices, failed_indices)
Percentage_failed_outliers = len(failed_outliers) / (len(outlier_indices)+0.00000000001)

print(f"Number of outliers: {len(outlier_indices)}")
print(f"Number of failed cases: {len(failed_indices)}")
print(f"Number of failed outliers: {len(failed_outliers)}")
print(f"Percentage of failed outliers: {Percentage_failed_outliers:.2f}%")

has_failed_outliers = failed_outliers.size > 0

analysis_failed_indices = failed_outliers if has_failed_outliers else failed_indices
analysis_failed_label = "Failed outlier" if has_failed_outliers else "Failure (fallback)"
analysis_failed_plural = "failed outliers" if has_failed_outliers else "all failed cases (fallback)"
analysis_failed_percentage = Percentage_failed_outliers if has_failed_outliers else 0

if not has_failed_outliers:
    print(
        "\nNo failed outliers were detected at the current chi-square threshold. "
        "Using all failed cases as fallback for lists, summaries, and pair plots."
    )

pos_contrib = np.clip(contrib_all[analysis_failed_indices], 0.0, None)

mean_pos = pos_contrib.mean(axis=0)
median_pos = np.median(pos_contrib, axis=0)
top_count = (pos_contrib == pos_contrib.max(axis=1, keepdims=True)).sum(axis=0)

order = np.argsort(-median_pos)
top_ids = order[:TOP_K_FEATURES].tolist()
pairs = list(combinations(top_ids, 2))

print("\nRanked feature contributions for analyzed failed set:")
for k in order:
    print(
        f"{feature_names[k]:>12s} | "
        f"mean_pos={mean_pos[k]:8.3f} | "
        f"median_pos={median_pos[k]:8.3f} | "
        f"top_count={top_count[k]:3d}"
    )

print(f"\nTop {len(top_ids)} variables used for focused plots/summaries:")
for idx in top_ids:
    print(f"  {feature_names[idx]}")

print("\nFocused variable pairs:")
for i, j in pairs:
    print(f"  {feature_names[i]} vs {feature_names[j]}")

fig, axes = make_panel_grid(len(pairs), ncols=3, panel_width=5.0, panel_height=4.0)
success_mask = y == 0
failed_mask = y == 1
for ax, (x_idx, y_idx) in zip(axes, pairs):
    x_name = feature_names[x_idx]
    y_name = feature_names[y_idx]

    ax.scatter(
        X_raw[success_mask, x_idx],
        X_raw[success_mask, y_idx],
        color="tab:blue",
        alpha=0.7,
        s=30,
        label="Success",
    )
    ax.scatter(
        X_raw[failed_mask, x_idx],
        X_raw[failed_mask, y_idx],
        color="tab:red",
        alpha=0.8,
        s=35,
        label="Failure",
    )

    ax.set_xlabel(x_name)
    ax.set_ylabel(y_name)
    ax.set_title(f"{x_name} vs {y_name}")
    ax.grid(True, alpha=0.3)

handles, labels = axes.flat[0].get_legend_handles_labels()
fig.legend(handles, labels, loc="upper center", ncol=2)
fig.suptitle("Top Failure-Driver Variable Pairs Colored by Outcome", y=0.98)
fig.tight_layout(rect=(0, 0, 1, 0.95))
plt.show()

# -----------------------------
# Plot: successful cases + analyzed failed set in normalized space
# -----------------------------
fig, axes = make_panel_grid(len(pairs), ncols=3, panel_width=5.2, panel_height=4.2)

for ax, (i, j) in zip(axes, pairs):
    # successful cases
    xs = X_success[:, i]
    ys = X_success[:, j]

    # analyzed failed set (failed outliers or fallback all failed cases)
    xfo = X[analysis_failed_indices, i]
    yfo = X[analysis_failed_indices, j]

    # plot successful cases
    ax.scatter(xs, ys, s=22, alpha=0.35, label="Success", zorder=1)

    # plot analyzed failed set
    ax.scatter(xfo, yfo, s=35, alpha=0.85, label=analysis_failed_label, zorder=2)

    ax.set_xlabel(feature_names[i])
    ax.set_ylabel(feature_names[j])
    ax.set_title(f"{feature_names[i]} vs {feature_names[j]}")
    ax.grid(True, alpha=0.25)

# single legend
handles, labels = axes[0].get_legend_handles_labels()
fig.legend(handles, labels, loc="upper center", ncol=2)
fig.suptitle("Analyzed Failed Set vs Successful Designs in Normalized Space", y=0.98)
plt.tight_layout(rect=[0, 0, 1, 0.95])
plt.show()

# -----------------------------
# Print numeric summaries
# -----------------------------
def summarize_feature(name, x_success, x_failed_out):
    q_success = np.percentile(x_success, [5, 25, 50, 75, 95])
    q_failed = np.percentile(x_failed_out, [5, 25, 50, 75, 95])

    print(f"\n{name}")
    print("  Success:")
    print(
        f"    min={x_success.min():.4f}, q05={q_success[0]:.4f}, q25={q_success[1]:.4f}, "
        f"med={q_success[2]:.4f}, q75={q_success[3]:.4f}, q95={q_success[4]:.4f}, max={x_success.max():.4f}"
    )
    print(f"  {analysis_failed_plural.capitalize()}:")
    print(
        f"    min={x_failed_out.min():.4f}, q05={q_failed[0]:.4f}, q25={q_failed[1]:.4f}, "
        f"med={q_failed[2]:.4f}, q75={q_failed[3]:.4f}, q95={q_failed[4]:.4f}, max={x_failed_out.max():.4f}"
    )

print("\n" + "=" * 70)
print(f"Top-variable summaries: successful cases vs {analysis_failed_plural}")
print("=" * 70)

for j in top_ids:
    summarize_feature(
        feature_names[j],
        X_success[:, j],
        X[analysis_failed_indices, j]
    )

import numpy as np
import pandas as pd
from itertools import combinations

# ------------------------------------------------------------
# Top variables from your latest analysis
# ------------------------------------------------------------
top_vars = ["chord_y4", "pitch_p7y", "pitch_p4x", "chord_p1y"]
name_to_idx = {name: i for i, name in enumerate(feature_names)}
top_ids = [name_to_idx[v] for v in top_vars]

# Analyze failed outliers when available; otherwise analyze all failures.
X_fo = X[analysis_failed_indices]

# Tolerance for deciding whether a value is on a bound
tol = 1e-8

# ------------------------------------------------------------
# 1) Per-variable bound-hit rates
# ------------------------------------------------------------
rows = []

for name, j in zip(top_vars, top_ids):
    succ = X_success[:, j]
    fail = X_fo[:, j]

    succ_lower = np.mean(succ <= tol)
    succ_upper = np.mean(succ >= 1 - tol)
    succ_either = np.mean((succ <= tol) | (succ >= 1 - tol))

    fail_lower = np.mean(fail <= tol)
    fail_upper = np.mean(fail >= 1 - tol)
    fail_either = np.mean((fail <= tol) | (fail >= 1 - tol))

    rows.append({
        "variable": name,
        "success_lower_rate": succ_lower,
        "success_upper_rate": succ_upper,
        "success_either_rate": succ_either,
        "failed_out_lower_rate": fail_lower,
        "failed_out_upper_rate": fail_upper,
        "failed_out_either_rate": fail_either,
        "delta_either": fail_either - succ_either,
        "ratio_either": np.nan if succ_either == 0 else fail_either / succ_either,
    })

bound_hit_df = pd.DataFrame(rows).sort_values(
    by="failed_out_either_rate", ascending=False
)

print("\n" + "=" * 100)
print(f"PER-VARIABLE BOUND-HIT RATES ({analysis_failed_plural})")
print("=" * 100)
print(bound_hit_df.to_string(index=False, float_format=lambda x: f"{x:0.3f}"))

# ------------------------------------------------------------
# 2) How many of the top 4 variables hit a bound at once?
# ------------------------------------------------------------
succ_hits = np.sum(
    (X_success[:, top_ids] <= tol) | (X_success[:, top_ids] >= 1 - tol),
    axis=1
)
fail_hits = np.sum(
    (X_fo[:, top_ids] <= tol) | (X_fo[:, top_ids] >= 1 - tol),
    axis=1
)

joint_rows = []
n_top = len(top_ids)

for k in range(n_top + 1):
    joint_rows.append({
        "num_bound_hits": k,
        "success_rate": np.mean(succ_hits == k),
        "failed_out_rate": np.mean(fail_hits == k),
        "delta": np.mean(fail_hits == k) - np.mean(succ_hits == k),
    })

joint_hit_df = pd.DataFrame(joint_rows)

print("\n" + "=" * 100)
print("NUMBER OF TOP-VARIABLE BOUND HITS PER DESIGN")
print("=" * 100)
print(joint_hit_df.to_string(index=False, float_format=lambda x: f"{x:0.3f}"))

print("\nMean number of bound hits")
print(f"  Success            : {succ_hits.mean():0.3f}")
print(f"  {analysis_failed_plural}: {fail_hits.mean():0.3f}")

# ------------------------------------------------------------
# 3) Pairwise co-occurrence table
#    We compute:
#      - both hit any bound
#      - both at upper bound
#      - both at lower bound
#      - first upper / second lower
#      - first lower / second upper
# ------------------------------------------------------------
pair_rows = []

for (name_i, i), (name_j, j) in combinations(zip(top_vars, top_ids), 2):
    succ_i = X_success[:, i]
    succ_j = X_success[:, j]
    fail_i = X_fo[:, i]
    fail_j = X_fo[:, j]

    # Success masks
    s_i_low = succ_i <= tol
    s_i_up = succ_i >= 1 - tol
    s_j_low = succ_j <= tol
    s_j_up = succ_j >= 1 - tol
    s_i_any = s_i_low | s_i_up
    s_j_any = s_j_low | s_j_up

    # Analyzed-failed masks
    f_i_low = fail_i <= tol
    f_i_up = fail_i >= 1 - tol
    f_j_low = fail_j <= tol
    f_j_up = fail_j >= 1 - tol
    f_i_any = f_i_low | f_i_up
    f_j_any = f_j_low | f_j_up

    pair_rows.append({
        "var1": name_i,
        "var2": name_j,
        "success_both_any": np.mean(s_i_any & s_j_any),
        "failed_both_any": np.mean(f_i_any & f_j_any),
        "success_both_upper": np.mean(s_i_up & s_j_up),
        "failed_both_upper": np.mean(f_i_up & f_j_up),
        "success_both_lower": np.mean(s_i_low & s_j_low),
        "failed_both_lower": np.mean(f_i_low & f_j_low),
        "success_var1_upper_var2_lower": np.mean(s_i_up & s_j_low),
        "failed_var1_upper_var2_lower": np.mean(f_i_up & f_j_low),
        "success_var1_lower_var2_upper": np.mean(s_i_low & s_j_up),
        "failed_var1_lower_var2_upper": np.mean(f_i_low & f_j_up),
    })

pair_df = pd.DataFrame(pair_rows)

# Add a few helpful differences
pair_df["delta_both_any"] = pair_df["failed_both_any"] - pair_df["success_both_any"]
pair_df["delta_both_upper"] = pair_df["failed_both_upper"] - pair_df["success_both_upper"]
pair_df["delta_both_lower"] = pair_df["failed_both_lower"] - pair_df["success_both_lower"]

pair_df = pair_df.sort_values(by="failed_both_any", ascending=False)

print("\n" + "=" * 100)
print("PAIRWISE BOUND CO-OCCURRENCE TABLE")
print("=" * 100)
print(pair_df.to_string(index=False, float_format=lambda x: f"{x:0.3f}"))

# ------------------------------------------------------------
# 4) Optional: compact matrix of "both hit any bound" rates
# ------------------------------------------------------------
def make_pair_matrix(X_block, var_names, ids, tol=1e-8):
    n = len(ids)
    M = np.zeros((n, n))
    for a in range(n):
        for b in range(n):
            xa = X_block[:, ids[a]]
            xb = X_block[:, ids[b]]
            a_any = (xa <= tol) | (xa >= 1 - tol)
            b_any = (xb <= tol) | (xb >= 1 - tol)
            M[a, b] = np.mean(a_any & b_any)
    return pd.DataFrame(M, index=var_names, columns=var_names)

succ_pair_any_mat = make_pair_matrix(X_success, top_vars, top_ids, tol=tol)
fail_pair_any_mat = make_pair_matrix(X_fo, top_vars, top_ids, tol=tol)
delta_pair_any_mat = fail_pair_any_mat - succ_pair_any_mat

print("\n" + "=" * 100)
print("SUCCESS: PAIRWISE 'BOTH HIT ANY BOUND' RATE MATRIX")
print("=" * 100)
print(succ_pair_any_mat.to_string(float_format=lambda x: f"{x:0.3f}"))

print("\n" + "=" * 100)
print(f"ANALYZED FAILED SET ({analysis_failed_plural}): PAIRWISE 'BOTH HIT ANY BOUND' RATE MATRIX")
print("=" * 100)
print(fail_pair_any_mat.to_string(float_format=lambda x: f"{x:0.3f}"))

print("\n" + "=" * 100)
print("DELTA MATRIX = ANALYZED FAILED SET - SUCCESS")
print("=" * 100)
print(delta_pair_any_mat.to_string(float_format=lambda x: f"{x:0.3f}"))

import numpy as np
import pandas as pd

# ------------------------------------------------------------
# Inputs assumed available:
#   X              : normalized design matrix, shape (n, p)
#   y              : labels, 0 = success, 1 = failure
#   feature_names  : list of variable names in X order
# ------------------------------------------------------------

name_to_idx = {name: i for i, name in enumerate(feature_names)}

i_chord_y4  = name_to_idx["chord_y4"]
i_pitch_p7y = name_to_idx["pitch_p7y"]
i_pitch_p4x = name_to_idx["pitch_p4x"]
i_chord_p1y = name_to_idx["chord_p1y"]

# Success / failure masks
succ_mask = (y == 0)
fail_mask = (y == 1)

# ------------------------------------------------------------
# Define the two coupled-constraint scores
# ------------------------------------------------------------
s_chord = X[:, i_chord_p1y] + X[:, i_chord_y4]      # want <= b1
s_pitch = X[:, i_pitch_p4x] - X[:, i_pitch_p7y]     # want <= b2

s_chord_succ = s_chord[succ_mask]
s_pitch_succ = s_pitch[succ_mask]

candidate_b1 = np.unique(s_chord_succ)
candidate_b2 = np.unique(s_pitch_succ)

candidate_rows = []
for b1 in candidate_b1:
    chord_ok = s_chord <= b1
    for b2 in candidate_b2:
        feasible = chord_ok & (s_pitch <= b2)
        success_keep = np.mean(feasible[succ_mask])
        failure_reject = np.mean(~feasible[fail_mask])
        score = failure_reject - 0.25 * (1.0 - success_keep)
        candidate_rows.append({
            "b1": b1,
            "b2": b2,
            "success_keep": success_keep,
            "failure_reject": failure_reject,
            "score": score,
        })

candidate_df = pd.DataFrame(candidate_rows).sort_values(
    by=["score", "failure_reject", "success_keep"],
    ascending=[False, False, False],
)
MIN_SUCCESS_KEEP = 0.90
constrained_df = candidate_df[candidate_df["success_keep"] >= MIN_SUCCESS_KEEP].copy()
used_constrained = not constrained_df.empty
ranking_df = constrained_df if used_constrained else candidate_df

top_n_pairs = ranking_df.head(10).copy()
top_n_pairs.insert(0, "rank", np.arange(1, len(top_n_pairs) + 1))

if used_constrained:
    print(f"\nTop 10 b1/b2 pairs by score (success_keep >= {MIN_SUCCESS_KEEP:.2f})")
else:
    print(
        f"\nNo candidate reached success_keep >= {MIN_SUCCESS_KEEP:.2f}. "
        "Showing unconstrained top 10 instead."
    )
    print("Top 10 b1/b2 pairs by score (unconstrained fallback)")
print("=" * 70)
print(
    top_n_pairs.to_string(
        index=False,
        formatters={
            "b1": lambda x: f"{x:.4f}",
            "b2": lambda x: f"{x:.4f}",
            "success_keep": lambda x: f"{x:.3f}",
            "failure_reject": lambda x: f"{x:.3f}",
            "score": lambda x: f"{x:.4f}",
        },
    )
)

best_pair = ranking_df.iloc[0]
selected_b1 = float(best_pair["b1"])
selected_b2 = float(best_pair["b2"])
selected_success_keep = float(best_pair["success_keep"])
selected_failure_reject = float(best_pair["failure_reject"])
selected_score = float(best_pair["score"])

print("\nBest pair evaluation (optimized with success-keep guard)")
print("=" * 70)
print(f"b1 (chord_p1y + chord_y4 <= b1): {selected_b1:.4f}")
print(f"b2 (pitch_p4x - pitch_p7y <= b2): {selected_b2:.4f}")
print(f"Success kept: {selected_success_keep:.3f}")
print(f"Failures rejected: {selected_failure_reject:.3f}")
print(f"Score: {selected_score:.4f}")