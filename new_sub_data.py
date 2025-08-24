from pathlib import Path
import re
import argparse
from typing import Optional, List, Tuple

# Ищем блок:
# TSTEP
#     X Y Z /
TSTEP_RX = re.compile(r"(TSTEP\s*\n\s*)(\d+)\s+(\d+)(\s+\d+\s*/)", re.I)


def find_base_data_file(folder: Path) -> Optional[Path]:
    """
    Возвращает исходный .DATA без суффикса '_TSTEP_…', чтобы не брать
    сгенерированные ранее файлы.
    """
    candidates = sorted(folder.glob("*.DATA"))
    for f in candidates:
        if "_TSTEP_" not in f.stem:
            return f
    return candidates[0] if candidates else None


def build_variations(template_text: str, total: int,
                     a_min: int, a_max: int, a_step: int) -> List[Tuple[int, int, str]]:
    """
    Возвращает список (a, b, modified_text) для всех a ∈ [a_min, a_max] с шагом a_step,
    при b = total - a. Меняется только первая строка после TSTEP, остальные данные неизменны.
    """
    if a_step <= 0:
        raise ValueError("Шаг перебора a_step должен быть положительным.")
    if total <= 1:
        raise ValueError("Параметр total должен быть > 1.")

    m = TSTEP_RX.search(template_text)
    if not m:
        raise ValueError("В файле не найден корректный блок TSTEP с тремя числами.")

    # Нормализуем границы: 1 ≤ a ≤ total-1
    a_min = max(1, a_min)
    a_max = min(total - 1, a_max)
    if a_min > a_max:
        return []

    prefix, _, _, suffix = m.groups()
    out: List[Tuple[int, int, str]] = []
    for a in range(a_min, a_max + 1, a_step):
        b = total - a
        if a <= 0 or b <= 0:
            continue
        replacement = f"{prefix}{a} {b}{suffix}"
        modified = TSTEP_RX.sub(replacement, template_text, count=1)
        out.append((a, b, modified))
    return out


def process_folder(folder: Path, total_days: int,
                   a_min: int, a_max: int, a_step: int, out_subdir: str) -> None:
    """Создаёт набор .DATA-файлов с TSTEP=(a,b), где a∈[a_min..a_max] с шагом a_step и a+b=total_days."""
    src = find_base_data_file(folder)
    if not src:
        print(f"[Пропуск] {folder}: .DATA не найден.")
        return

    text = src.read_text(encoding="utf-8", errors="ignore")
    var_list = build_variations(text, total_days, a_min, a_max, a_step)

    out_dir = folder / out_subdir if out_subdir else folder
    out_dir.mkdir(exist_ok=True)

    n = 0
    for a, b, new_text in var_list:
        out_file = out_dir / f"{src.stem}_TSTEP_{a:03}_{b:03}{src.suffix}"
        out_file.write_text(new_text, encoding="utf-8")
        n += 1

    print(f"[OK] {folder.name}: создано {n} файлов в {out_dir}")


def main() -> None:
    ap = argparse.ArgumentParser("Генерация .DATA с окном первого шага TSTEP под кейсы BHP")
    ap.add_argument("--base", required=True, type=Path,
                    help="Путь к каталогу, где лежат папки BHP_***")
    ap.add_argument("--bhp-start", type=int, default=10, help="Начальное значение BHP (в имени папки)")
    ap.add_argument("--bhp-stop", type=int, default=120, help="Конечное значение BHP (в имени папки, включительно)")
    ap.add_argument("--total-days", type=int, default=3000, help="Сумма первых двух чисел в TSTEP")
    ap.add_argument("--a-min", type=int, default=1100, help="Минимальное значение первого числа (окно)")
    ap.add_argument("--a-max", type=int, default=2700, help="Максимальное значение первого числа (окно)")
    ap.add_argument("--a-step", type=int, default=20, help="Шаг перебора первого числа (окна)")
    ap.add_argument("--out-subdir", default="",
                    help="Подкаталог для сохранения файлов (пусто = класть рядом с базовым .DATA)")

    args = ap.parse_args()

    if args.a_step <= 0:
        raise SystemExit("Ошибка: --a-step должен быть положительным целым.")

    base_dir: Path = args.base.resolve()
    if not base_dir.is_dir():
        raise SystemExit(f"Каталог не найден: {base_dir}")

    for bhp in range(args.bhp_start, args.bhp_stop + 1):
        folder = base_dir / f"QINJ_{bhp:03d}"
        if folder.is_dir():
            process_folder(folder, args.total_days, args.a_min, args.a_max, args.a_step, args.out_subdir)
        else:
            print(f"[Пропуск] {folder}: папка отсутствует.")


if __name__ == "__main__":
    main()
