#!/usr/bin/env sh
# Regenerate the LVGL setup fonts (LvglPkg/Application/LvglSetupApp/Fonts).
#
# The character set is taken from the app source, so the fonts only contain
# the glyphs actually used (keeps the firmware small and the rendering exact).
#
# Requirements:
#   - Noto Sans SC Regular OTF (SIL OFL), e.g. from
#     https://github.com/notofonts/noto-cjk  (Sans/SubsetOTF/SC/NotoSansSC-Regular.otf)
#   - lv_font_conv (npm i lv_font_conv)
#
# Usage: tools/make_setup_fonts.sh <NotoSansSC-Regular.otf> <path-to-lv_font_conv>
set -eu

FONT=${1:?usage: make_setup_fonts.sh <NotoSansSC-Regular.otf> <lv_font_conv>}
LVFC=${2:-lv_font_conv}
DIR=Platform/../LvglPkg/Application/LvglSetupApp
[ -d "$DIR" ] || DIR=LvglPkg/Application/LvglSetupApp

CHARS=$(python3 - "$DIR/LvglSetupApp.c" <<'PY'
import sys
chars = sorted({c for c in open(sys.argv[1], encoding='utf-8').read() if ord(c) > 0x7F})
print(','.join('0x%X' % ord(c) for c in chars))
PY
)

for SZ in 16 24; do
    "$LVFC" --font "$FONT" --bpp 4 --size "$SZ" --format lvgl \
        --range 0x20-0x7F --range "$CHARS" \
        -o "$DIR/Fonts/lv_font_ls_setup_$SZ.c" \
        --force-fast-kern-format --no-compress
    # icon glyphs fall back to the built-in Montserrat font
    python3 - "$DIR/Fonts/lv_font_ls_setup_$SZ.c" "$SZ" <<'PY'
import sys
path, size = sys.argv[1], sys.argv[2]
fallback = 'lv_font_montserrat_%s' % size
text = open(path).read()
old = '''#if LV_VERSION_CHECK(8, 2, 0) || LVGL_VERSION_MAJOR >= 9
    .fallback = NULL,
#endif'''
new = '''#if LV_VERSION_CHECK(8, 2, 0) || LVGL_VERSION_MAJOR >= 9
    /* Missing glyphs (LV_SYMBOL_* icons) resolve via the built-in font */
    .fallback = &%s,
#endif''' % fallback
assert old in text, path
open(path, 'w').write(text.replace(old, new, 1))
print('patched fallback in', path)
PY
done
