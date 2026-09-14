/** @file
  Runtime UI scale helpers for LvglTheme.h.

  Copyright (c) 2026, MrChromebox. All rights reserved.<BR>
  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#define LV_CONF_INCLUDE_SIMPLE
#include "lv_conf.h"

#include <Library/LvglThemeLib.h>
#include <Guid/LvglUiConfig.h>

STATIC UINT8  mScaleNum = 1;
STATIC UINT8  mScaleDen = 1;

VOID
EFIAPI
LvglThemeInitFromUiScale (
  IN UINT8  UiScale
  )
{
  switch (UiScale) {
    case LVGL_UI_SCALE_2X:
      mScaleNum = 2;
      mScaleDen = 1;
      break;
    case LVGL_UI_SCALE_1_5X:
      mScaleNum = 3;
      mScaleDen = 2;
      break;
    default:
      mScaleNum = 1;
      mScaleDen = 1;
      break;
  }
}

UINT32
EFIAPI
LvglThemePx (
  IN UINT32  BasePx
  )
{
  return (UINT32)(((UINT64)BasePx * (UINT64)mScaleNum) / (UINT64)mScaleDen);
}

const lv_font_t *
EFIAPI
LvglThemeFontTitle (
  VOID
  )
{
  if ((mScaleNum == 2) && (mScaleDen == 1)) {
#if LV_FONT_MONTSERRAT_40
    return &lv_font_montserrat_40;
#endif
  } else if ((mScaleNum == 3) && (mScaleDen == 2)) {
#if LV_FONT_MONTSERRAT_30
    return &lv_font_montserrat_30;
#endif
  }

  return &lv_font_montserrat_20;
}

const lv_font_t *
EFIAPI
LvglThemeFontBody (
  VOID
  )
{
  if ((mScaleNum == 2) && (mScaleDen == 1)) {
#if LV_FONT_MONTSERRAT_32
    return &lv_font_montserrat_32;
#endif
  } else if ((mScaleNum == 3) && (mScaleDen == 2)) {
    return &lv_font_montserrat_24;
  }

  return &lv_font_montserrat_16;
}

const lv_font_t *
EFIAPI
LvglThemeFontPopup (
  VOID
  )
{
  return LvglThemeFontBody ();
}

VOID
EFIAPI
LvglThemeApplyBodyFont (
  IN lv_obj_t  *Obj
  )
{
  lv_obj_set_style_text_font (Obj, LvglThemeFontBody (), LV_PART_MAIN);
}

VOID
EFIAPI
LvglThemeStyleCheckbox (
  IN lv_obj_t  *Cb
  )
{
  lv_coord_t  Box;

  LvglThemeApplyBodyFont (Cb);
  Box = (lv_coord_t)LvglThemePx (24);
  lv_obj_set_style_text_font (Cb, LvglThemeFontBody (), LV_PART_INDICATOR);
  lv_obj_set_style_pad_all (Cb, (lv_coord_t)LvglThemePx (2), LV_PART_INDICATOR);
  lv_obj_set_style_width (Cb, Box, LV_PART_INDICATOR);
  lv_obj_set_style_height (Cb, Box, LV_PART_INDICATOR);
  lv_obj_set_style_radius (Cb, (lv_coord_t)LvglThemePx (4), LV_PART_INDICATOR);
}

VOID
EFIAPI
LvglThemeStyleDropdown (
  IN lv_obj_t  *Dd
  )
{
  lv_obj_set_style_text_font (Dd, LvglThemeFontBody (), LV_PART_MAIN);
  lv_obj_set_style_pad_left (Dd, (lv_coord_t)LvglThemePx (12), LV_PART_MAIN);
  lv_obj_set_style_pad_right (Dd, (lv_coord_t)LvglThemePx (12), LV_PART_MAIN);
  lv_obj_set_style_pad_top (Dd, (lv_coord_t)LvglThemePx (8), LV_PART_MAIN);
  lv_obj_set_style_pad_bottom (Dd, (lv_coord_t)LvglThemePx (8), LV_PART_MAIN);
  lv_obj_set_style_text_font (Dd, LvglThemeFontBody (), LV_PART_INDICATOR);
  lv_obj_set_style_pad_all (Dd, (lv_coord_t)LvglThemePx (4), LV_PART_INDICATOR);
}

VOID
EFIAPI
LvglThemeStyleDropdownList (
  IN lv_obj_t  *List
  )
{
  lv_obj_set_style_text_font (List, LvglThemeFontBody (), LV_PART_MAIN);
  lv_obj_set_style_pad_row (List, (lv_coord_t)LvglThemePx (4), LV_PART_MAIN);
  lv_obj_set_style_pad_left (List, (lv_coord_t)LvglThemePx (12), LV_PART_MAIN);
  lv_obj_set_style_pad_right (List, (lv_coord_t)LvglThemePx (12), LV_PART_MAIN);
}

VOID
EFIAPI
LvglThemeStyleTextarea (
  IN lv_obj_t  *Ta
  )
{
  LvglThemeApplyBodyFont (Ta);
  lv_obj_set_style_min_height (Ta, (lv_coord_t)LvglThemePx (32), LV_PART_MAIN);
  lv_obj_set_style_pad_left (Ta, (lv_coord_t)LvglThemePx (8), LV_PART_MAIN);
  lv_obj_set_style_pad_right (Ta, (lv_coord_t)LvglThemePx (8), LV_PART_MAIN);
  lv_obj_set_style_pad_top (Ta, (lv_coord_t)LvglThemePx (6), LV_PART_MAIN);
  lv_obj_set_style_pad_bottom (Ta, (lv_coord_t)LvglThemePx (6), LV_PART_MAIN);
}

VOID
EFIAPI
LvglThemeStyleButton (
  IN lv_obj_t  *Btn
  )
{
  LvglThemeApplyBodyFont (Btn);
  lv_obj_set_style_pad_left (Btn, (lv_coord_t)LvglThemePx (12), LV_PART_MAIN);
  lv_obj_set_style_pad_right (Btn, (lv_coord_t)LvglThemePx (12), LV_PART_MAIN);
  lv_obj_set_style_pad_top (Btn, (lv_coord_t)LvglThemePx (8), LV_PART_MAIN);
  lv_obj_set_style_pad_bottom (Btn, (lv_coord_t)LvglThemePx (8), LV_PART_MAIN);
}

UINT32
EFIAPI
LvglThemeDropdownWidth (
  IN UINTN  MaxChars
  )
{
  return (UINT32)(MaxChars * LvglThemePx (10) + LvglThemePx (50));
}

UINT32
EFIAPI
LvglThemeDateTimeFieldWidth (
  IN UINTN  Digits
  )
{
  return (UINT32)(Digits * LvglThemePx (12) + LvglThemePx (28));
}

UINT32
EFIAPI
LvglThemeImageZoom (
  VOID
  )
{
  return (UINT32)((256U * (UINT32)mScaleNum) / (UINT32)mScaleDen);
}

VOID
EFIAPI
LvglThemeApplyPopupFont (
  IN lv_obj_t  *Obj
  )
{
  lv_obj_set_style_text_font (Obj, LvglThemeFontPopup (), LV_PART_MAIN);
}

VOID
EFIAPI
LvglThemeStyleButtonLabel (
  IN lv_obj_t  *Btn,
  IN lv_obj_t  *Lbl
  )
{
  LvglThemeStyleButton (Btn);
  LvglThemeApplyBodyFont (Lbl);
}

VOID
EFIAPI
LvglThemeStyleKeyboard (
  IN lv_obj_t  *Kb
  )
{
  lv_obj_set_style_text_font (Kb, LvglThemeFontBody (), LV_PART_ITEMS);
  lv_obj_set_style_pad_all (Kb, (lv_coord_t)LvglThemePx (6), LV_PART_ITEMS);
  lv_obj_set_style_pad_row (Kb, (lv_coord_t)LvglThemePx (4), LV_PART_MAIN);
  lv_obj_set_style_pad_column (Kb, (lv_coord_t)LvglThemePx (4), LV_PART_MAIN);
}

VOID
EFIAPI
LvglThemeStyleCursor (
  IN lv_obj_t  *CursorImg
  )
{
  if (CursorImg == NULL) {
    return;
  }

  lv_image_set_scale (CursorImg, LvglThemeImageZoom ());
}
