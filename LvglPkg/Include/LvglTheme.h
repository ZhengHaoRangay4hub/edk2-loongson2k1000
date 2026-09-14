/** @file
  LvglTheme.h - User-customizable theme for LvglDisplayEngineDxe.

  Edit the macros in this file and rebuild to restyle the LVGL HII form
  renderer. All colors, fonts, padding, and radius values used by
  LvglFormRenderer.c flow through these macros.

  Fonts referenced here must be enabled in LvglPkg/lv_conf.h
  (LV_FONT_MONTSERRAT_*).
**/

#ifndef LVGL_THEME_H_
#define LVGL_THEME_H_

#include <Library/LvglThemeLib.h>

//
// Background colors (24-bit RGB; passed to lv_color_hex())
//
// NovaCore palette: near-black canvas, blue-tinted panels, accent blue.
//
#define THEME_COLOR_BG_SCREEN     0x0F141A
#define THEME_COLOR_BG_PANEL      0x182328
#define THEME_COLOR_BG_PANEL_ELEV 0x23304A
#define THEME_COLOR_BG_DIALOG     0x1B2A3A
#define THEME_COLOR_BG_SEPARATOR  0x2A3A52

//
// Text colors
//
#define THEME_COLOR_TEXT_TITLE     0xFFFFFF
#define THEME_COLOR_TEXT_PRIMARY   0xEAF2FF
#define THEME_COLOR_TEXT_SECONDARY 0x9FB0C8
#define THEME_COLOR_TEXT_DISABLED  0x6A7B92
#define THEME_COLOR_TEXT_LABEL     THEME_COLOR_TEXT_PRIMARY
#define THEME_COLOR_TEXT_POPUP     THEME_COLOR_TEXT_PRIMARY

//
// Row colors (default / hovered / focused).
//
#define THEME_COLOR_ROW_BG            THEME_COLOR_BG_PANEL
#define THEME_COLOR_ROW_BG_HOVER      0x1E2A3C
#define THEME_COLOR_ROW_TEXT          THEME_COLOR_TEXT_PRIMARY
#define THEME_COLOR_ROW_TEXT_FOCUSED  0xFFFFFF
#define THEME_COLOR_ROW_TEXT_DISABLED THEME_COLOR_TEXT_DISABLED

//
// Accent (focus ring + active selection).
//
#define THEME_COLOR_ACCENT        0x1A6FD8
#define THEME_COLOR_ACCENT_HOVER  0x2A85F0
#define THEME_COLOR_SUCCESS       0x2BC79F
#define THEME_COLOR_WARNING       0xE9A23B
#define THEME_COLOR_DANGER        0xE25555

//
// Accent (subtitle / focus highlight) -- LV_PALETTE_* enum value
//
#define THEME_ACCENT_PALETTE      LV_PALETTE_BLUE

//
// Fonts -- must be enabled in lv_conf.h. Sizes scale with UiScale via
// LvglThemeFont*() (base: title 20, body/popup 16).
//
#define THEME_FONT_TITLE          LvglThemeFontTitle()
#define THEME_FONT_BODY           LvglThemeFontBody()
#define THEME_FONT_POPUP          LvglThemeFontPopup()
#define THEME_APPLY_BODY_FONT     LvglThemeApplyBodyFont
#define THEME_APPLY_POPUP_FONT    LvglThemeApplyPopupFont

//
// Spacing & shape (base pixels at 1x; scaled via LvglThemePx()).
//
#define THEME_PAD_SCREEN          LvglThemePx(16)
#define THEME_PAD_PANEL           LvglThemePx(8)
#define THEME_PAD_ROW             LvglThemePx(4)
#define THEME_PAD_ROW_TIGHT       LvglThemePx(2)
#define THEME_PAD_DIALOG          LvglThemePx(16)
#define THEME_PAD_DIALOG_ROW_GAP  LvglThemePx(10)
#define THEME_PAD_DIALOG_COL_GAP  LvglThemePx(8)
#define THEME_PAD_SCREEN_ROW_GAP  LvglThemePx(6)
#define THEME_PAD_PANEL_ROW_GAP   LvglThemePx(4)
#define THEME_PAD_LABEL_TOP       LvglThemePx(8)
#define THEME_RADIUS              LvglThemePx(8)
#define THEME_OVERLAY_OPA         LV_OPA_50

