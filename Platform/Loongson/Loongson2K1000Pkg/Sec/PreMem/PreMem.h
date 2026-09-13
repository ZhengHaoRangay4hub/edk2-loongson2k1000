/** @file
  Pre-memory (SEC) stage declarations for Loongson 2K1000LA.

  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#ifndef __PREMEM_H__
#define __PREMEM_H__

#include <Uefi.h>

/*
 * Early 16550 serial output helpers implemented in LoongsonPreMem.c.
 * They access the UART through the uncached DMW window and never touch
 * .data/.bss (the SEC runs in-place from SPI NOR before DRAM exists).
 */
VOID
EarlySerialInit (
  VOID
  );

VOID
EarlyPutString (
  IN CONST CHAR8  *String
  );

/*
 * Assembly entry points (PmonPreSerial.S / ClkSetting.S / DdrEntry.S).
 * All of them are position independent and only use registers/stack.
 */
VOID  EarlySerialReinitAfterPll (VOID);  /* initserial_later */
VOID  ClkSettingAsm (VOID);              /* CPU/DDR/GPU PLL programming */
VOID  DdrEntryAsm (VOID);                /* LSMC DDR3 init + leveling */

/*
 * Locate the raw DTB file (FileGuid) in the firmware volume at FvBase,
 * copy it to Destination and return its size. Returns 0 when not found.
 */
UINTN
CopyDtbFromFv (
  IN EFI_PHYSICAL_ADDRESS  FvBase,
  IN EFI_PHYSICAL_ADDRESS  Destination
  );

#endif /* __PREMEM_H__ */
