#!/usr/bin/env python3
"""Generate the platform boot logo (assets/logo.bmp, 24bpp BMP).

The rendered BMP is committed; re-run only when redesigning:

    python3 tools/make_logo.py assets/logo.bmp
"""
import math
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

W, H = 1024, 512

BG_TOP = (10, 14, 38)
BG_BOT = (36, 26, 90)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient_bg():
    img = Image.new('RGB', (W, H))
    px = img.load()
    for y in range(H):
        row = lerp(BG_TOP, BG_BOT, y / H)
        for x in range(W):
            sheen = (math.sin((x / W * 1.4 + y / H * 0.9) * math.pi) ** 2) * 9
            px[x, y] = tuple(min(255, int(c + sheen)) for c in row)
    return img


def font(path, size):
    return ImageFont.truetype(path, size)


def fit(draw, text, path, target_w, start):
    """Return the largest font no wider than target_w."""
    size = start
    while size > 12:
        f = font(path, size)
        w = draw.textbbox((0, 0), text, font=f)[2]
        if w <= target_w:
            return f
        size -= 2
    return font(path, 12)


def main(out):
    img = gradient_bg()

    # ---- base art ----
    d = ImageDraw.Draw(img)
    d.ellipse((60, 55, 410, 405), outline=(240, 180, 80), width=6)
    d.ellipse((74, 69, 396, 391), outline=(120, 90, 160), width=2)

    # wordmark (auto-fit into the right column)
    left, right = 462, 980
    col = right - left
    han = font('/System/Library/Fonts/Hiragino Sans GB.ttc', 300)
    title_f = fit(d, 'LOONGSON 2K1000LA', '/System/Library/Fonts/Helvetica.ttc', col, 72)
    sub_t = 'EDK II  ·  UEFI FIRMWARE'
    sub_f = fit(d, sub_t, '/System/Library/Fonts/Helvetica.ttc', col, 32)
    foot_t = 'LA264 x2 @ 1.0GHz · LoongArch64'
    foot_f = font('/System/Library/Fonts/Menlo.ttc', 24)

    d.text((left, 186), 'LOONGSON 2K1000LA', font=title_f, fill=(246, 248, 255))
    d.line((left + 2, 248, right, 248), fill=(240, 180, 80), width=3)
    d.text((left + 2, 268), sub_t, font=sub_f, fill=(172, 182, 224))
    d.text((left + 2, 430), foot_t, font=foot_f, fill=(128, 138, 182))

    # ---- glow layer: gold glyph + ring, blurred and screened on top ----
    layer = Image.new('RGB', (W, H), (0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.text((235, 232), '龙', font=han, fill=(120, 82, 20), anchor='mm')
    layer = layer.filter(ImageFilter.GaussianBlur(14))
    # tighter bright core
    core = Image.new('RGB', (W, H), (0, 0, 0))
    cd = ImageDraw.Draw(core)
    cd.text((235, 232), '龙', font=han, fill=(255, 196, 90), anchor='mm')
    core = core.filter(ImageFilter.GaussianBlur(2))
    layer = ImageChops.screen(layer, core)

    img = ImageChops.screen(img, layer)

    # crisp glyph on top of everything
    d = ImageDraw.Draw(img)
    d.text((235, 232), '龙', font=han, fill=(255, 208, 110), anchor='mm')

    img.save(out, format='BMP')
    print('wrote', out, img.size)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'assets/logo.bmp')