//
// Aptio-style chrome (header / subtitle / footer / wallpaper).
// Used by LvglDisplayEngineDxe/LvglAptioChrome.c.
//
#define THEME_COLOR_HEADER_BG_TOP     0x0B1218
#define THEME_COLOR_HEADER_BG_BOTTOM  0x16263F
#define THEME_COLOR_HEADER_TEXT       0xFFFFFF
#define THEME_COLOR_HEADER_DIM        0x9FB0C8
#define THEME_COLOR_SUBTITLE_BG       0x182328
#define THEME_COLOR_SUBTITLE_TEXT     0xEAF2FF
#define THEME_COLOR_FOOTER_BG         0x0B1218
#define THEME_COLOR_FOOTER_TEXT       0xEAF2FF
#define THEME_COLOR_FOOTER_DIM        0x6A7B92
#define THEME_COLOR_HIGHLIGHT_ROW     THEME_COLOR_ACCENT

#define THEME_HEADER_HEIGHT       LvglThemePx(44)
#define THEME_SUBTITLE_HEIGHT     LvglThemePx(28)
#define THEME_FOOTER_HEIGHT       LvglThemePx(32)

//
// Chrome -- help pane (right column).
//
#define THEME_PAD_HELPPANE_X         LvglThemePx(14)
#define THEME_PAD_HELPPANE_Y         LvglThemePx(12)
#define THEME_PAD_HELPPANE_ROW_GAP   LvglThemePx(8)

//
// Chrome -- header / subtitle / content / footer paddings.
//
#define THEME_PAD_HEADER_X           LvglThemePx(16)
#define THEME_PAD_SUBTITLE_X         LvglThemePx(16)
#define THEME_PAD_CONTENT_LEFT       LvglThemePx(24)
#define THEME_PAD_CONTENT_RIGHT      LvglThemePx(16)
#define THEME_PAD_CONTENT_Y          LvglThemePx(12)
#define THEME_PAD_CONTENT_ROW_GAP    LvglThemePx(6)
#define THEME_PAD_FOOTER_X           LvglThemePx(12)
#define THEME_PAD_FOOTER_Y           LvglThemePx(2)
#define THEME_PAD_FOOTER_COL_GAP     LvglThemePx(6)

//
// Footer "chip" widgets (one per registered hotkey + nav primitives).
//
#define THEME_PAD_CHIP_X             LvglThemePx(8)
#define THEME_PAD_CHIP_Y             LvglThemePx(4)
#define THEME_PAD_CHIP_COL_GAP       LvglThemePx(6)
#define THEME_RADIUS_CHIP            LvglThemePx(4)

//
// Form rows (StyleRow).
//
#define THEME_RADIUS_ROW             LvglThemePx(4)
#define THEME_PAD_ROW_X              LvglThemePx(16)
#define THEME_PAD_ROW_Y              LvglThemePx(10)
#define THEME_BORDER_FOCUS           LvglThemePx(3)

//
// Generic 1 px separator/border thickness used between panes.
//
#define THEME_BORDER_PANE            LvglThemePx(1)

//
// Confirm/discard dialog card width as a percentage of the screen.
//
#define THEME_DIALOG_WIDTH_PCT       50


//
// Content frame sizing (Graphical UI Configuration setup page / PCD defaults):
//   CenteredFrameEnabled    -- center UI in an aspect-ratio window
//   CenteredFrameHeightPct  -- frame height (% of display height)
//   CenteredFrameAspectNum, CenteredFrameAspectDen -- frame width = height * Num / Den
//
// Backdrop shown behind the centered content frame (the letterbox bars).
// Only used when PcdLvglCenteredFrameEnabled is TRUE.
//
#define THEME_COLOR_BACKDROP         0x05080B

//
// Aptio-style chrome strings and layout overrides (platform DSC / PCD):
//   PcdLvglAptioHeaderTitle      -- header bar title (left)
//   PcdLvglAptioHeaderVendor     -- header bar vendor string (center)
//   PcdLvglHelpPaneWidthPct      -- help pane width (% of content row)
//   PcdLvglAptioSubtitleShowsDeviceModel -- device model in subtitle bar vs content
//
#define APTIO_FOOTER_NAV_HINTS    LV_SYMBOL_UP LV_SYMBOL_DOWN " Select   Enter Confirm   Esc Exit   F9 Defaults   F10 Save"
#define APTIO_FOOTER_SYSINFO      "QEMU x86_64  |  OVMF"

#endif // LVGL_THEME_H_
