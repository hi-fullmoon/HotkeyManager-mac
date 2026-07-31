"""生成 HotkeyManager 的 macOS 应用图标：深色立体键帽 + 黄色闪电。

输出：
  Resources/AppIcon.icns    iconutil 编译的多尺寸 icns
  assets/icon-preview.png   512px 预览图

用法（仓库根目录）：
  python3 -m venv .venv-icon && .venv-icon/bin/pip install pillow
  .venv-icon/bin/python tools/make_icon.py
"""

import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ICNS_PATH = ROOT / "Resources" / "AppIcon.icns"
PREVIEW_PATH = ROOT / "assets" / "icon-preview.png"
ICONSET_DIR = ROOT / ".build" / "AppIcon.iconset"

SIZE = 1024  # 基准画布，小尺寸由 Pillow 高质量缩放
SS = 2       # 超采样倍数，抗锯齿

# 调色板
BASE_TOP = (51, 65, 85, 255)      # 键帽底座顶 #334155
BASE_BOT = (15, 23, 42, 255)      # 键帽底座底 #0F172A
KEY_TOP = (100, 116, 139, 255)    # 键面顶部亮灰 #64748B
KEY_BOT = (51, 65, 85, 255)       # 键面底部 #334155
EDGE_HI = (148, 163, 184, 255)    # 键面顶部高光 #94A3B8
BOLT = (250, 204, 21, 255)        # 明黄 #FACC15
BOLT_EDGE = (202, 138, 4, 255)    # 闪电描边 #CA8A04


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))


def rounded_gradient(size, box, radius, top_color, bottom_color):
    """圆角矩形 + 垂直渐变，返回 (RGBA 图层, mask)。"""
    x0, y0, x1, y1 = box
    grad = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(grad)
    for y in range(y0, y1):
        t = (y - y0) / max(1, y1 - y0)
        d.line([(x0, y), (x1, y)], fill=lerp(top_color, bottom_color, t))
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.paste(grad, (0, 0), mask)
    return layer, mask


def draw_icon() -> Image.Image:
    s = SIZE * SS
    u = s / 256  # 以 256 为逻辑坐标的缩放因子

    def pt(x, y):
        return (x * u, y * u)

    def box(x0, y0, x1, y1):
        return (round(x0 * u), round(y0 * u), round(x1 * u), round(y1 * u))

    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    # 键帽底座：全画布圆角矩形，深色渐变
    base, _ = rounded_gradient(img.size, box(2, 2, 254, 254), round(56 * u), BASE_TOP, BASE_BOT)
    img.alpha_composite(base)

    # 键面：上方内缩、底部留出底座边缘，营造立体感
    key, key_mask = rounded_gradient(img.size, box(14, 10, 242, 224), round(46 * u), KEY_TOP, KEY_BOT)
    img.alpha_composite(key)

    # 键面顶部高光：一条柔和的浅色弧线
    hi = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(hi)
    d.rounded_rectangle(box(14, 10, 242, 224), radius=round(46 * u), outline=EDGE_HI, width=round(2.2 * u))
    hi = hi.filter(ImageFilter.GaussianBlur(1.2 * u))
    # 只保留键面内的上半部分高光
    top_half = Image.new("L", img.size, 0)
    ImageDraw.Draw(top_half).rectangle(box(14, 10, 242, 110), fill=255)
    hi_mask = Image.composite(key_mask, Image.new("L", img.size, 0), top_half)
    img.paste(hi, (0, 0), Image.composite(hi.split()[3], Image.new("L", img.size, 0), hi_mask))

    # 闪电（经典 zigzag 形状，基准坐标基于 256，居中于键面）
    bolt = [
        (150, 36),
        (82, 142),
        (122, 142),
        (102, 214),
        (176, 106),
        (132, 106),
    ]

    # 闪电投影：向下偏移 + 模糊，压在键面上
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    off = 5 * u
    sd.polygon([(x * u, y * u + off) for x, y in bolt], fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(3 * u))
    shadow.putalpha(Image.composite(shadow.split()[3], Image.new("L", img.size, 0), key_mask))
    img.alpha_composite(shadow)

    # 闪电本体
    d = ImageDraw.Draw(img)
    d.polygon([pt(x, y) for x, y in bolt], fill=BOLT, outline=BOLT_EDGE, width=round(3 * u))

    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    icon = draw_icon()
    ICNS_PATH.parent.mkdir(parents=True, exist_ok=True)
    PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
    ICONSET_DIR.mkdir(parents=True, exist_ok=True)

    # iconset 全套尺寸
    for logical in (16, 32, 128, 256, 512):
        for scale, px in ((1, logical), (2, logical * 2)):
            name = f"icon_{logical}x{logical}" + ("@2x" if scale == 2 else "") + ".png"
            icon.resize((px, px), Image.LANCZOS).save(ICONSET_DIR / name)

    subprocess.run(
        ["iconutil", "-c", "icns", str(ICONSET_DIR), "-o", str(ICNS_PATH)],
        check=True,
    )
    icon.resize((512, 512), Image.LANCZOS).save(PREVIEW_PATH)
    print(f"written: {ICNS_PATH}")
    print(f"written: {PREVIEW_PATH}")


if __name__ == "__main__":
    main()
