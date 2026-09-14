/** @file
  Runtime UI scale helpers for LvglTheme.h.

  LvglLib calls LvglThemeInitFromUiScale() once at display init. Theme macros
  in LvglTheme.h route pixel and font values through these helpers so layout
  scales at draw time while LVGL renders at the physical framebuffer resolution.

  Copyright (c) 2026, MrChromebox. All rights reserved.<BR>
  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#ifndef LVGL_THEME_LIB_H_
#define LVGL_THEME_LIB_H_

#include <Uefi.h>
#include <lvgl.h>

VOID
EFIAPI
LvglThemeInitFromUiScale (
  IN UINT8  UiScale
  );

UINT32
EFIAPI
LvglThemePx (
  IN UINT32  BasePx
  );

const lv_font_t *
EFIAPI
LvglThemeFontTitle (
  VOID
  );

const lv_font_t *
EFIAPI
LvglThemeFontBody (
  VOID
  );

const lv_font_t *
EFIAPI
LvglThemeFontPopup (
  VOID
  );

VOID
EFIAPI
LvglThemeApplyBodyFont (
  IN lv_obj_t  *Obj
  );

VOID
EFIAPI
LvglThemeStyleCheckbox (
  IN lv_obj_t  *Cb
  );

VOID
EFIAPI
LvglThemeStyleDropdown (
  IN lv_obj_t  *Dd
  );

VOID
EFIAPI
LvglThemeStyleDropdownList (
  IN lv_obj_t  *List
  );

VOID
EFIAPI
LvglThemeStyleTextarea (
  IN lv_obj_t  *Ta
  );

VOID
EFIAPI
LvglThemeStyleButton (
  IN lv_obj_t  *Btn
  );

UINT32
EFIAPI
LvglThemeDropdownWidth (
  IN UINTN  MaxChars
  );

UINT32
EFIAPI
LvglThemeDateTimeFieldWidth (
  IN UINTN  Digits
  );

UINT32
EFIAPI
LvglThemeImageZoom (
  VOID
  );

VOID
EFIAPI
LvglThemeApplyPopupFont (
  IN lv_obj_t  *Obj
  );

VOID
EFIAPI
LvglThemeStyleButtonLabel (
  IN lv_obj_t  *Btn,
  IN lv_obj_t  *Lbl
  );

VOID
EFIAPI
LvglThemeStyleKeyboard (
  IN lv_obj_t  *Kb
  );

VOID
EFIAPI
LvglThemeStyleCursor (
  IN lv_obj_t  *CursorImg
  );

#endif // LVGL_THEME_LIB_H_
