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
  Resets the entire platform (cold).

  The PMC full-reset register drives both cold and warm resets on
  2K1000LA; the SoC does not distinguish the two.
**/
VOID
EFIAPI
ResetCold (
  VOID
  )
{
  LoongsonWarmReset ();
  CpuDeadLoop ();
}

/**
  Resets the entire platform (warm).
**/
VOID
EFIAPI
ResetWarm (
  VOID
  )
{
  LoongsonWarmReset ();
  CpuDeadLoop ();
}

/**
  Powers down the platform (ACPI G2/S5).
**/
VOID
EFIAPI
ResetShutdown (
  VOID
  )
{
  LoongsonShutdown ();
  CpuDeadLoop ();
}

/**
  Resets the platform; the reset subtype GUID carried in ResetData is
  not interpreted, a warm reset is performed.
**/
VOID
EFIAPI
ResetPlatformSpecific (
  IN UINTN  DataSize,
  IN VOID   *ResetData
  )
{
  LoongsonWarmReset ();
  CpuDeadLoop ();
}

/**
  S3 resume is not supported by this platform; fall back to a cold reset.
**/
VOID
EFIAPI
EnterS3WithImmediateWake (
  VOID
  )
{
  LoongsonWarmReset ();
  CpuDeadLoop ();
}

/**
  Resets the entire platform.
**/
VOID
EFIAPI
ResetSystem (
  IN EFI_RESET_TYPE  ResetType,
  IN EFI_STATUS      ResetStatus,
  IN UINTN           DataSize,
  IN VOID            *ResetData OPTIONAL
  )
{
  switch (ResetType) {
    case EfiResetShutdown:
      LoongsonShutdown ();
      break;

    case EfiResetPlatformSpecific:
    case EfiResetWarm:
    case EfiResetCold:
    default:
      //
      // Unknown reset types fall back to a warm reset.
      //
      LoongsonWarmReset ();
      break;
  }

  //
  // If the reset fails, just hang.
  //
  CpuDeadLoop ();
}
