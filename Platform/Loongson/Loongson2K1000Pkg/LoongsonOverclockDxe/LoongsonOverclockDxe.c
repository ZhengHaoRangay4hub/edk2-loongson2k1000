/** @file
  Loongson 2K1000LA overclocking setup page.

  Publishes an HII formset (Platform Setup class) that lets the user pick
  the CPU core clock; the choice is persisted in the "LoongsonOcCfg"
  variable and programmed into the CPU PLL (0x1fe00480) before boot,
  using the PMON ClkSetting sequence:
    node_clock = 100MHz / L1_REFC(4) * L1_LOOPC / L1_DIV(1) / L2_DIV(2)

  Copyright (c) 2026, Loongson2K1000LA EDK2 port contributors.
  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#include <PiDxe.h>
#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/DebugLib.h>
#include <Library/HiiLib.h>
#include <Library/IoLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/PrintLib.h>
#include <Library/UefiHiiServicesLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiRuntimeServicesTableLib.h>
#include <Library/UefiLib.h>
#include <Protocol/HiiConfigAccess.h>
#include <Protocol/HiiConfigRouting.h>

#include "OverclockStorage.h"

#define LS_MMIO_UNCACHED(Base)  (0x9000000000000000ULL | (UINT64)(Base))
#define CPU_PLL_BASE            0x1fe00480

#define PLL_L1_ENA              (1ULL << 2)
#define PLL_L1_LOCKED           (1ULL << 16)
#define PLL_CHANG_COMMIT        1ULL
#define PLL_POWER_DOWN          (1ULL << 19)

extern UINT8  OverclockFormsBin[];
extern UINT8  OverclockStringsBin[];

STATIC LOONGSON_OC_CONFIG               mOcConfig;
STATIC EFI_HII_CONFIG_ACCESS_PROTOCOL   mConfigAccess;
STATIC EFI_HII_HANDLE                   mHiiHandle;
STATIC EFI_HANDLE                       mDriverHandle;
STATIC EFI_EVENT                        mReadyToBootEvent;

STATIC CONST EFI_GUID  mOcVarGuid     = LOONGSON_OC_VAR_GUID;
STATIC CONST EFI_GUID  mOcFormsetGuid = LOONGSON_OC_FORMSET_GUID;

/**
  Program the CPU PLL for the requested core clock (MHz).

  Sequence ported verbatim from PMON ClkSetting.S (soft CLK SEL adjust):
  power-down L1, load dividers, enable, wait lock, commit.
**/
STATIC
VOID
ApplyCpuPll (
  IN UINT32  FreqMhz
  )
{
  UINTN   Base  = LS_MMIO_UNCACHED (CPU_PLL_BASE);
  UINTN   Loopc = ((UINTN)FreqMhz * 8) / 100;          /* Freq / 12.5 */
  UINT64  Cfg;

  if (FreqMhz < 200) {
    return;
  }

  Cfg = ((UINT64)Loopc << 32) | (1ULL << 42) | (4ULL << 26) | (0x3ULL << 10) | (1ULL << 7);

  MmioWrite64 (Base, PLL_POWER_DOWN);
  MmioWrite64 (Base, Cfg);
  MmioWrite64 (Base + 8, 2);                         /* L2_DIV */
  MmioWrite64 (Base, Cfg | PLL_L1_ENA);

  while ((MmioRead64 (Base) & PLL_L1_LOCKED) == 0) {
  }

  MmioWrite64 (Base, MmioRead64 (Base) | PLL_CHANG_COMMIT);

  DEBUG ((DEBUG_INFO, "%a: CPU PLL set for %u MHz (loopc=%u)\n", __func__, FreqMhz, Loopc));
}

/**
  Load the persisted selection (defaults when absent or corrupt).
**/
STATIC
VOID
OcConfigLoad (
  VOID
  )
{
  UINTN      Size;
  EFI_STATUS Status;

  Size   = sizeof (mOcConfig);
  Status = gRT->GetVariable ((CHAR16 *)LOONGSON_OC_VAR_NAME, (EFI_GUID *)&mOcVarGuid, NULL, &Size, &mOcConfig);
  if (EFI_ERROR (Status) || (mOcConfig.CpuFreq > OC_CPU_1200)) {
    mOcConfig.CpuFreq = OC_CPU_DEFAULT;
  }
}

