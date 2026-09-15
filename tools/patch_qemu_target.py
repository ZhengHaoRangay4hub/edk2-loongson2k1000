#!/usr/bin/env python3
"""Patch the upstream LoongArchVirt QEMU target to match this port.

The QEMU regression firmware is built from OvmfPkg/LoongArchVirt, so the
platform integration (theme library, LVGL apps, console/resolution PCDs)
has to be applied there too. Doing it with a pile of `sed` expressions
turned out to be order dependent and easy to break, hence this idempotent
script: every operation checks the current state first.

Usage: python3 tools/patch_qemu_target.py <edk2-dir>
"""
import os
import re
import sys

THEME_LIB = "Platform/Loongson/Loongson2K1000Pkg/Library/LoongsonSetupThemeLib/CustomizedDisplayLib.inf"
BOOT_MGR_LIB = "Platform/Loongson/Loongson2K1000Pkg/Library/PlatformBootManagerLib/PlatformBootManagerLib.inf"
LVGL_LIB = "LvglPkg/Library/LvglLib/LvglLib.inf"
#
# Only the setup centre is built into the firmware: the upstream demo
# applications (UefiDashboard, LvglDemoApp) ship a crude UI and would show
# up in the boot menu next to the real setup, which is confusing.
#
APPS = [
    "LvglPkg/Application/LvglSetupApp/LvglSetupApp.inf",
]
BOOT_MENU_APP = "MdeModulePkg/Application/BootManagerMenuApp/BootManagerMenuApp.inf"

# Upstream demos: not built into the firmware any more. They are stripped
# from cached edk2 trees so a previous patch does not keep them alive.
DEMO_APPS = [
    "LvglPkg/Application/UefiDashboard/UefiDashboard.inf",
    "LvglPkg/Application/LvglDemoApp/LvglDemoApp.inf",
]
UI_APP = "MdeModulePkg/Application/UiApp/UiApp.inf"
BOOT_MENU_GUID_BYTES = "{ 0xdc, 0x5b, 0xc2, 0xee, 0xf2, 0x67, 0x95, 0x4d, 0xb1, 0xd5, 0xf8, 0x1b, 0x20, 0x39, 0xd1, 0x1d }"
LEGACY_BOOT_MENU_GUID = "{ 0x21, 0xaa, 0x2c, 0x46, 0x14, 0x76, 0x03, 0x45, 0x83, 0x6e, 0x8a, 0xb6, 0xf4, 0x66, 0x23, 0x31 }"

log = []


def set_pcd(text, name, value):
    """Force `Pcd<name>` to `value`, whether or not it is already defined."""
    pattern = re.compile(r'(%s\s*\|)[^|\n]*' % re.escape(name))
    if pattern.search(text):
        new, n = pattern.subn(r'\g<1> %s' % value, text, count=1)
        log.append("%s -> %s" % (name, value))
        return new
    return text


def _insert(text, anchor, lines, before, scope_from=None):
    """Insert `lines` next to `anchor` unless they are already present."""
    missing = [l for l in lines if l.strip() and l.strip() not in text]
    if not missing:
        return text
    start = text.find(scope_from) if scope_from else 0
    if start == -1:
        log.append("!! section not found: %s" % scope_from)
        return text
    idx = text.find(anchor, start)
    if idx == -1:
        log.append("!! anchor not found: %s" % anchor)
        return text
    add = ''.join('  %s\n' % l for l in missing)
    where = 'before' if before else 'after'
    pos = text.rfind('\n', 0, idx) + 1 if before else text.find('\n', idx) + 1
    log.append("inserted %s '%s': %s" % (
        where, anchor.strip()[:44], ', '.join(m.split('/')[-1] for m in missing)))
    return text[:pos] + add + text[pos:]


def ensure_before(text, anchor, lines, scope_from=None):
    return _insert(text, anchor, lines, True, scope_from)


def ensure_after(text, anchor, lines, scope_from=None):
    return _insert(text, anchor, lines, False, scope_from)


def strip_demo_apps(text):
    for app in DEMO_APPS:
        for prefix in ('INF  ', '  '):
            text = text.replace('%s%s\n' % (prefix, app), '')
    return text


def write_if_changed(path, text):
    old = open(path).read()
    if old != text:
        open(path, 'w').write(text)
        return True
    return False


def patch_dsc(path):
    text = open(path).read()

    # theme library replaces the stock CustomizedDisplayLib instance
    text = re.sub(
        r'(\s*)CustomizedDisplayLib\s*\|.*CustomizedDisplayLib\.inf',
        r'\1CustomizedDisplayLib             | ' + THEME_LIB,
        text, count=1)

    # LVGL library class
    if LVGL_LIB not in text:
        text = ensure_after(
            text,
            'CustomizedDisplayLib             |',
            ['LvglLib                          | ' + LVGL_LIB],
            scope_from='[LibraryClasses')

    # platform BDS policy (graphics-only ConOut, largest text mode, the LVGL
    # setup entry) replaces the upstream light boot manager
    text = re.sub(
        r'(\s*)PlatformBootManagerLib\s*\|.*PlatformBootManagerLib\.inf',
        r'\1PlatformBootManagerLib           | ' + BOOT_MGR_LIB,
        text, count=1)
    log.append("PlatformBootManagerLib -> board implementation")

    # components: LVGL applications + the boot manager menu popup
    components = [BOOT_MENU_APP] + APPS
    text = ensure_before(
        text,
        'MdeModulePkg/Application/UiApp/UiApp.inf',
        components,
        scope_from='[Components]')

    # video / console PCDs
    text = set_pcd(text, 'PcdVideoHorizontalResolution', '1024')
    text = set_pcd(text, 'PcdVideoVerticalResolution', '768')
    text = set_pcd(text, 'PcdSetupVideoHorizontalResolution', '1024')
    text = set_pcd(text, 'PcdSetupVideoVerticalResolution', '768')

    if 'PcdConOutColumn' not in text:
        text = ensure_after(
            text,
            'PcdSetupVideoVerticalResolution',
            [
                'gEfiMdeModulePkgTokenSpaceGuid.PcdConOutColumn | 0',
                'gEfiMdeModulePkgTokenSpaceGuid.PcdConOutRow | 0',
                'gEfiMdeModulePkgTokenSpaceGuid.PcdSetupConOutColumn | 0',
                'gEfiMdeModulePkgTokenSpaceGuid.PcdSetupConOutRow | 0',
            ],
        )

    text = text.replace(LEGACY_BOOT_MENU_GUID, BOOT_MENU_GUID_BYTES)
    text = strip_demo_apps(text)

    if write_if_changed(path, text):
        log.append("dsc written")
    else:
        log.append("dsc already up to date")


def patch_fdf(path):
    text = open(path).read()
    in_lines = ['INF  ' + m for m in [BOOT_MENU_APP] + APPS]
    text = ensure_before(text, 'INF  ' + UI_APP, in_lines)
    text = strip_demo_apps(text)
    if write_if_changed(path, text):
        log.append("fdf written")
    else:
        log.append("fdf already up to date")


def main():
    edk2 = sys.argv[1]
    dsc = os.path.join(edk2, 'OvmfPkg/LoongArchVirt/LoongArchVirtQemu.dsc')
    fdf = os.path.join(edk2, 'OvmfPkg/LoongArchVirt/LoongArchVirtQemu.fdf')
    patch_dsc(dsc)
    patch_fdf(fdf)
    for line in log:
        print('  ' + line)


if __name__ == '__main__':
    main()
