#!/usr/bin/env python3
"""用桌面确认过的枫叶 1×/2× 源图生成输入源图标。

未选中用黑叶加白边，深浅背景都能看见。
选中态用白叶加黑边：Fn 面板选中行会直接画 alternate 图标，纯黑模板会被浅色高亮盖掉。
"""
from pathlib import Path
import subprocess
import tempfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC_1X = ROOT / "scripts/assets/ime-source@1x.png"
SRC_2X = ROOT / "scripts/assets/ime-source@2x.png"
OUT = ROOT / "IME"


def recolor(src: Path, fill: tuple[int, int, int], halo: tuple[int, int, int]) -> Image.Image:
    image = Image.open(src).convert("RGBA")
    pixels = image.load()
    width, height = image.size
    output = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    dest = output.load()
    for y in range(height):
        for x in range(width):
            alpha = pixels[x, y][3]
            if alpha > 24:
                dest[x, y] = (*fill, alpha)
                continue
            neighbor = 0
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < width and 0 <= ny < height:
                        neighbor = max(neighbor, pixels[nx, ny][3])
            if neighbor > 24:
                dest[x, y] = (*halo, min(255, int(neighbor * 0.95)))
    return output


def write_tiff(image_1x: Image.Image, image_2x: Image.Image, dest: Path) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        path_1x = folder / "1x.png"
        path_2x = folder / "2x.png"
        image_1x.save(path_1x)
        image_2x.save(path_2x)
        subprocess.check_call([
            "tiffutil", "-cathidpicheck",
            str(path_1x), str(path_2x),
            "-out", str(dest),
        ])


def main() -> None:
    normal_1x = recolor(SRC_1X, (0, 0, 0), (255, 255, 255))
    normal_2x = recolor(SRC_2X, (0, 0, 0), (255, 255, 255))
    selected_1x = recolor(SRC_1X, (255, 255, 255), (0, 0, 0))
    selected_2x = recolor(SRC_2X, (255, 255, 255), (0, 0, 0))
    menu = OUT / "ime-menu.tiff"
    write_tiff(normal_1x, normal_2x, menu)
    write_tiff(selected_1x, selected_2x, OUT / "ime-selected.tiff")
    # Fn / 输入法切换面板用原始枫叶，不加白边
    subprocess.check_call([
        "tiffutil", "-cathidpicheck",
        str(SRC_1X), str(SRC_2X),
        "-out", str(OUT / "ime-fn.tiff"),
    ])
    data = (OUT / "ime-fn.tiff").read_bytes()
    (OUT / "ime-input-source.tiff").write_bytes(data)
    print("generated menu, input-source, fn and selected icons")


if __name__ == "__main__":
    main()
