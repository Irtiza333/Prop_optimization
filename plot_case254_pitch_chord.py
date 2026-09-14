"""Plot pitch and chord distributions for best CFD case (case 254, eta~0.5404)."""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

from para_control_bez_updated import para_control_bez_updated

ROOT = Path(__file__).resolve().parent
OUT_DIR = ROOT / "New_training"
CASE_ID = 254
DESIGN_VARS = np.array(
    [0.791976, 0.561425, 0.350000, 0.085144, 0.500000, 0.583290,
     0.150000, 0.536295, 0.050000, 0.414897, 0.050000],
    dtype=float,
)
ETA = 0.540391
J_OPT = 0.568385


def original_pitch(x):
    return (
        19344.5071 * x**12 - 114044.8587 * x**11 + 280789.2801 * x**10
        - 357377.6146 * x**9 + 207947.2705 * x**8 + 43330.8173 * x**7
        - 173099.4797 * x**6 + 143116.5772 * x**5 - 65570.9523 * x**4
        + 18410.2055 * x**3 - 3128.7530 * x**2 + 294.0671 * x - 10.4419
    )


def original_chord(x):
    return (
        -143202.4761 * x**12 + 978274.9902 * x**11 - 2992184.0323 * x**10
        + 5408923.9625 * x**9 - 6424276.8851 * x**8 + 5271614.6993 * x**7
        - 3058632.5267 * x**6 + 1261908.7720 * x**5 - 366745.1423 * x**4
        + 73096.4455 * x**3 - 9470.1908 * x**2 + 716.1619 * x - 23.7157
    )


def tip_biased_spacing(a, b, n):
    t = np.linspace(0.0, 1.0, n)
    return a + (b - a) * np.sin(0.5 * np.pi * t)


def main():
    pitch_con, chord_con = DESIGN_VARS[:6], DESIGN_VARS[6:]
    r_grid = np.concatenate([np.arange(0.17, 0.985, 0.018), [0.99, 0.999]])
    pitch_fn, chord_fn, _, _ = para_control_bez_updated(
        original_pitch, original_chord, r_grid, 7, pitch_con, chord_con,
        case_id=CASE_ID, constraint_mode="project",
    )

    r_smooth = np.linspace(0.17, 1.0, 400)
    r_pts = tip_biased_spacing(0.20, 0.99, 70)
    pitch_pts = np.asarray(pitch_fn(r_pts), dtype=float)
    chord_pts = np.asarray(chord_fn(r_pts), dtype=float)

    pitch_y4 = pitch_con[0] + (1.4 - pitch_con[0]) * pitch_con[1]
    print(f"Case {CASE_ID}: eta={ETA:.4f}, J*={J_OPT:.4f}")
    print(
        f"  pitch: p1y={pitch_con[0]:.4f}, y4_frac={pitch_con[1]:.4f} (-> y4={pitch_y4:.4f}), "
        f"p4x={pitch_con[2]:.4f}, d1={pitch_con[3]:.4f}, d2={pitch_con[4]:.4f}, p7y={pitch_con[5]:.4f}"
    )
    print(
        f"  chord: p1y={chord_con[0]:.4f}, p4x={chord_con[1]:.4f}, "
        f"d1={chord_con[2]:.4f}, y4={chord_con[3]:.4f}, w56={chord_con[4]:.4f}"
    )

    fig, axes = plt.subplots(1, 2, figsize=(14, 5.5))
    label = f"Case {CASE_ID} (η={ETA:.4f})"

    axes[0].plot(r_smooth, original_pitch(r_smooth), "k--", lw=2.2, label="Original")
    axes[0].plot(r_pts, pitch_pts, "o-", color="#d62728", ms=4, lw=1.5, label=label)
    axes[0].set_title("Pitch Distribution")
    axes[0].set_ylabel("Pitch / Diameter [-]")

    axes[1].plot(r_smooth, original_chord(r_smooth), "k--", lw=2.2, label="Original")
    axes[1].plot(r_pts, chord_pts, "o-", color="#d62728", ms=4, lw=1.5, label=label)
    axes[1].set_title("Chord Distribution")
    axes[1].set_ylabel("Chord / Diameter [-]")

    for ax in axes:
        ax.set_xlabel("Normalized Radius [-]")
        ax.set_xlim(0.17, 1.0)
        ax.grid(True, alpha=0.3)
        ax.legend(frameon=True, framealpha=0.9)

    fig.suptitle(f"Best CFD Case so far — Case {CASE_ID}", fontsize=14, y=0.98)
    fig.tight_layout(rect=[0, 0, 1, 0.94])
    out = OUT_DIR / f"case_{CASE_ID}_pitch_chord.png"
    fig.savefig(out, dpi=200)
    print(f"Wrote {out}")
    plt.show()


if __name__ == "__main__":
    main()
