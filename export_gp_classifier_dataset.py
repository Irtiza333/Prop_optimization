"""
Export a single table of all design inputs (control points) with a binary label
for Gaussian-process (or other) classifiers.

Label column `failed`:
  1 = case failed (case id not present in that stage's Results*.txt)
  0 = case generated successfully (case id present in Results*.txt)

Same success/failure rule as plot_failed_pitch_chord_curves.py.
Rows are not filtered by X_blade; every control-point row is included.
"""

from __future__ import annotations

import csv
from pathlib import Path

import numpy as np

from plot_failed_pitch_chord_curves import (
    CONTROL_COLS,
    PITCH_COLS,
    ROOT,
    STAGES,
    _load_control_points,
    _load_success_case_ids,
)

OUTPUT_CSV = ROOT / "gp_classifier_dataset.csv"


def main() -> None:
    n_pitch = PITCH_COLS
    n_chord = CONTROL_COLS - PITCH_COLS
    pitch_headers = [f"pitch_cp_{i}" for i in range(n_pitch)]
    chord_headers = [f"chord_cp_{i}" for i in range(n_chord)]
    fieldnames = (
        ["stage", "stage_id", "case_id"]
        + pitch_headers
        + chord_headers
        + ["failed"]
    )

    rows: list[dict[str, str | int | float]] = []
    for stage_id, stage in enumerate(STAGES):
        results_path = ROOT / stage.results_file
        success_case_ids = _load_success_case_ids(results_path)
        control_points = _load_control_points(stage)
        n_cases = int(control_points.shape[0])
        usable_success_ids = {
            case_id for case_id in success_case_ids if 0 <= case_id < n_cases
        }

        for case_id in range(n_cases):
            row_vals = np.asarray(control_points[case_id], dtype=float)
            failed = 0 if case_id in usable_success_ids else 1
            rec: dict[str, str | int | float] = {
                "stage": stage.name,
                "stage_id": stage_id,
                "case_id": case_id,
                "failed": failed,
            }
            for i, name in enumerate(pitch_headers):
                rec[name] = float(row_vals[i])
            for j, name in enumerate(chord_headers):
                rec[name] = float(row_vals[n_pitch + j])
            rows.append(rec)

    OUTPUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_CSV.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    n_fail = sum(int(r["failed"]) for r in rows)
    n_ok = len(rows) - n_fail
    print(f"[WROTE] {OUTPUT_CSV}  rows={len(rows)} failed={n_fail} generated={n_ok}")


if __name__ == "__main__":
    main()
