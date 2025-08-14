# -------------------------------------------------------------
# build_edge_cases_v3.py   (base + все однофакторные комбинации)
# -------------------------------------------------------------
from pathlib import Path
import re, shutil, sys

# ------------------ ПУТИ ------------------
TEMPLATE_DIR  = Path(r"D:\MsProject")
TEMPLATE_DATA = TEMPLATE_DIR / "Egg_Model_ECL.DATA"
INC_FILES     = ["ACTIVE.INC", "mDARCY.INC"]
OUTPUT_ROOT   = Path(r"D:\MsProject\edge_cases")

# ------------------ НАБОРЫ ЗНАЧЕНИЙ ------------------
bhp_vals  = [395]                                   # бар
skin_vals = [-2, -1, 0, 1, 2]
qinj_vals = [79.5]                                  # м³/сут
so_vals   = [0.80, 0.82, 0.84, 0.86, 0.88,
             0.90, 0.92, 0.94, 0.96, 0.98]
p_vals    = [400]                                   # бар

# ------------------ БАЗОВЫЕ ИНДЕКСЫ ------------------
# Явно указываем базовые элементы в каждом списке:
i_bhp, i_skin, i_qinj, i_so, i_p = 0, 2, 0, 5, 0

# Валидация индексов
lists = [bhp_vals, skin_vals, qinj_vals, so_vals, p_vals]
ibase = [i_bhp, i_skin, i_qinj, i_so, i_p]
for name, arr, i in zip(["BHP","skin","Qinj","SO","P"], lists, ibase):
    if not (0 <= i < len(arr)):
        sys.exit(f"Базовый индекс {name}={i} вне диапазона (0..{len(arr)-1}).")

# ------------------ ПАТЧЕРЫ ------------------
def replace_soil_swat(txt: str, so_init: float) -> str:
    sw_init = 1.0 - so_init
    txt = re.sub(r"(SOIL\s*\n\s*\d+\*)\s*[\d.]+\s*/",
                 rf"\g<1>{so_init:.2f} /", txt, count=1, flags=re.I)
    txt = re.sub(r"(SWAT\s*\n\s*\d+\*)\s*[\d.]+\s*/",
                 rf"\g<1>{sw_init:.2f} /", txt, count=1, flags=re.I)
    return txt

def replace_pressure(txt: str, p_init: int) -> str:
    out, in_block = [], False
    for ln in txt.splitlines(keepends=True):
        up = ln.upper().lstrip()
        if up.startswith("PRESSURE"):
            in_block = True; out.append(ln); continue
        if in_block:
            if ln.strip().startswith('/'):
                in_block = False; out.append(ln); continue
            ln = re.sub(r"(\d+\*)\s*[\d.]+", rf"\g<1>{p_init}", ln)
        out.append(ln)
    return "".join(out)

def replace_wconprod(txt: str, bhp: int) -> str:
    return re.sub(r"('BHP'\s+5\*\s+)\d+", rf"\g<1>{bhp}", txt, flags=re.I)

def replace_wconinje(txt: str, qinj: float) -> str:
    return re.sub(r"('RATE'\s+)\d+(\.\d+)?",
                  rf"\g<1>{qinj}", txt, flags=re.I)

def patch_compdat_block(txt: str, skin: int) -> str:
    lines, out, in_block = txt.splitlines(keepends=True), [], False
    for ln in lines:
        if ln.upper().lstrip().startswith("COMPDAT"):
            in_block = True; out.append(ln); continue
        if in_block:
            if ln.strip().startswith('/'):
                in_block = False; out.append(ln); continue
            if "'PROD" in ln.upper():
                before, after = ln.rsplit('/', 1)
                before = re.sub(r"(-?\d+(?:\.\d*)?)\s*$", f"{skin} ", before)
                ln = before + '/' + after
        out.append(ln)
    return "".join(out)

def patch_data_file(src: Path, dst: Path, so, pin, skin, bhp, qinj):
    txt = src.read_text(encoding="utf-8")
    txt = replace_soil_swat(txt, so)
    txt = replace_pressure(txt, pin)
    txt = replace_wconprod(txt, bhp)
    txt = replace_wconinje(txt, qinj)
    txt = patch_compdat_block(txt, skin)
    dst.write_text(txt, encoding="utf-8")

# ------------------ ФОРМИРОВАНИЕ СЕТКИ ------------------
base = (bhp_vals[i_bhp], skin_vals[i_skin], qinj_vals[i_qinj],
        so_vals[i_so],   p_vals[i_p])

# «База + все однофакторные отклонения»:
param_lists = [bhp_vals, skin_vals, qinj_vals, so_vals, p_vals]
param_grid = [base]
for param_idx, arr in enumerate(param_lists):
    base_idx = ibase[param_idx]
    for j, v in enumerate(arr):
        if j == base_idx:  # пропускаем базу
            continue
        t = list(base)
        t[param_idx] = v
        param_grid.append(tuple(t))

# ------------------ ПРОВЕРКИ ПЕРЕД ЗАПУСКОМ ------------------
def differs_by_one(a, b):
    return sum(1 for x, y in zip(a, b) if x != y) == 1

expected_n = 1 + sum(max(0, len(arr) - 1) for arr in param_lists)
assert len(param_grid) == expected_n, (len(param_grid), expected_n)
assert all(differs_by_one(base, t) for t in param_grid[1:]), "Нарушено правило: изменяется ровно один параметр."

# ------------------ СОЗДАНИЕ ПАПОК И ФАЙЛОВ ------------------
OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)

for run_id, (bhp, skin, qinj, so, pin) in enumerate(param_grid, 1):
    run_dir = OUTPUT_ROOT / f"run_{run_id:03d}"
    run_dir.mkdir(exist_ok=True)
    for inc in INC_FILES:
        shutil.copy2(TEMPLATE_DIR / inc, run_dir / inc)

    dst = run_dir / TEMPLATE_DATA.name
    patch_data_file(TEMPLATE_DATA, dst, so, pin, skin, bhp, qinj)

    print(f"✓ {run_dir.name}: SO={so:.2f}, P={pin}, skin={skin}, BHP={bhp}, Qinj={qinj}")

print(f"\nГотово. Создано {len(param_grid)} кейсов (ожидалось {expected_n}).")