/**
  Convert the stored selector to a frequency in MHz.
**/
STATIC
UINT32
OcFreqMhz (
  VOID
  )
{
  STATIC CONST UINT32  Table[] = { 800, 900, 1000, 1100, 1200 };

  if (mOcConfig.CpuFreq > OC_CPU_1200) {
    return 1000;
  }
  return Table[mOcConfig.CpuFreq];
}

/* ---------------- HII ConfigAccess ---------------- */

STATIC
EFI_STATUS
EFIAPI
OcExtractConfig (
  IN  CONST EFI_HII_CONFIG_ACCESS_PROTOCOL  *This,
  IN  CONST EFI_STRING                      Request,
  OUT EFI_STRING                            *Progress,
  OUT EFI_STRING                            *Results
  )
{
  EFI_STATUS  Status;
  EFI_STRING  ConfigRequestHdr;
  EFI_STRING  ConfigRequest;
  UINTN       Size;
  BOOLEAN     AllocatedRequest;

  if ((Progress == NULL) || (Results == NULL)) {
    return EFI_INVALID_PARAMETER;
  }

  ConfigRequestHdr = NULL;
  ConfigRequest    = NULL;
  Size             = 0;
  AllocatedRequest = FALSE;

  *Progress = Request;
  if ((Request != NULL) && !HiiIsConfigHdrMatch (Request, &mOcVarGuid, LOONGSON_OC_VAR_NAME)) {
    return EFI_NOT_FOUND;
  }

  if ((Request == NULL) || (StrStr (Request, L"OFFSET") == NULL)) {
    ConfigRequestHdr = HiiConstructConfigHdr (&mOcVarGuid, LOONGSON_OC_VAR_NAME, mDriverHandle);
    if (ConfigRequestHdr == NULL) {
      return EFI_OUT_OF_RESOURCES;
    }

    Size             = (StrLen (ConfigRequestHdr) + 32 + 1) * sizeof (CHAR16);
    ConfigRequest    = AllocateZeroPool (Size);
    AllocatedRequest = TRUE;
    if (ConfigRequest == NULL) {
      FreePool (ConfigRequestHdr);
      return EFI_OUT_OF_RESOURCES;
    }

    UnicodeSPrint (
      ConfigRequest,
      Size,
      L"%s&OFFSET=0&WIDTH=%016LX",
      ConfigRequestHdr,
      (UINT64)sizeof (LOONGSON_OC_CONFIG)
      );
    FreePool (ConfigRequestHdr);
  } else {
    ConfigRequest = (EFI_STRING)Request;
  }

  Status = gHiiConfigRouting->BlockToConfig (
                                gHiiConfigRouting,
                                ConfigRequest,
                                (VOID *)&mOcConfig,
                                sizeof (mOcConfig),
                                Results,
                                Progress
                                );

  if (AllocatedRequest) {
    FreePool (ConfigRequest);
    if (Request == NULL) {
      *Progress = NULL;
    } else if (EFI_ERROR (Status)) {
      *Progress = Request;
    } else {
      *Progress = Request + StrLen (Request);
    }
  }

  return Status;
}

