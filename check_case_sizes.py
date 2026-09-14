from pathlib import Path


threshold_kb = 700000
small_cases = []
missing_cases = []

for i in range(200):
    case_file = Path(f"ORCA_gridsample_blade{i}.cas")

    if not case_file.exists():
        missing_cases.append(i)
        continue

    size_kb = (case_file.stat().st_size + 1023) // 1024
    if size_kb < threshold_kb:
        small_cases.append((i, size_kb))

print(f"Cases below {threshold_kb} KB:")
for case_id, size_kb in small_cases:
    print(f"{case_id}: {size_kb} KB")

print("\nMissing cases:")
print(missing_cases)
