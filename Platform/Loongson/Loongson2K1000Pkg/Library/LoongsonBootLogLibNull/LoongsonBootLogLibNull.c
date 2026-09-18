/** @file
  Null instance of the boot progress log.

  The QEMU regression target runs on the generic LoongArch `virt` machine, which
  has no 2K1000 SPI controller at 0x1fff0220; writing there would raise a guest
  address error.  The target still links the board's PlatformBootManagerLib (so
  it exercises the same BDS policy), hence this null instance satisfies the
  library class without touching any hardware.

  Copyright (c) 2026, Loongson2K1000LA EDK2 port contributors.
  SPDX-License-Identifier: BSD-2-Clause-Patent

**/

#include <Base.h>
#include <Library/LoongsonBootLog.h>

VOID
EFIAPI
LoongsonBootLogBoot (
  VOID
  )
{
}

VOID
EFIAPI
LoongsonBootLogEvent (
  IN UINT8   Code,
  IN UINT32  Arg
  )
{
  (VOID)Code;
  (VOID)Arg;
}