STATIC
EFI_STATUS
EFIAPI
OcRouteConfig (
  IN  CONST EFI_HII_CONFIG_ACCESS_PROTOCOL  *This,
  IN  CONST EFI_STRING                      Configuration,
  OUT EFI_STRING                            *Progress
  )
{
  EFI_STATUS  Status;
  UINTN       BufferSize;

  if ((Configuration == NULL) || (Progress == NULL)) {
    return EFI_INVALID_PARAMETER;
  }

  *Progress = Configuration;
  if (!HiiIsConfigHdrMatch (Configuration, &mOcVarGuid, LOONGSON_OC_VAR_NAME)) {
    return EFI_NOT_FOUND;
  }

  BufferSize = sizeof (mOcConfig);
  Status     = gHiiConfigRouting->ConfigToBlock (
                                    gHiiConfigRouting,
                                    (EFI_STRING)Configuration,
                                    (VOID *)&mOcConfig,
                                    &BufferSize,
                                    Progress
                                    );
  if (EFI_ERROR (Status)) {
    return Status;
  }

  if (mOcConfig.CpuFreq > OC_CPU_1200) {
    mOcConfig.CpuFreq = OC_CPU_DEFAULT;
  }

  return gRT->SetVariable (
                (CHAR16 *)LOONGSON_OC_VAR_NAME,
                (EFI_GUID *)&mOcVarGuid,
                EFI_VARIABLE_NON_VOLATILE | EFI_VARIABLE_BOOTSERVICE_ACCESS |
                EFI_VARIABLE_RUNTIME_ACCESS,
                sizeof (mOcConfig),
                &mOcConfig
                );
}

STATIC
EFI_STATUS
EFIAPI
OcCallback (
  IN  CONST EFI_HII_CONFIG_ACCESS_PROTOCOL  *This,
  IN  EFI_BROWSER_ACTION                    Action,
  IN  EFI_QUESTION_ID                       QuestionId,
  IN  UINT8                                 Type,
  IN  EFI_IFR_TYPE_VALUE                    *Value,
  OUT EFI_BROWSER_ACTION_REQUEST            *ActionRequest
  )
{
  if ((ActionRequest == NULL) || (Value == NULL)) {
    return EFI_INVALID_PARAMETER;
  }

  if (Action != EFI_BROWSER_ACTION_CHANGED) {
    return EFI_UNSUPPORTED;
  }

  //
  // The browser pushes the new selection through RouteConfig on submit;
  // nothing else to do here.
  //
  *ActionRequest = EFI_BROWSER_ACTION_REQUEST_NONE;
  return EFI_SUCCESS;
}

/* ---------------- driver ---------------- */

STATIC
VOID
EFIAPI
OnReadyToBoot (
  IN EFI_EVENT  Event,
  IN VOID       *Context
  )
{
  //
  // Apply the programmed clock at every boot before the OS starts.
  //
  ApplyCpuPll (OcFreqMhz ());
}

EFI_STATUS
EFIAPI
LoongsonOverclockDxeEntryPoint (
  IN EFI_HANDLE        ImageHandle,
  IN EFI_SYSTEM_TABLE  *SystemTable
  )
{
  EFI_STATUS  Status;

  OcConfigLoad ();

  mConfigAccess.ExtractConfig = OcExtractConfig;
  mConfigAccess.RouteConfig   = OcRouteConfig;
  mConfigAccess.Callback      = OcCallback;

  mDriverHandle = NULL;
  Status = gBS->InstallMultipleProtocolInterfaces (
                  &mDriverHandle,
                  &gEfiDevicePathProtocolGuid,
                  NULL,
                  &gEfiHiiConfigAccessProtocolGuid,
                  &mConfigAccess,
                  NULL
                  );
  if (EFI_ERROR (Status)) {
    return Status;
  }

  mHiiHandle = HiiAddPackages (
                 &mOcFormsetGuid,
                 mDriverHandle,
                 OverclockStringsBin,
                 OverclockFormsBin,
                 NULL
                 );
  if (mHiiHandle == NULL) {
    gBS->UninstallMultipleProtocolInterfaces (
           mDriverHandle,
           &gEfiDevicePathProtocolGuid,
           NULL,
           &gEfiHiiConfigAccessProtocolGuid,
           &mConfigAccess,
           NULL
           );
    return EFI_OUT_OF_RESOURCES;
  }

  Status = EfiCreateEventReadyToBootEx (
             TPL_CALLBACK,
             OnReadyToBoot,
             NULL,
             &mReadyToBootEvent
             );
  if (EFI_ERROR (Status)) {
    DEBUG ((DEBUG_WARN, "%a: ReadyToBoot hook failed, clock stays at SEC setting\n", __func__));
  }

  DEBUG ((DEBUG_INFO, "%a: overclocking page ready (cpu=%u MHz)\n", __func__, OcFreqMhz ()));
  return EFI_SUCCESS;
}
