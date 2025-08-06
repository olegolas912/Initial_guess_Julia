# -------------------------------------------------------------
# build_edge_cases_v2.py   (base + 5 однофакторных варианта)
# -------------------------------------------------------------
from pathlib import Path
import re, shutil

# ------------------ ПУТИ ------------------
TEMPLATE_DIR  = Path(r"D:\t_nav_models\egg")
TEMPLATE_DATA = TEMPLATE_DIR / "Egg_Model_ECL.DATA"
INC_FILES     = ["ACTIVE.INC", "mDARCY.INC"]
OUTPUT_ROOT   = Path(r"D:\convergance_tests\edge_cases")

# --------- ЗАДАЁМ low / base / high ----------
so_vals   = [0.80, 0.90, 0.98]     # вода 0.20 / 0.10 / 0.02
p_vals    = [350, 400, 450]        # бар
skin_vals = [-2,   0,   2]
bhp_vals  = [350, 395, 440]        # бар
qinj_vals = [40,  79.5, 120]       # м³/сут

# базовая пятёрка (индекс 1 = base)
base = (bhp_vals[1], skin_vals[1], qinj_vals[1], so_vals[1], p_vals[1])

def variant(idx_param: int, to_high: bool):
    """смещаем один параметр к low (False) или high (True)"""
    bhp, skin, qinj, so, pin = base
    if   idx_param == 0: bhp  = bhp_vals[2 if to_high else 0]
    elif idx_param == 1: skin = skin_vals[2 if to_high else 0]
    elif idx_param == 2: qinj = qinj_vals[2 if to_high else 0]
    elif idx_param == 3: so   = so_vals  [2 if to_high else 0]
    elif idx_param == 4: pin  = p_vals   [2 if to_high else 0]
    return (bhp, skin, qinj, so, pin)

# формируем: base + 5 «high» смещений + 5 «low» смещений
param_grid = [base] + [variant(i, True) for i in range(0, 5)] + [variant(i, False) for i in range(0, 5)]
# итого 11 файлов

# ---------------- ПАТЧЕРЫ (без изменений, count=) -------------
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
            in_block = True
            out.append(ln); continue
        if in_block:
            if ln.strip().startswith('/'):
                in_block = False
                out.append(ln); continue
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

# -------------------- СОЗДАНИЕ ПАПОК -------------------------
OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
for run_id, (bhp, skin, qinj, so, pin) in enumerate(param_grid, 1):
    run_dir = OUTPUT_ROOT / f"run_{run_id:03d}"
    run_dir.mkdir(exist_ok=True)
    for inc in INC_FILES:
        shutil.copy2(TEMPLATE_DIR / inc, run_dir / inc)
    dst = run_dir / TEMPLATE_DATA.name
    patch_data_file(TEMPLATE_DATA, dst, so, pin, skin, bhp, qinj)
    print(f"✓ {run_dir.name}: SO={so:.2f}, P={pin}, skin={skin}, BHP={bhp}, Qinj={qinj}")

print(f"\nГотово: создано {len(param_grid)} краевых комбинаций.")
