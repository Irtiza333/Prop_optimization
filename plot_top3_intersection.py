"""
Generate self-propulsion-point plots (thrust(J) and total_resistance(J)
quadratic fits intersecting) for the top 3 optimized propeller designs.

Designs
-------
1. Opt. Design 1 -> first_training/Results_infill3.txt, case 24
2. Opt. Design 2 -> first_training/Results.txt,        case 8
3. Opt. Design 3 -> first_training/Results_infill4.txt, case 1

Replicates the styling from prop_training.py (same fonts, sizes, markers,
fit curves, intersection marker + dashed vertical line).
"""

import os
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


# ---------------------------------------------------------------------------
# Data sources / cases
# ---------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parent
RESULTS_DIR = ROOT / "first_training"

DESIGNS = [
   
    {
        "label": "Promising Candidate",
        "results_file": RESULTS_DIR / "Results.txt",
        "case_id": 8,
    }
 
]

OUTPUT_DIR = ROOT / "top3_intersection_plots"
SAVE_PLOTS = True
SHOW_PLOTS = True


# ---------------------------------------------------------------------------
# Plot styling (matches prop_training.py "big-format" look)
# ---------------------------------------------------------------------------
FONT_FAMILY = "Times New Roman"
FIGSIZE = (22, 16)
TITLE_FONTSIZE = 60
LABEL_FONTSIZE = 60
TICK_FONTSIZE = 52
LEGEND_FONTSIZE = 42
CURVE_LINEWIDTH = 5.0
GRID_LINEWIDTH = 2.0
DATA_MARKERSIZE = 18
INTERSECTION_MARKERSIZE = 22
SUBPLOT_ADJUST = dict(left=0.11, right=0.99, bottom=0.13, top=0.92)

plt.rcParams.update(
    {
        "font.family": FONT_FAMILY,
        "font.size": LABEL_FONTSIZE,
    }
)


# ---------------------------------------------------------------------------
# Helpers (mirrors prop_training.py logic)
# ---------------------------------------------------------------------------
def _load_results_table(path: Path) -> np.ndarray:
    try:
        data = np.loadtxt(path, comments="#")
    except ValueError:
        data = np.loadtxt(path, comments="#", skiprows=1)
    if data.ndim == 1:
        data = data.reshape(1, -1)
    return data


def _intersection_J(poly_thrust: np.poly1d, poly_res: np.poly1d,
                    J_arr: np.ndarray) -> float:
    roots = np.roots(poly_thrust - poly_res)
    real_roots = roots[np.isreal(roots)].real
    j_min, j_max, j_mid = float(np.min(J_arr)), float(np.max(J_arr)), float(np.mean(J_arr))
    if real_roots.size == 0:
        return float("nan")
    in_range = real_roots[(real_roots >= j_min) & (real_roots <= j_max)]
    if in_range.size > 0:
        return float(in_range[np.argmin(np.abs(in_range - j_mid))])
    return float(real_roots[np.argmin(np.abs(real_roots - j_mid))])


def _plot_design(design: dict) -> None:
    data = _load_results_table(design["results_file"])
    case_id = design["case_id"]
    case_data = data[data[:, 0].astype(int) == case_id, :]
    if case_data.shape[0] < 3:
        raise RuntimeError(
            f"{design['label']}: only {case_data.shape[0]} rows for case {case_id} "
            f"in {design['results_file'].name} (need >=3 for quadratic fit)."
        )

    case_data = case_data[np.argsort(case_data[:, 1])]
    J = case_data[:, 1]
    thrust = np.abs(case_data[:, 4])
    total_resistance = np.abs(case_data[:, 7])

    poly_thrust = np.poly1d(np.polyfit(J, thrust, 2))
    poly_res = np.poly1d(np.polyfit(J, total_resistance, 2))

    intersection_J = _intersection_J(poly_thrust, poly_res, J)
    intersection_thrust = float(poly_thrust(intersection_J)) if np.isfinite(intersection_J) else float("nan")

    fig, ax = plt.subplots(figsize=FIGSIZE)

    ax.plot(
        J, thrust,
        linestyle="None", marker="o", markersize=DATA_MARKERSIZE,
        label="thrust (data)",
    )
    ax.plot(
        J, total_resistance,
        linestyle="None", marker="s", markersize=DATA_MARKERSIZE,
        label="total_resistance (data)",
    )

    j_grid = np.linspace(float(np.min(J)), float(np.max(J)), 200)
    ax.plot(j_grid, poly_thrust(j_grid), "-", linewidth=CURVE_LINEWIDTH,
            label="thrust (quadratic fit)")
    ax.plot(j_grid, poly_res(j_grid), "-", linewidth=CURVE_LINEWIDTH,
            label="total_resistance (quadratic fit)")

    if np.isfinite(intersection_J):
        ax.plot(
            intersection_J, intersection_thrust,
            linestyle="None", marker="o", markersize=INTERSECTION_MARKERSIZE,
            color="g", label="intersection (fit=fit)",
        )
        ax.axvline(intersection_J, color="g", alpha=0.25, linewidth=2)

    ax.set_title(design["label"], fontname=FONT_FAMILY, fontsize=TITLE_FONTSIZE)
    ax.set_xlabel("J", fontname=FONT_FAMILY, fontsize=LABEL_FONTSIZE)
    ax.set_ylabel("Force (N)", fontname=FONT_FAMILY, fontsize=LABEL_FONTSIZE)
    ax.tick_params(axis="both", labelsize=TICK_FONTSIZE)
    ax.legend(prop={"family": FONT_FAMILY, "size": LEGEND_FONTSIZE})
    ax.grid(True, linewidth=GRID_LINEWIDTH, alpha=0.35)
    fig.subplots_adjust(**SUBPLOT_ADJUST)

    if SAVE_PLOTS:
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        out_path = OUTPUT_DIR / f"{design['label'].lower().replace('. ', '_').replace(' ', '_')}.png"
        fig.savefig(out_path, dpi=200)
        print(f"Saved: {out_path}")

    print(
        f"{design['label']}: J*={intersection_J:.4f}, "
        f"T*={intersection_thrust:.2f} N"
    )


def main() -> None:
    for design in DESIGNS:
        _plot_design(design)
    if SHOW_PLOTS:
        plt.show()


if __name__ == "__main__":
    main()
