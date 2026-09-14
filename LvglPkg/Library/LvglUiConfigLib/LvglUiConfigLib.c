/** @file
  LVGL UI configuration helpers.

  Copyright (c) 2026, MrChromebox. All rights reserved.<BR>
  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#include <Library/LvglUiConfigLib.h>
#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/DebugLib.h>
#include <Library/PcdLib.h>
#include <Library/UefiRuntimeServicesTableLib.h>

/**
  Clamp persisted values to sane ranges.
**/
STATIC
VOID
LvglUiConfigSanitize (
  IN OUT LVGL_UI_CONFIG_VARSTORE_DATA  *Config
  )
{
  if ((Config->UiScale != LVGL_UI_SCALE_1_5X) && (Config->UiScale != LVGL_UI_SCALE_2X)) {
    Config->UiScale = LVGL_UI_SCALE_1X;
  }

  Config->CenteredFrameEnabled = (Config->CenteredFrameEnabled != 0) ? 1 : 0;

  if (Config->CenteredFrameHeightPct == 0) {
    Config->CenteredFrameHeightPct = PcdGet8 (PcdLvglCenteredFrameHeightPct);
  }

  if (Config->CenteredFrameHeightPct > 100) {
    Config->CenteredFrameHeightPct = 100;
  }

  if (Config->CenteredFrameAspectNum == 0) {
    Config->CenteredFrameAspectNum = PcdGet8 (PcdLvglCenteredFrameAspectNum);
  }

  if (Config->CenteredFrameAspectDen == 0) {
    Config->CenteredFrameAspectDen = PcdGet8 (PcdLvglCenteredFrameAspectDen);
  }

  Config->SubtitleShowsDeviceModel = (Config->SubtitleShowsDeviceModel != 0) ? 1 : 0;
}

VOID
EFIAPI
LvglUiConfigGetDefaults (
  OUT LVGL_UI_CONFIG_VARSTORE_DATA  *Config
  )
{
  ASSERT (Config != NULL);

  Config->UiScale                 = LVGL_UI_SCALE_DEFAULT;
  Config->CenteredFrameEnabled      = PcdGetBool (PcdLvglCenteredFrameEnabled) ? 1 : 0;
  Config->CenteredFrameHeightPct    = PcdGet8 (PcdLvglCenteredFrameHeightPct);
  Config->CenteredFrameAspectNum    = PcdGet8 (PcdLvglCenteredFrameAspectNum);
  Config->CenteredFrameAspectDen    = PcdGet8 (PcdLvglCenteredFrameAspectDen);
  Config->SubtitleShowsDeviceModel  = PcdGetBool (PcdLvglAptioSubtitleShowsDeviceModel) ? 1 : 0;

  LvglUiConfigSanitize (Config);
}

EFI_STATUS
EFIAPI
LvglUiConfigLoad (
  OUT LVGL_UI_CONFIG_VARSTORE_DATA  *Config
  )
{
  EFI_STATUS  Status;
  UINTN       Size;

  if (Config == NULL) {
    return EFI_INVALID_PARAMETER;
  }

  Size   = sizeof (*Config);
  Status = gRT->GetVariable (
                  LVGL_UI_CONFIG_VAR_NAME,
                  &gLvglUiConfigFormSetGuid,
                  NULL,
                  &Size,
                  Config
                  );
  if (!EFI_ERROR (Status) && (Size == sizeof (*Config))) {
    LvglUiConfigSanitize (Config);
    return EFI_SUCCESS;
  }

  LvglUiConfigGetDefaults (Config);
  return EFI_NOT_FOUND;
}

VOID
EFIAPI
LvglUiConfigEnsureVariable (
  VOID
  )
{
  EFI_STATUS                    Status;
  LVGL_UI_CONFIG_VARSTORE_DATA  Config;
  UINTN                         Size;

  Size   = sizeof (Config);
  Status = gRT->GetVariable (
                  LVGL_UI_CONFIG_VAR_NAME,
                  &gLvglUiConfigFormSetGuid,
                  NULL,
                  &Size,
                  &Config
                  );
  if (!EFI_ERROR (Status) && (Size == sizeof (Config))) {
    return;
  }

  LvglUiConfigGetDefaults (&Config);
  LvglUiConfigSanitize (&Config);

  Status = gRT->SetVariable (
                  LVGL_UI_CONFIG_VAR_NAME,
                  &gLvglUiConfigFormSetGuid,
                  EFI_VARIABLE_NON_VOLATILE | EFI_VARIABLE_BOOTSERVICE_ACCESS,
                  sizeof (Config),
                  &Config
                  );
  DEBUG ((
    DEBUG_INFO,
    "LvglUiConfigLib: seeded %s (scale=%u frame=%u %u:%u@%u%% subtitle=%u) %r\n",
    LVGL_UI_CONFIG_VAR_NAME,
    Config.UiScale,
    Config.CenteredFrameEnabled,
    Config.CenteredFrameAspectNum,
    Config.CenteredFrameAspectDen,
    Config.CenteredFrameHeightPct,
    Config.SubtitleShowsDeviceModel,
    Status
    ));
}
