"""
Plot Pitch-over-Diameter and Chord-over-Diameter for the top-3 propeller
configurations (by matched intersection efficiency) against the original
baseline blade.

Top-3 (from this workspace's first_training results):
    Rank 1: infill 3, case 24  (eta=0.5347, J=0.5765)
    Rank 2: original, case  8  (eta=0.5307, J=0.5940)
    Rank 3: infill 4, case  1  (eta=0.5305, J=0.5866)

The "Original" reference curves are the polynomial fits hard-coded at the
top of x_blade.py. The "Optimized" curves are produced by running those
originals through `para_control_bez_updated` with each case's 11 design
variables.
"""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

from para_control_bez_updated import para_control_bez_updated
from gp_infill_from_training_data import conpoints_to_designvars


ROOT = Path(__file__).resolve().parent

# Per-file storage format:
#   "designvars" -> [p_p1y, y4_frac, p_p4x, d1_pitch, d2_pitch, p_p7y,
#                    c_p1y, c_p4x, d1_chord, c_y4, c_w56]   (what `para_control_bez_updated` expects)
#   "conpoints"  -> [p_p1y, p_y4, p_p4x, p_p2x, p_p5x, p_p7y,
#                    c_p1y, c_p4x, c_p2x, c_y4, c_w56]      (needs `conpoints_to_designvars`)
# The infill `*_control_points_*.txt` outputs from gp_infill_from_training_data.py
# are design-vars; the original `Control_point_values.dat` stores con-points.
CONFIGS = [
    {
        "label": "Promising Candidate",
        "file": ROOT / "Control_point_values.dat",
        "row": 8,
        "format": "conpoints",
        "color": "#1f77b4",
        "marker": "s",
    }
]

# Match the look of the reference figure
FONT_FAMILY = "Times New Roman"
TITLE_FONTSIZE = 26
LABEL_FONTSIZE = 22
TICK_FONTSIZE = 18
LEGEND_FONTSIZE = 17
ORIGINAL_LINEWIDTH = 2.6
MARKER_SIZE = 4
MARKER_EDGEWIDTH = 0.6
N_MARKERS = 70

plt.rcParams.update({"font.family": FONT_FAMILY})


def original_pitch(x):
    """Baseline pitch polynomial (P/D), copied verbatim from x_blade.py."""
    return (
        19344.5071 * x**12
        - 114044.8587 * x**11
        + 280789.2801 * x**10
        - 357377.6146 * x**9
        + 207947.2705 * x**8
        + 43330.8173 * x**7
        - 173099.4797 * x**6
        + 143116.5772 * x**5
        - 65570.9523 * x**4
        + 18410.2055 * x**3
        - 3128.7530 * x**2
        + 294.0671 * x
        - 10.4419
    )


def original_chord(x):
    """Baseline chord polynomial (c/D), copied verbatim from x_blade.py."""
    return (
        -143202.4761 * x**12
        + 978274.9902 * x**11
        - 2992184.0323 * x**10
        + 5408923.9625 * x**9
        - 6424276.8851 * x**8
        + 5271614.6993 * x**7
        - 3058632.5267 * x**6
        + 1261908.7720 * x**5
        - 366745.1423 * x**4
        + 73096.4455 * x**3
        - 9470.1908 * x**2
        + 716.1619 * x
        - 23.7157
    )


def max_camber_over_chord(x):
    """Baseline max camber polynomial (camber / chord), from x_blade.py:25."""
    return (
        -4448.8369 * x**12
        + 30393.6831 * x**11
        - 92977.6043 * x**10
        + 168066.8833 * x**9
        - 199490.6759 * x**8
        + 163416.9800 * x**7
        - 94493.8152 * x**6
        + 38765.7447 * x**5
        - 11176.4246 * x**4
        + 2207.9559 * x**3
        - 285.0846 * x**2
        + 21.9443 * x
        - 0.7490
    )


def max_thickness_over_chord(x):
    """Baseline max thickness polynomial (thickness / chord), from x_blade.py:31."""
    return (
        -9688.7237 * x**12
        + 59807.8900 * x**11
        - 164159.4387 * x**10
        + 265158.4257 * x**9
        - 281726.9910 * x**8
        + 209033.5305 * x**7
        - 112447.0353 * x**6
        + 44837.0567 * x**5
        - 13266.8679 * x**4
        + 2814.8064 * x**3
        - 391.1763 * x**2
        + 29.0131 * x
        - 0.4854
    )


