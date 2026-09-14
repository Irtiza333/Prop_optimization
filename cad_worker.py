"""
Isolated single-case CAD generation worker.

Run as a subprocess so a hang or crash inside pythonOCC (which cannot be
interrupted from Python because it is C code) only affects one case and can be
killed via a subprocess timeout instead of blocking the whole batch.

Usage:
    python cad_worker.py <case_id> <geometry_dir> <points_npy>
"""

import sys
from pathlib import Path

import numpy as np


def main():
    if len(sys.argv) != 4:
        print("usage: python cad_worker.py <case_id> <geometry_dir> <points_npy>")
        return 2

    case_id = int(sys.argv[1])
    geometry_dir = Path(sys.argv[2])
    points_path = Path(sys.argv[3])

    points = np.load(points_path)

    import para
    para.GEOMETRY_OUTPUT_DIR = geometry_dir
    from X_CAD import X_CAD

    X_CAD(points, case_id, output_dir=geometry_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
