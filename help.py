import re
from pathlib import Path


def schedule():
    TEMPLATE = Path(r"D:\convergance_tests\orig-Copy\INCLUDE\schedule_test.inc")
    OUTPUT_DIR = Path(r"D:\convergance_tests\orig-Copy\INCLUDE\generated")
    OUTPUT_DIR.mkdir(exist_ok=True)

    text = TEMPLATE.read_text(encoding="utf‑8")

    for orat in range(180, 4, -5):
        replacement = r"\g<1>{}".format(orat)
        new_text = re.sub(r"('ORAT'\s+)\d+", replacement, text, count=1)
        out_file = OUTPUT_DIR / f"schedule_ORAT_{orat:03}.inc"
        out_file.write_text(new_text, encoding="utf‑8")

    print(f"{len(list(OUTPUT_DIR.glob('schedule_ORAT_*.inc')))} файлов создано.")


def data():

    return


if __name__ == "__main__":
    schedule()
    print("Готово.")
