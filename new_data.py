# -------------------------------------------------------------
# build_32_cases.py (версия без COMPDAT.INC)
# -------------------------------------------------------------
from pathlib import Path
import itertools
import re
import shutil

# ------------------ НАСТРОЙКИ ПОЛЬЗОВАТЕЛЯ ------------------
TEMPLATE_DIR  = Path(r"D:\t_nav_models\egg")          # где лежит исходный .DATA
TEMPLATE_DATA = TEMPLATE_DIR / "Egg_Model_ECL.DATA"

INC_FILES   = ["ACTIVE.INC", "mDARCY.INC"]            # COMPDAT.INC убрали
OUTPUT_ROOT = Path(r"D:\convergance_tests\cases_32")  # куда класть результаты
# -------------------------------------------------------------

# ------------------ СЕТКА ПАРАМЕТРОВ ------------------------
so_vals   = [0.80, 0.98]
p_vals    = [350, 450] 
skin_vals = [-2,  2]   
bhp_vals  = [350, 440]
qinj_vals = [40, 120]
param_grid = list(itertools.product(bhp_vals, skin_vals,
                                    qinj_vals, so_vals, p_vals))

# ------------------- ФУНКЦИИ-ПАТЧЕРЫ ------------------------
def replace_soil_swat(txt: str, so_init: float) -> str:
    sw_init = 1.0 - so_init
    txt = re.sub(r"(SOIL\s*\n\s*\d+\*)\s*[\d.]+\s*/",
                 rf"\g<1>{so_init:.2f} /", txt, 1, flags=re.I)
    txt = re.sub(r"(SWAT\s*\n\s*\d+\*)\s*[\d.]+\s*/",
                 rf"\g<1>{sw_init:.2f} /", txt, 1, flags=re.I)
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

def replace_wconinje(txt: str, qinj: int) -> str:
    return re.sub(r"('RATE'\s+)\d+", rf"\g<1>{qinj}", txt, flags=re.I)

def patch_compdat_block(txt: str, skin: int) -> str:
    """Меняет skin-factor у PROD-скважин в блоке COMPDAT."""
    lines, out, in_block = txt.splitlines(keepends=True), [], False
    for ln in lines:
        if ln.upper().lstrip().startswith("COMPDAT"):
            in_block = True
            out.append(ln); continue
        if in_block:
            if ln.strip().startswith('/'):
                in_block = False
                out.append(ln); continue
            if "'PROD" in ln.upper():
                before, after = ln.rsplit('/', 1)
                before = re.sub(r"(-?\d+(?:\.\d*)?)\s*$", f"{skin} ", before)
                ln = before + '/' + after
        out.append(ln)
    return "".join(out)

def patch_data_file(src: Path, dst: Path,
                    so, p_init, skin, bhp, qinj):
    txt = src.read_text(encoding="utf-8")
    txt = replace_soil_swat(txt, so)
    txt = replace_pressure(txt, p_init)
    txt = replace_wconprod(txt, bhp)
    txt = replace_wconinje(txt, qinj)
    txt = patch_compdat_block(txt, skin)         # ← патчим COMPDAT
    dst.write_text(txt, encoding="utf-8")

# --------------------- ОСНОВНОЙ ЦИКЛ ------------------------
OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)

for run_id, (bhp, skin, qinj, so, p_init) in enumerate(param_grid, 1):
    run_dir = OUTPUT_ROOT / f"run_{run_id:03d}"
    run_dir.mkdir(exist_ok=True)

    # копируем необходимые *.INC
    for inc in INC_FILES:
        shutil.copy2(TEMPLATE_DIR / inc, run_dir / inc)

    # создаём и патчим основной .DATA
    dst = run_dir / TEMPLATE_DATA.name
    patch_data_file(TEMPLATE_DATA, dst, so, p_init, skin, bhp, qinj)

    print(f"✓ {run_dir.name}: SO={so:.2f}, P={p_init}, "
          f"skin={skin}, BHP={bhp}, Qinj={qinj}")

print("\nВсе 32 случая успешно созданы.")
