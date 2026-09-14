"""
Plot all pitch/chord curves from initial training through infill 6.

Successful cases are plotted in green.
Failed cases are plotted in red.

Success/failure is determined directly from the results files:
- a case is successful if its case id appears in the stage's `Results*.txt`
- a case is failed if its case id does not appear there but does exist in the
  matching control-point file(s)

Notes:
- For the initial stage, this script uses `Results_updated.txt` with
  `Control_point_values.dat` (60 cases).
- For infill1, the historical curve-value files exist in both the repo root and
  the `infill1/` subfolder:
  - `input_curve_values.dat`
  - `input_curve_values_extra_20.dat`
  - `infill1/input_curve_values.dat`
  - `infill1/input_curve_values_extra_20.dat`
  This script does not rely on those files; it reconstructs curves from control
  points instead.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

SHOW_PLOTS = True
SAVE_PLOTS = True

import matplotlib

if not SHOW_PLOTS:
    matplotlib.use("Agg")

import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from mpl_toolkits.mplot3d import Axes3D  # noqa: F401
import numpy as np

from x_blade import X_blade


ROOT = Path(__file__).resolve().parent
OUTPUT_DIR = ROOT / "all_curve_plots"

R_PITCH = np.linspace(0.17, 0.998, 300)
R_CHORD = np.linspace(0.17, 0.96, 300)
R_3D = np.linspace(0.17, 0.96, 300)

CONTROL_COLS = 11
PITCH_COLS = 6
ROOT_RADIUS = 0.17
TIP_RADIUS = 0.999
MAX_PITCH_Y4 = 1.4

SUCCESS_COLOR = "green"
FAIL_COLOR = "red"
SUCCESS_ALPHA = 0.35
FAIL_ALPHA = 0.60
SUCCESS_LINEWIDTH = 1.0
FAIL_LINEWIDTH = 1.2


@dataclass(frozen=True)
class StageConfig:
    name: str
    results_file: str
    control_files: tuple[str, ...]
    control_space: str = "design"


@dataclass(frozen=True)
class CurveRecord:
    stage: str
    case_id: int
    status: str
    min_dis: float
    constraint_violation: int
    pitch_vals: np.ndarray
    chord_vals: np.ndarray
    pitch_3d: np.ndarray
    chord_3d: np.ndarray


STAGES: tuple[StageConfig, ...] = (
    StageConfig(
        name="initial",
        results_file="Results_updated.txt",
        control_files=("Control_point_values.dat",),
        control_space="legacy_transformed",
    ),
    StageConfig(
        name="infill1",
        results_file="Results_infill1.txt",
        control_files=(
            "infill_control_points_50.txt",
            "infill_control_points_extra_20.txt",
        ),
    ),
    StageConfig(
        name="infill2",
        results_file="Results_infill2.txt",
        control_files=("infill2_control_points_50.txt",),
    ),
    StageConfig(
        name="infill3",
        results_file="Results_infill3.txt",
        control_files=("infill3_control_points_70.txt",),
    ),
    StageConfig(
        name="infill4",
        results_file="Results_infill4.txt",
        control_files=("infill4_control_points_70.txt",),
    ),
    StageConfig(
        name="infill5",
        results_file="Results_infill5.txt",
        control_files=("infill5_control_points_30.txt",),
    ),
    StageConfig(
        name="infill6",
        results_file="Results_infill6.txt",
        control_files=("infill6_control_points_30.txt",),
    ),
)


def _load_results_table(path: Path) -> np.ndarray:
    """Load a whitespace-delimited results table as a guaranteed 2-D array."""
    try:
        data = np.loadtxt(path, comments="#")
    except ValueError:
        data = np.loadtxt(path, comments="#", skiprows=1)

    if data.ndim == 1:
        data = data.reshape(1, -1)
    return np.asarray(data, dtype=float)


def _load_success_case_ids(path: Path) -> set[int]:
    data = _load_results_table(path)
    if data.size == 0:
        return set()
    if data.shape[1] < 1:
        raise RuntimeError(f"{path.name} does not have a case-id column.")

    case_col = data[:, 0]
    finite_mask = np.isfinite(case_col)
    case_ids = np.unique(np.round(case_col[finite_mask]).astype(int))
    return set(int(v) for v in case_ids)


def _legacy_con_points_to_design_vars(arr: np.ndarray) -> np.ndarray:
    arr = np.asarray(arr, dtype=float)
    if arr.ndim != 2 or arr.shape[1] != CONTROL_COLS:
        raise RuntimeError(
            f"Expected a 2-D legacy control-point array with {CONTROL_COLS} columns, got {arr.shape}"
        )

    pitch_p1y = arr[:, 0]
    pitch_y4 = arr[:, 1]
    pitch_p4x = arr[:, 2]
    pitch_p2x = arr[:, 3]
    pitch_p5x = arr[:, 4]
    pitch_p7y = arr[:, 5]
    chord_p1y = arr[:, 6]
    chord_p4x = arr[:, 7]
    chord_p2x = arr[:, 8]
    chord_y4 = arr[:, 9]
    chord_w56 = arr[:, 10]

    with np.errstate(divide="raise", invalid="raise"):
        pitch_y4_u = (pitch_y4 - pitch_p1y) / (MAX_PITCH_Y4 - pitch_p1y)
        pitch_d1 = (pitch_p4x - pitch_p2x) / (pitch_p4x - ROOT_RADIUS)
        pitch_d2 = (pitch_p5x - pitch_p4x) / (TIP_RADIUS - pitch_p4x)
        chord_d1 = (chord_p4x - chord_p2x) / (chord_p4x - ROOT_RADIUS)

    out = np.column_stack(
        [
            pitch_p1y,
            pitch_y4_u,
            pitch_p4x,
            pitch_d1,
            pitch_d2,
            pitch_p7y,
            chord_p1y,
            chord_p4x,
            chord_d1,
            chord_y4,
            chord_w56,
        ]
    )
    if not np.all(np.isfinite(out)):
        raise RuntimeError("Recovered design variables contain non-finite values.")
    return out


def _load_control_points(stage: StageConfig) -> np.ndarray:
    blocks = []
    for rel_path in stage.control_files:
        path = ROOT / rel_path
        arr = np.loadtxt(path, comments="#")
        if arr.ndim == 1:
            arr = arr.reshape(1, -1)
        if arr.shape[1] != CONTROL_COLS:
            raise RuntimeError(
                f"{path.name} should have {CONTROL_COLS} columns, got {arr.shape[1]}"
            )
        if stage.control_space == "legacy_transformed":
            arr = _legacy_con_points_to_design_vars(arr)
        elif stage.control_space != "design":
            raise RuntimeError(
                f"Unsupported control space '{stage.control_space}' for stage '{stage.name}'."
            )
        blocks.append(np.asarray(arr, dtype=float))

    return np.vstack(blocks)


def _collect_stage_records(stage: StageConfig) -> list[CurveRecord]:
    results_path = ROOT / stage.results_file
    success_case_ids = _load_success_case_ids(results_path)
    control_points = _load_control_points(stage)

    records: list[CurveRecord] = []
    n_cases = int(control_points.shape[0])

    ignored_success_ids = sorted(case_id for case_id in success_case_ids if case_id < 0 or case_id >= n_cases)
    if ignored_success_ids:
        print(
            f"[WARN] {stage.name}: ignoring result case ids outside control-point range: "
            f"{ignored_success_ids}"
        )

    usable_success_ids = {case_id for case_id in success_case_ids if 0 <= case_id < n_cases}

    for case_id in range(n_cases):
        row = np.asarray(control_points[case_id], dtype=float)
        pitch_con = row[:PITCH_COLS]
        chord_con = row[PITCH_COLS:]
        status = "success" if case_id in usable_success_ids else "failed"

        try:
            _, min_dis, constraint_violation, _, _, Pitch, ChordLength = X_blade(
                pitch_con, chord_con, case_id
            )
            pitch_vals = np.asarray(Pitch(R_PITCH), dtype=float)
            chord_vals = np.asarray(ChordLength(R_CHORD), dtype=float)
            pitch_3d = np.asarray(Pitch(R_3D), dtype=float)
            chord_3d = np.asarray(ChordLength(R_3D), dtype=float)
        except Exception as exc:
            print(f"[WARN] {stage.name}: failed to reconstruct case {case_id}: {exc}")
            continue

        records.append(
            CurveRecord(
                stage=stage.name,
                case_id=case_id,
                status=status,
                min_dis=float(min_dis),
                constraint_violation=int(constraint_violation),
                pitch_vals=pitch_vals,
                chord_vals=chord_vals,
                pitch_3d=pitch_3d,
                chord_3d=chord_3d,
            )
        )

    n_success = sum(rec.status == "success" for rec in records)
    n_failed = sum(rec.status == "failed" for rec in records)
    print(
        f"[INFO] {stage.name}: total={len(records)} success={n_success} failed={n_failed} "
        f"(from {stage.results_file})"
    )
    return records


def _plot_all_curves(records: list[CurveRecord]) -> None:
    if not records:
        print("[INFO] No curves available to plot.")
        return

    fig_pitch, ax_pitch = plt.subplots(figsize=(13, 8))
    fig_chord, ax_chord = plt.subplots(figsize=(13, 8))

    for rec in records:
        color = SUCCESS_COLOR if rec.status == "success" else FAIL_COLOR
        alpha = SUCCESS_ALPHA if rec.status == "success" else FAIL_ALPHA
        linewidth = SUCCESS_LINEWIDTH if rec.status == "success" else FAIL_LINEWIDTH

        ax_pitch.plot(R_PITCH, rec.pitch_vals, color=color, alpha=alpha, linewidth=linewidth)
        ax_chord.plot(R_CHORD, rec.chord_vals, color=color, alpha=alpha, linewidth=linewidth)

    success_count = sum(rec.status == "success" for rec in records)
    # failed_count = sum(rec.status == "failed" for rec in records)
    failed_count = 0

    ax_pitch.set_title(
        f"All Pitch Curves | success={success_count} | failed={failed_count}"
    )
    ax_pitch.set_xlabel("radius")
    ax_pitch.set_ylabel("pitch")
    ax_pitch.grid(True, alpha=0.35)

    ax_chord.set_title(
        f"All Chord Curves | success={success_count} | failed={failed_count}"
    )
    ax_chord.set_xlabel("radius")
    ax_chord.set_ylabel("chord")
    ax_chord.grid(True, alpha=0.35)

    legend_handles = [
        Line2D([0], [0], color=SUCCESS_COLOR, linewidth=2.0, label="successful case"),
        Line2D([0], [0], color=FAIL_COLOR, linewidth=2.0, label="failed case"),
    ]
    ax_pitch.legend(handles=legend_handles)
    ax_chord.legend(handles=legend_handles)

    fig_pitch.tight_layout()
    fig_chord.tight_layout()

    if SAVE_PLOTS:
        fig_pitch.savefig(OUTPUT_DIR / "all_pitch_curves_success_green_failed_red.png", dpi=180, bbox_inches="tight")
        fig_chord.savefig(OUTPUT_DIR / "all_chord_curves_success_green_failed_red.png", dpi=180, bbox_inches="tight")

    if SHOW_PLOTS:
        plt.show()

    plt.close(fig_pitch)
    plt.close(fig_chord)


def _plot_all_curves_3d(records: list[CurveRecord]) -> None:
    if not records:
        print("[INFO] No curves available to plot in 3D.")
        return

    fig = plt.figure(figsize=(13, 9))
    ax = fig.add_subplot(111, projection="3d")

    for rec in records:
        color = SUCCESS_COLOR if rec.status == "success" else FAIL_COLOR
        alpha = SUCCESS_ALPHA if rec.status == "success" else FAIL_ALPHA
        linewidth = SUCCESS_LINEWIDTH if rec.status == "success" else FAIL_LINEWIDTH

        ax.plot(
            R_3D,
            rec.pitch_3d,
            rec.chord_3d,
            color=color,
            alpha=alpha,
            linewidth=linewidth,
        )

    success_count = sum(rec.status == "success" for rec in records)
    failed_count = sum(rec.status == "failed" for rec in records)

    ax.set_title(
        f"All Curves in 3D (r, p, c) | success={success_count} | failed={failed_count}"
    )
    ax.set_xlabel("radius")
    ax.set_ylabel("pitch")
    ax.set_zlabel("chord")

    legend_handles = [
        Line2D([0], [0], color=SUCCESS_COLOR, linewidth=2.0, label="successful case"),
        Line2D([0], [0], color=FAIL_COLOR, linewidth=2.0, label="failed case"),
    ]
    ax.legend(handles=legend_handles)

    if SAVE_PLOTS:
        fig.savefig(
            OUTPUT_DIR / "all_curves_3d_rpc_success_green_failed_red.png",
            dpi=180,
            bbox_inches="tight",
        )

    if SHOW_PLOTS:
        plt.show()

    plt.close(fig)


def _write_manifest(records: list[CurveRecord]) -> None:
    lines = ["stage\tcase_id\tstatus\tmin_dis\tconstraint_violation"]
    for rec in records:
        lines.append(
            f"{rec.stage}\t{rec.case_id}\t{rec.status}\t"
            f"{rec.min_dis:.10g}\t{rec.constraint_violation}"
        )

    manifest_path = OUTPUT_DIR / "curve_case_status_manifest.tsv"
    manifest_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[WROTE] {manifest_path}")


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    all_records: list[CurveRecord] = []
    for stage in STAGES:
        all_records.extend(_collect_stage_records(stage))

    _plot_all_curves(all_records)
    _plot_all_curves_3d(all_records)
    _write_manifest(all_records)


if __name__ == "__main__":
    main()
