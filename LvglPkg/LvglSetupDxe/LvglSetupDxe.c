/** @file
  Setup driver that publishes the LVGL UI configuration form.

  Presents graphical UI settings (software UI scale and centered-frame layout)
  and seeds the backing non-volatile variable with platform PCD defaults on
  first boot. The form uses an efivarstore, so the setup browser reads and
  writes the variable directly; no ConfigAccess protocol is required.

  Copyright (c) 2026, MrChromebox. All rights reserved.<BR>
  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#include <Uefi.h>
#include <Library/DebugLib.h>
#include <Library/DevicePathLib.h>
#include <Library/HiiLib.h>
#include <Library/LvglUiConfigLib.h>
#include <Library/UefiBootServicesTableLib.h>

#include <Guid/LvglUiConfig.h>

extern UINT8  LvglSetupDxeVfrBin[];
extern UINT8  LvglSetupDxeStrings[];

typedef struct {
  VENDOR_DEVICE_PATH          VendorDevicePath;
  EFI_DEVICE_PATH_PROTOCOL    End;
} HII_VENDOR_DEVICE_PATH;

STATIC HII_VENDOR_DEVICE_PATH  mVendorDevicePath = {
  {
    {
      HARDWARE_DEVICE_PATH,
      HW_VENDOR_DP,
      {
        (UINT8)(sizeof (VENDOR_DEVICE_PATH)),
        (UINT8)((sizeof (VENDOR_DEVICE_PATH)) >> 8)
      }
    },
    LVGL_UI_CONFIG_FORMSET_GUID
  },
  {
    END_DEVICE_PATH_TYPE,
    END_ENTIRE_DEVICE_PATH_SUBTYPE,
    {
      (UINT8)(END_DEVICE_PATH_LENGTH),
      (UINT8)((END_DEVICE_PATH_LENGTH) >> 8)
    }
  }
};

/**
  Install the HII form package and its vendor device path.

  @retval EFI_SUCCESS  The pages were installed.
**/
STATIC
EFI_STATUS
InstallHiiPages (
  VOID
  )
{
  EFI_STATUS      Status;
  EFI_HII_HANDLE  HiiHandle;
  EFI_HANDLE      DriverHandle;

  DriverHandle = NULL;
  Status       = gBS->InstallMultipleProtocolInterfaces (
                        &DriverHandle,
                        &gEfiDevicePathProtocolGuid,
                        &mVendorDevicePath,
                        NULL
                        );
  if (EFI_ERROR (Status)) {
    return Status;
  }

  HiiHandle = HiiAddPackages (
                &gLvglUiConfigFormSetGuid,
                DriverHandle,
                LvglSetupDxeStrings,
                LvglSetupDxeVfrBin,
                NULL
                );
  if (HiiHandle == NULL) {
    gBS->UninstallMultipleProtocolInterfaces (
           DriverHandle,
           &gEfiDevicePathProtocolGuid,
           &mVendorDevicePath,
           NULL
           );
    return EFI_OUT_OF_RESOURCES;
  }

  return EFI_SUCCESS;
}

/**
  Entry point for the LVGL UI configuration setup driver.

  @param[in] ImageHandle  The image handle of the driver.
  @param[in] SystemTable  The system table.

  @retval EFI_SUCCESS  The operation completed successfully.
**/
EFI_STATUS
EFIAPI
LvglSetupInitialize (
  IN EFI_HANDLE        ImageHandle,
  IN EFI_SYSTEM_TABLE  *SystemTable
  )
{
  LvglUiConfigEnsureVariable ();
  return InstallHiiPages ();
}
