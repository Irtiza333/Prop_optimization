import numpy as np
from pathlib import Path
import os

N = list(range(0,300))

failed_cases = []
ok_cases = []
ok_cad_files = []
failed_cad_files = []

for i in N:
    case = f"ORCA_gridsample_blade{i}.cas"
    cad_file = f"sample_blade{i}.iges"
    if os.path.exists(case):
        ok_cases.append(i)
    else:
        failed_cases.append(i)

    if os.path.exists(cad_file):
        ok_cad_files.append(i)
    else:
        failed_cad_files.append(i)

print(ok_cases)
print(failed_cases)
print(ok_cad_files)
print(failed_cad_files)

print(len(ok_cases))
print(len(failed_cases))
print(len(ok_cad_files))
print(len(failed_cad_files))