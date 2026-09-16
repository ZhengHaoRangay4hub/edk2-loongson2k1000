/** @file
  NOR flash platform description for Loongson 2K1000LA.

  The SPI NOR is mapped read-only (XIP) at 0x1c000000. A 16MB part is
  assumed; the UEFI variable store lives in the tail of the 4MB firmware
  image, right behind FVMAIN_COMPACT (offset 0x370000, see
  PcdLoongsonSpiNorVarStoreOffset).

  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#include <PiDxe.h>
#include <Library/DebugLib.h>
#include <Library/PcdLib.h>
#include <Library/VirtNorFlashPlatformLib.h>

STATIC VIRT_NOR_FLASH_DESCRIPTION  mNorFlashDevice =
{
  0,             /* DeviceBaseAddress, filled at runtime */
  0,             /* RegionBaseAddress, filled at runtime */
  0,             /* Size, filled at runtime */
  0x1000         /* BlockSize, 4K SPI sectors */
};

EFI_STATUS
VirtNorFlashPlatformInitialization (
  VOID
  )
{
  return EFI_SUCCESS;
}

EFI_STATUS
VirtNorFlashPlatformGetDevices (
  OUT VIRT_NOR_FLASH_DESCRIPTION  **NorFlashDescriptions,
  OUT UINT32                      *Count
  )
{
  UINTN  FlashBase;

  FlashBase = (UINTN)FixedPcdGet64 (PcdLoongsonSpiNorBaseAddress);

  mNorFlashDevice.DeviceBaseAddress = FlashBase;
  mNorFlashDevice.RegionBaseAddress = FlashBase + FixedPcdGet32 (PcdLoongsonSpiNorVarStoreOffset);
  mNorFlashDevice.Size              = FixedPcdGet32 (PcdLoongsonSpiNorVarStoreSize);

  *NorFlashDescriptions = &mNorFlashDevice;
  *Count                = 1;

  return EFI_SUCCESS;
}
