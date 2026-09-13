/** @file
  ResetSystemLib for Loongson 2K1000LA.

  Reset and poweroff are controlled through the PMC block (syscon):
    reboot   : PMC + 0x30 = 1
    poweroff : PMC + 0x14 = 0x3c00

  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#include <Base.h>
#include <Library/BaseLib.h>
#include <Library/DebugLib.h>
#include <Library/IoLib.h>
#include <Library/PcdLib.h>
#include <Library/ResetSystemLib.h>

#define PMC_BASE  ((UINTN)(0x9000000000000000ULL | (UINT64)FixedPcdGet32 (PcdLoongsonPmcBaseAddress)))

/**
  This function causes the system to perform a warm reset.
**/
STATIC
VOID
LoongsonWarmReset (
  VOID
  )
{
  MmioWrite32 (PMC_BASE + 0x30, 0x1);
}

/**
  This function causes the system to enter a power state equivalent
  to the ACPI G2/S5 state.
**/
STATIC
VOID
LoongsonShutdown (
  VOID
  )
{
  MmioWrite32 (PMC_BASE + 0x14, 0x3c00);
}

/**
  Resets the entire platform.
**/
EFI_STATUS
EFIAPI
ResetSystem (
  IN EFI_RESET_TYPE  ResetType,
  IN EFI_STATUS      ResetStatus,
  IN UINTN           DataSize,
  IN VOID            *ResetData OPTIONAL
  )
{
  switch (ResetType) {
    case EfiResetPlatformSpecific:
    case EfiResetWarm:
    case EfiResetCold:
      LoongsonWarmReset ();
      break;

    case EfiResetShutdown:
      LoongsonShutdown ();
      break;

    default:
      return EFI_INVALID_PARAMETER;
  }

  //
  // If the reset fails, just hang.
  //
  CpuDeadLoop ();

  return EFI_SUCCESS;
}