def load_design_variables(path: Path, row_index: int, fmt: str) -> np.ndarray:
    """Return the (11,) design-variable row, converting from con-points if needed.

    `fmt` is one of:
      - "designvars": file already stores design-vars (pass-through).
      - "conpoints" : file stores con-points; apply `conpoints_to_designvars`.
    """
    data = np.loadtxt(path)
    if data.ndim == 1:
        data = data.reshape(1, -1)
    if data.shape[1] != 11:
        raise ValueError(
            f"Expected 11 columns per row in {path.name}, got {data.shape[1]}"
        )
    if row_index < 0 or row_index >= data.shape[0]:
        raise IndexError(
            f"Row {row_index} out of range for {path.name} (n_rows={data.shape[0]})"
        )

    row = data[row_index].astype(float)
    if fmt == "designvars":
        return row
    if fmt == "conpoints":
        return conpoints_to_designvars(row.reshape(1, -1))[0]
    raise ValueError(f"Unknown format '{fmt}'. Use 'designvars' or 'conpoints'.")


def build_optimized_curves(design_vars: np.ndarray, case_id):
    """
    Run the 11-variable design vector through `para_control_bez_updated` and
    return callable Pitch and ChordLength functions for the optimized blade.

    The ordering is: 6 pitch variables then 5 chord variables, matching
    Initial_sampling.py and para_control_bez_updated.py.
    """
    pitch_con = design_vars[:6]
    chord_con = design_vars[6:]

    R_values = np.concatenate([np.arange(0.17, 0.985, 0.018), [0.99, 0.999]])

    Pitch_opt, ChordLength_opt, _, _ = para_control_bez_updated(
        original_pitch,
        original_chord,
        R_values,
        7,  # para_control = 7  -> apply Bezier control to both pitch and chord
        pitch_con,
        chord_con,
        case_id=case_id,
        constraint_mode="project",
    )
    return Pitch_opt, ChordLength_opt


def _report_design_vars(label: str, dv: np.ndarray) -> None:
    """Print the 11 design-vars feeding `para_control_bez_updated`."""
    pc, cc = dv[:6], dv[6:]
    pitch_y4 = pc[0] + (1.4 - pc[0]) * pc[1]
    print(f"--- {label} (design-vars fed to para_control_bez_updated) ---")
    print(
        f"  pitch: p1y={pc[0]:.4f}, y4_frac={pc[1]:.4f} (-> y4={pitch_y4:.4f}), "
        f"p4x={pc[2]:.4f}, d1={pc[3]:.4f}, d2={pc[4]:.4f}, p7y={pc[5]:.4f}"
    )
    print(
        f"  chord: p1y={cc[0]:.4f}, p4x={cc[1]:.4f}, d1={cc[2]:.4f}, "
        f"y4={cc[3]:.4f}, w56={cc[4]:.4f}"
    )


def _style_axis(ax, ylabel):
    ax.set_xlabel("Normalized Radius [-]", fontsize=LABEL_FONTSIZE)
    ax.set_ylabel(ylabel, fontsize=LABEL_FONTSIZE)
    ax.tick_params(axis="both", labelsize=TICK_FONTSIZE, length=6, width=1.2)
    ax.set_xlim(0.17, 1.0)
    ax.grid(True, which="major", linestyle="-", linewidth=0.6, alpha=0.25)
    for spine in ax.spines.values():
        spine.set_linewidth(1.2)
    ax.legend(
        prop={"family": FONT_FAMILY, "size": LEGEND_FONTSIZE},
        loc="best",
        frameon=True,
        framealpha=0.9,
        edgecolor="0.7",
    )


def _tip_biased_spacing(a: float, b: float, n: int) -> np.ndarray:
    """Half-cosine spacing in [a, b] that clusters points near the upper end `b`.

    Uses x(t) = a + (b - a) * sin(pi/2 * t) for t in [0, 1]:
        dx/dt(0) = pi/2 * (b - a)   (sparse near a)
        dx/dt(1) = 0                (dense near b)

    This handles the steep pitch/chord drop-off near the tip (R -> 1) while
    keeping the inner-blade region (R near 0.2) sparser.
    """
    t = np.linspace(0.0, 1.0, n)
    return a + (b - a) * np.sin(0.5 * np.pi * t)


