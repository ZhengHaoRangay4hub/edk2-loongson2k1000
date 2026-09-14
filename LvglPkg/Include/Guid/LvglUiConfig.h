/** @file
  Shared definitions for the LVGL UI configuration (software UI scaling and
  chrome layout). The values are persisted in a non-volatile UEFI variable so
  the LVGL library and display engine can read them at boot. LvglSetupDxe
  publishes the setup form; platform PCDs supply the defaults on first boot.

  Copyright (c) 2026, MrChromebox. All rights reserved.<BR>
  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#ifndef LVGL_UI_CONFIG_H_
#define LVGL_UI_CONFIG_H_

//
// {DDB969F2-E99B-4DD5-8E36-B80B526D3B73}
//
#define LVGL_UI_CONFIG_FORMSET_GUID \
  { 0xddb969f2, 0xe99b, 0x4dd5, { 0x8e, 0x36, 0xb8, 0x0b, 0x52, 0x6d, 0x3b, 0x73 } }

//
// Non-volatile variable that stores the UI configuration. Both the setup
// driver's efivarstore and the LVGL library reference this exact name/GUID.
//
#define LVGL_UI_CONFIG_VAR_NAME  L"LvglUiScale"

//
// UI scale factors. Values are stored as-is in the variable's UiScale field.
//   1x   : native resolution, base theme metrics (default)
//   1.5x : larger fonts and layout via LvglThemeLib (3/2)
//   2x   : larger fonts and layout via LvglThemeLib (2/1)
//
#define LVGL_UI_SCALE_1X       0
#define LVGL_UI_SCALE_1_5X     1
#define LVGL_UI_SCALE_2X       2
#define LVGL_UI_SCALE_DEFAULT  LVGL_UI_SCALE_1X

#pragma pack(1)
typedef struct {
  UINT8    UiScale;
  UINT8    CenteredFrameEnabled;
  UINT8    CenteredFrameHeightPct;
  UINT8    CenteredFrameAspectNum;
  UINT8    CenteredFrameAspectDen;
  UINT8    SubtitleShowsDeviceModel;
} LVGL_UI_CONFIG_VARSTORE_DATA;
#pragma pack()

extern EFI_GUID  gLvglUiConfigFormSetGuid;

#endif // LVGL_UI_CONFIG_H_
