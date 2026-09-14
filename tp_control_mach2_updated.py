# tp_control_mach2_updated.py
import os
import sys
import numpy as np
from concurrent.futures import ProcessPoolExecutor, as_completed

from CFD_workflow_mach2 import CFD_workflow  # per-case GLF/PRE + per-case post temp




# WORKER (top-level, picklable) 
def _run_one_pack(args):
    """
    Worker: runs one CFD case.
    Returns (idx, row) or raises so the parent prints the exception.
    """
    idx_pt, dX_c, dY_c, beta, N_iter, work_dir, n_procs = args
    prefix = f"/CFD/iter{N_iter}_idx{idx_pt}_Dxc{dX_c:.6f}_Dyc{dY_c:.6f}_B{beta:.6f}"
    CL, CD = CFD_workflow(
        dX_c, dY_c, beta,
        work_dir=work_dir,
        prefix=prefix,
        n_procs=n_procs
    )
    return idx_pt, [dX_c, dY_c, beta, float(CL), float(CD)]


def Get_CL_CD(train_pts,
              N_iter: int,
              n_workers: int,
              n_procs: int,
              work_dir: str):
    train_pts = np.asarray(train_pts, dtype=float)
    n_train_pts = train_pts.shape[0]
    max_workers = max(1, min(int(n_workers), n_train_pts))

    print(f"[INFO] Submitting {n_train_pts} cases (concurrency={max_workers}, ranks/job={n_procs})")

    if n_train_pts == 0:
        out_name = f"CL_CD_Data_retrain{N_iter}.txt"
        np.savetxt(out_name, np.empty((0, 5)),
                   header="dX/c   dY/c   beta   CL   CD", fmt="%.10g")
        print(f"[WARN] No samples. Wrote empty file: {out_name}", flush=True)
        return np.empty((0, 5))

    
    tasks = [
        (i, float(train_pts[i, 0]), float(train_pts[i, 1]), float(train_pts[i, 2]),N_iter,
         work_dir, int(n_procs))
        for i in range(n_train_pts)
    ]

    results_by_idx = {}

    # Submit and consume futures
    with ProcessPoolExecutor(max_workers=max_workers) as ex:
        futs = [ex.submit(_run_one_pack, t) for t in tasks]
        for fu in as_completed(futs):
            try:
                idx, row = fu.result()
                results_by_idx[idx] = row
                # print(f"[OK] Finished idx={idx} -> CL={row[3]}, CD={row[4]}", flush=True)
            except Exception as e:
                # Print the exception immediately (no silent failure)
                print(f"[ERROR] Worker failed: {repr(e)}", file=sys.stderr)
                # Optional: re-raise if you want to abort the whole batch
                # raise

    # restore original order
    rows = [results_by_idx[i] for i in range(n_train_pts) if i in results_by_idx]
    iter_results = np.asarray(rows) if rows else np.empty((0, 5))

    out_name = f"CL_CD_Data_retrain{N_iter}.txt"
    np.savetxt(out_name, iter_results,
               header="dX/c   dY/c   beta   CL   CD", fmt="%.10g")
    print(f"[INFO] Wrote {iter_results.shape[0]} rows to {out_name}", flush=True)

    return iter_results


