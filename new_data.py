# -*- coding: utf-8 -*-
"""
make_bhp_case_set.py
--------------------
Создаёт кейсы BHP_XXX:
  • правит .DATA (INCLUDE → 'INCLUDE/…');
  • копирует только mDARCY.INC и ACTIVE.INC в подпапку INCLUDE;
  • генерирует schedule_BHP_XXX.inc из шаблона schedule_test.inc, меняя только BHP.
"""

import argparse
import pathlib
import re
import shutil
import sys
from typing import List

EXTRA_DEFAULT = ["mDARCY.INC", "ACTIVE.INC"]  
TARGET_INCLUDE = "schedule_test.inc"          # что ищем в .DATA

# -------------------- функции -------------------------------------------

def rewrite_include_line(line: str) -> str:
    """
    Если строка указывает на *.INC без 'INCLUDE/', дописываем 'INCLUDE/…'.
    """
    m = re.search(r"^(\s*)([A-Za-z0-9._-]+\.(?:INC|inc))(.*)$", line)
    if not m:
        return line
    indent, fname, tail = m.groups()
    if "INCLUDE/" in line:
        return line
    return f"{indent}'INCLUDE/{fname}'{tail}\n"


def patch_data(lines: List[str], num: int, prefix: str) -> List[str]:
    """
    В .DATA заменяем ссылку на шаблонный schedule_test.inc на конкретный schedule_BHP_XXX.inc.
    Все прочие INCLUDE-строки дополняем префиксом 'INCLUDE/' при необходимости.
    """
    sched_token = f"'INCLUDE/schedule_{prefix}_{num:03d}.inc'"
    patched = []
    for ln in lines:
        if TARGET_INCLUDE in ln:
            indent = ln[: len(ln) - len(ln.lstrip())]
            tail = " /" if "/" in ln else ""
            patched.append(f"{indent}{sched_token}{tail}\n")
        else:
            patched.append(rewrite_include_line(ln))
    return patched


def write_schedule_from_template(tmpl_text: str, num: int, dst: pathlib.Path) -> None:
    """
    В шаблоне schedule_test.inc заменяем ПЕРВОЕ число после 'BHP' на `num`.
    Пример шаблона (фрагмент):
        WCONPROD
            'PROD1' 'OPEN' 'BHP' 5* 450 /
        /
    Регулярка ниже заменит только первое вхождение.
    """
    replacement = rf"\g<1>{num}"
    content = re.sub(r"('BHP'\s+\d*\*?\s*)\d+", replacement, tmpl_text, count=1, flags=re.I)
    # Если у вас формат типа:  'BHP' 5* 450  — тоже сработает (захватывает '5* ' как опциональный блок).
    dst.write_text(content, encoding="utf-8")


def copy_file(src: pathlib.Path, dst_dir: pathlib.Path) -> None:
    if not src.is_file():
        sys.exit(f"Не найден файл: {src}")
    shutil.copy2(src, dst_dir)

# -------------------- основной код --------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser("Генерация BHP‑кейсов")
    ap.add_argument("--data", required=True, type=pathlib.Path, help="исходный .DATA")
    ap.add_argument(
        "--tmpl",
        type=pathlib.Path,
        default=None,
        help="шаблон schedule_test.inc (по умолчанию рядом с .DATA)",
    )
    ap.add_argument(
        "--out",
        "-o",
        type=pathlib.Path,
        default=None,
        help="корневая папка для BHP_XXX",
    )
    ap.add_argument(
        "--extra",
        "-e",
        type=pathlib.Path,
        default=None,
        help="папка с mDARCY.INC и ACTIVE.INC",
    )
    ap.add_argument(
        "--prefix", "-p", default="BHP", help="префикс папок и schedule‑файлов"
    )
    # Диапазон BHP по умолчанию: 390..399 с шагом 1
    ap.add_argument("--start", type=int, default=390)
    ap.add_argument("--stop",  type=int, default=399)
    ap.add_argument("--step",  type=int, default=1)
    args = ap.parse_args()

    base_data = args.data.resolve()
    if not base_data.is_file():
        sys.exit(f".DATA не найден: {base_data}")

    tmpl_path = (args.tmpl or (base_data.parent / "schedule_test.inc")).resolve()
    if not tmpl_path.is_file():
        sys.exit(f"Шаблон schedule_test.inc не найден: {tmpl_path}")
    tmpl_text = tmpl_path.read_text(encoding="utf-8")

    out_root = (args.out or base_data.parent).resolve()
    extra_dir = (args.extra or base_data.parent).resolve()

    extra_paths = [extra_dir / f for f in EXTRA_DEFAULT]
    for p in extra_paths:
        if not p.is_file():
            sys.exit(f"Нет файла {p}")

    data_lines = base_data.read_text(encoding="utf-8", errors="ignore").splitlines(keepends=True)

    for num in range(args.start, args.stop + 1, args.step):
        tag = f"{args.prefix}_{num:03d}"
        case_dir = out_root / tag
        include_dir = case_dir / "INCLUDE"
        include_dir.mkdir(parents=True, exist_ok=True)

        # 1) .DATA (подмена schedule и нормализация INCLUDE путей)
        patched = patch_data(data_lines, num, args.prefix)
        (case_dir / base_data.name).write_text("".join(patched), encoding="utf-8")

        # 2) копируем только необходимые *.INC
        for p in extra_paths:
            copy_file(p, include_dir)

        # 3) генерируем schedule_BHP_XXX.inc из шаблона, меняем только BHP
        sched_file = include_dir / f"schedule_{args.prefix}_{num:03d}.inc"
        write_schedule_from_template(tmpl_text, num, sched_file)

        print(f"✓ {tag}")

if __name__ == "__main__":
    main()