def main() -> None:
    r_smooth = np.linspace(0.17, 1.0, 400)
    r_markers = _tip_biased_spacing(0.20, 0.99, N_MARKERS)

    # Pre-load each config's design vars and build curve callables once
    eval_curves = []
    for cfg in CONFIGS:
        design_vars = load_design_variables(cfg["file"], cfg["row"], cfg["format"])
        _report_design_vars(cfg["label"], design_vars)
        Pitch_opt, ChordLength_opt = build_optimized_curves(design_vars, cfg["label"])
        eval_curves.append((cfg, Pitch_opt, ChordLength_opt))

    # --- Figure 1: Pitch / Diameter ---
    fig_p, ax_pitch = plt.subplots(figsize=(9, 6))
    ax_pitch.plot(
        r_smooth,
        original_pitch(r_smooth),
        color="black",
        linestyle="--",
        linewidth=ORIGINAL_LINEWIDTH,
        label="Original",
        zorder=3,
    )
    for cfg, Pitch_opt, _ in eval_curves:
        pitch_pts = np.asarray(Pitch_opt(r_markers), dtype=float)
        ax_pitch.plot(
            r_markers, pitch_pts,
            linestyle="None", marker=cfg["marker"], markersize=MARKER_SIZE,
            markerfacecolor=cfg["color"], markeredgecolor=cfg["color"],
            markeredgewidth=MARKER_EDGEWIDTH, label=cfg["label"], zorder=4,
        )
    _style_axis(ax_pitch, "Pitch Over Diameter [-]")
    fig_p.suptitle("Pitch Distribution", fontsize=TITLE_FONTSIZE, y=0.98)
    fig_p.tight_layout(rect=[0, 0, 1, 0.94])

    # --- Figure 2: Chord / Diameter ---
    fig_c, ax_chord = plt.subplots(figsize=(9, 6))
    ax_chord.plot(
        r_smooth,
        original_chord(r_smooth),
        color="black",
        linestyle="--",
        linewidth=ORIGINAL_LINEWIDTH,
        label="Original",
        zorder=3,
    )
    for cfg, _, ChordLength_opt in eval_curves:
        chord_pts = np.asarray(ChordLength_opt(r_markers), dtype=float)
        ax_chord.plot(
            r_markers, chord_pts,
            linestyle="None", marker=cfg["marker"], markersize=MARKER_SIZE,
            markerfacecolor=cfg["color"], markeredgecolor=cfg["color"],
            markeredgewidth=MARKER_EDGEWIDTH, label=cfg["label"], zorder=4,
        )
    _style_axis(ax_chord, "Chord Over Diameter [-]")
    fig_c.suptitle("Chord Distribution", fontsize=TITLE_FONTSIZE, y=0.98)
    fig_c.tight_layout(rect=[0, 0, 1, 0.94])

    # --- Figure 3: Max Camber (absolute) ---
    # `MaxCamber(R)` from x_blade.py is camber/chord (a section property), and
    # `para_control_bez_updated` does NOT modify it. So if we plot the *ratio*
    # camber/chord, all designs collapse onto the original.
    # What para.py actually uses for the blade geometry (lines 47-49) is the
    # ABSOLUTE camber  max_c = MaxCamber(R) * ChordLength(R)  (times d, a
    # constant scaling). That is the per-design quantity, and it differs by
    # design because ChordLength differs.
    fig_cam, ax_cam = plt.subplots(figsize=(9, 6))
    cam_ratio_smooth = max_camber_over_chord(r_smooth)
    cam_ratio_pts = max_camber_over_chord(r_markers)
    ax_cam.plot(
        r_smooth,
        cam_ratio_smooth * original_chord(r_smooth),
        color="black",
        linestyle="--",
        linewidth=ORIGINAL_LINEWIDTH,
        label="Original",
        zorder=3,
    )
    for cfg, _, ChordLength_opt in eval_curves:
        chord_pts = np.asarray(ChordLength_opt(r_markers), dtype=float)
        cam_pts = cam_ratio_pts * chord_pts
        ax_cam.plot(
            r_markers, cam_pts,
            linestyle="None", marker=cfg["marker"], markersize=MARKER_SIZE,
            markerfacecolor=cfg["color"], markeredgecolor=cfg["color"],
            markeredgewidth=MARKER_EDGEWIDTH, label=cfg["label"], zorder=4,
        )
    _style_axis(ax_cam, "Max Camber [-]")
    fig_cam.suptitle("Max Camber Distribution", fontsize=TITLE_FONTSIZE, y=0.98)
    fig_cam.tight_layout(rect=[0, 0, 1, 0.94])

    # --- Figure 4: Max Thickness (absolute) ---
    # Same logic as Figure 3: plot MaxThickness(R) * ChordLength(R) per design.
    fig_thk, ax_thk = plt.subplots(figsize=(9, 6))
    thk_ratio_smooth = max_thickness_over_chord(r_smooth)
    thk_ratio_pts = max_thickness_over_chord(r_markers)
    ax_thk.plot(
        r_smooth,
        thk_ratio_smooth * original_chord(r_smooth),
        color="black",
        linestyle="--",
        linewidth=ORIGINAL_LINEWIDTH,
        label="Original",
        zorder=3,
    )
    for cfg, _, ChordLength_opt in eval_curves:
        chord_pts = np.asarray(ChordLength_opt(r_markers), dtype=float)
        thk_pts = thk_ratio_pts * chord_pts
        ax_thk.plot(
            r_markers, thk_pts,
            linestyle="None", marker=cfg["marker"], markersize=MARKER_SIZE,
            markerfacecolor=cfg["color"], markeredgecolor=cfg["color"],
            markeredgewidth=MARKER_EDGEWIDTH, label=cfg["label"], zorder=4,
        )
    _style_axis(ax_thk, "Max Thickness [-]")
    fig_thk.suptitle("Max Thickness Distribution", fontsize=TITLE_FONTSIZE, y=0.98)
    fig_thk.tight_layout(rect=[0, 0, 1, 0.94])

    plt.show()



if __name__ == "__main__":
    main()
