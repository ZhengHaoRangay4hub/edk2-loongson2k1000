/** @file
  AMI Aptio-style chrome (header bar, subtitle bar, footer bar, wallpaper)
  for LvglDisplayEngineDxe.

  Copyright (c) 2024-2026, Hamit Karaca. All rights reserved.<BR>
  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#ifndef LVGL_APTIO_CHROME_H_
#define LVGL_APTIO_CHROME_H_

#include <Uefi.h>
#include <Library/LvglLib.h>
#include <Protocol/DisplayProtocol.h>

/**
  Build the full Aptio chrome under Screen and return the inner content
  panel into which the form widgets should be appended.

  Layout (top to bottom):
    Wallpaper (full-screen, behind everything)
    Header bar          THEME_HEADER_HEIGHT px,  gradient
    Subtitle bar        THEME_SUBTITLE_HEIGHT px
    Content panel       fills remaining space, transparent
    Footer bar          THEME_FOOTER_HEIGHT px

  @param[in]  Screen    LVGL root screen (must already be created).
  @param[in]  FormData  Current form (used for subtitle text).

  @return  The content panel object. Form widgets should be created as
           children of this object. Returned pointer is owned by Screen
           and freed when Screen is deleted.
**/
lv_obj_t *
EFIAPI
AptioBuildChrome (
  IN lv_obj_t                    *Screen,
  IN FORM_DISPLAY_ENGINE_FORM    *FormData
  );

/**
  Stop the clock-update timer if running. Must be called before the
  screen object is deleted (timers are not children of objects).
**/
VOID
EFIAPI
AptioChromeTeardown (
  VOID
  );

/**
  Update the help pane text. Caller-owned UTF-8 string is copied by LVGL.
  Pass NULL or "" to clear.
**/
VOID
EFIAPI
AptioSetHelpText (
  IN CONST CHAR8  *Utf8
  );

#endif // LVGL_APTIO_CHROME_H_
