"""
Diagnose which design-variable bounds the accepted (successful) designs are
saturating, to decide how to widen pitch_bounds / chord_bounds.

Reuses the exact bounds and con/design-var conventions from
gp_infill_from_training_data.py and the pipeline's training data.
"""

import numpy as np

from pipeline_config import training_data_files
from pipeline_io import load_table
from gp_infill_from_training_data import bounds_all

VAR_NAMES = [
    "pitch_p1y", "pitch_y4frac", "pitch_p4x", "pitch_d1", "pitch_d2", "pitch_p7y",
    "chord_p1y", "chord_p4x", "chord_d1", "chord_y4", "chord_w56",
]

EDGE_TOL_FRAC = 0.02   # "at bound": within 2% of the range from an edge
NEAR_TOL_FRAC = 0.10   # "near bound": within 10% of the range from an edge
TOP_N = 15             # how many best-efficiency designs to highlight


def load_all_designs():
    """Return (X design-vars, eff) for every successful training row."""
    X_rows, eff_rows = [], []
    for path in training_data_files():
        block = load_table(path)
        if block.shape[1] < 13:
            continue
        X_rows.append(block[:, :11])
        eff_rows.append(block[:, 12])
    X = np.vstack(X_rows)
    eff = np.concatenate(eff_rows)
    return X, eff


def edge_flags(X, tol_frac):
    """Return boolean masks (at_low, at_high) per (row, dim)."""
    lo = bounds_all[:, 0]
    hi = bounds_all[:, 1]
    span = np.maximum(hi - lo, 1e-12)
    at_low = (X - lo) / span <= tol_frac
    at_high = (hi - X) / span <= tol_frac
    return at_low, at_high


def summarize(X, eff, label):
    n = X.shape[0]
    at_low, at_high = edge_flags(X, EDGE_TOL_FRAC)
    near_low, near_high = edge_flags(X, NEAR_TOL_FRAC)

    print(f"\n=== {label} (n={n}) ===")
    print(f"{'variable':<14} {'bounds':<16} "
          f"{'@lo':>5} {'@hi':>5} {'~lo':>5} {'~hi':>5}   note")
    for j, name in enumerate(VAR_NAMES):
        lo, hi = bounds_all[j]
        c_lo = int(at_low[:, j].sum())
        c_hi = int(at_high[:, j].sum())
        c_nlo = int(near_low[:, j].sum())
        c_nhi = int(near_high[:, j].sum())
        note = ""
        if c_lo / n >= 0.30:
            note += f" LOWER saturated ({100*c_lo/n:.0f}%)"
        if c_hi / n >= 0.30:
            note += f" UPPER saturated ({100*c_hi/n:.0f}%)"
        print(f"{name:<14} [{lo:>5.2f},{hi:>5.2f}]   "
              f"{c_lo:>5} {c_hi:>5} {c_nlo:>5} {c_nhi:>5}  {note}")


def main():
    X, eff = load_all_designs()

    summarize(X, eff, "ALL successful designs")

    order = np.argsort(eff)[::-1]
    top_idx = order[:TOP_N]
    summarize(X[top_idx], eff[top_idx], f"TOP {TOP_N} by efficiency")

    print(f"\nTop {TOP_N} designs (efficiency + design vars):")
    lo = bounds_all[:, 0]
    hi = bounds_all[:, 1]
    span = np.maximum(hi - lo, 1e-12)
    for rank, i in enumerate(top_idx, 1):
        x = X[i]
        marks = []
        for j in range(11):
            frac = (x[j] - lo[j]) / span[j]
            if frac <= EDGE_TOL_FRAC:
                marks.append(f"{VAR_NAMES[j]}=lo")
            elif frac >= 1.0 - EDGE_TOL_FRAC:
                marks.append(f"{VAR_NAMES[j]}=hi")
        print(f"  #{rank:<2} eff={eff[i]:.4f}  at-bound: {', '.join(marks) if marks else '(none)'}")


if __name__ == "__main__":
    main()
