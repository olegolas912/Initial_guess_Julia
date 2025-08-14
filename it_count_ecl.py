from pathlib import Path
import re

# ---------- ПУТЬ К PRT-ФАЙЛУ ----------
PRT_FILE = r"D:\convergance_tests\orig-Copy\EGG_MODEL_ECL.PRT"
# --------------------------------------

re_its = re.compile(r"\b(\d+)\s+ITS\)")
re_linit = re.compile(r"LINIT=\s*(\d+)\b")
re_step = re.compile(r"\bSTEP\s+\d+\b")

newton_iters = 0
linear_iters = 0
steps = 0

for line in Path(PRT_FILE).read_text(encoding="utf-8", errors="ignore").splitlines():
    if m := re_its.search(line):
        newton_iters += int(m.group(1))
    if m := re_linit.search(line):
        linear_iters += int(m.group(1))
    if re_step.search(line):
        steps += 1

print(f"Non-linear iterations (ITS): {newton_iters}")
print(f"Linear   iterations (LINIT): {linear_iters}")
print(f"Time-steps (STEP lines)    : {steps}")
