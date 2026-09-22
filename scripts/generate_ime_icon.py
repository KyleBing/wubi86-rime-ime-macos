#!/usr/bin/env python3
"""用桌面确认过的枫叶 1×/2× 源图生成三处输入源图标。"""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SRC_1X = ROOT / "scripts/assets/ime-source@1x.png"
SRC_2X = ROOT / "scripts/assets/ime-source@2x.png"
OUT = ROOT / "IME"


def main() -> None:
    # 三处目前使用同一视觉源，但保留独立文件，后续可分别调整。
    menu_icon = OUT / "ime-menu.tiff"
    subprocess.check_call([
        "tiffutil", "-cathidpicheck",
        str(SRC_1X), str(SRC_2X),
        "-out", str(menu_icon),
    ])
    data = menu_icon.read_bytes()
    (OUT / "ime-input-source.tiff").write_bytes(data)
    (OUT / "ime-fn.tiff").write_bytes(data)
    print("generated menu, input-source and fn icons")


if __name__ == "__main__":
    main()
