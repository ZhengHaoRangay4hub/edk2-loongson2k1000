/** @file
  LVGL UI configuration helpers.

  Loads the non-volatile LvglUiScale variable published by LvglSetupDxe.
  When the variable is absent, PCD defaults from the platform DSC are used
  instead.

  Copyright (c) 2026, MrChromebox. All rights reserved.<BR>
  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#ifndef LVGL_UI_CONFIG_LIB_H_
#define LVGL_UI_CONFIG_LIB_H_

#include <Uefi.h>
#include <Guid/LvglUiConfig.h>

/**
  Fill @a Config with platform PCD defaults.
**/
VOID
EFIAPI
LvglUiConfigGetDefaults (
  OUT LVGL_UI_CONFIG_VARSTORE_DATA  *Config
  );

/**
  Load the persisted UI configuration.

  Reads the LvglUiScale NVRAM variable when present with the expected size.
  If the variable is absent or has an unexpected size, @a Config is filled
  from PCD defaults and EFI_NOT_FOUND is returned.

  @param[out] Config  Loaded or default configuration.

  @retval EFI_SUCCESS       Variable read successfully.
  @retval EFI_NOT_FOUND     Variable absent; @a Config holds PCD defaults.
  @retval EFI_INVALID_PARAMETER  @a Config is NULL.
**/
EFI_STATUS
EFIAPI
LvglUiConfigLoad (
  OUT LVGL_UI_CONFIG_VARSTORE_DATA  *Config
  );

/**
  Seed the LvglUiScale variable when it is absent or has an unexpected size.
**/
VOID
EFIAPI
LvglUiConfigEnsureVariable (
  VOID
  );

#endif // LVGL_UI_CONFIG_LIB_H_
