#!/usr/bin/env python3
"""把黑枫叶 1×/2× 源图打成输入法模板 TIFF。

系统打开 TISIconIsTemplate 后会按深浅背景上色，只需要这一张 ime-fn.tiff。
"""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SRC_1X = ROOT / "scripts/assets/ime-source@1x.png"
SRC_2X = ROOT / "scripts/assets/ime-source@2x.png"
OUT = ROOT / "IME" / "ime-fn.tiff"


def main() -> None:
    subprocess.check_call([
        "tiffutil", "-cathidpicheck",
        str(SRC_1X), str(SRC_2X),
        "-out", str(OUT),
    ])
    print("generated", OUT.name)


if __name__ == "__main__":
    main()
