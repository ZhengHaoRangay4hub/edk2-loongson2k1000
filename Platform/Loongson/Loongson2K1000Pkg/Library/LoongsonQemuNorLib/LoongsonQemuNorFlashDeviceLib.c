/** @file
  QEMU-only VirtNorFlashDeviceLib for the Loongson 2K1000LA education board.

  QEMU's ls2k machine backs only the first 1 MB of the SPI NOR with the
  firmware image ("spi bios"); 0x1c100000 and up is an empty romd region, so
  everything behind the 1 MB window reads back as zero and writes are dropped
  without an error.  VirtNorFlashDxe cannot format a variable store there, and
  without a formatted store it never installs gEdkiiNvVarStoreFormattedGuid,
  which in turn keeps Variable/FTW/BdsDxe from ever being dispatched.

  With -D QEMU_FIT=TRUE the platform therefore parks the variable store in the
  DRAM hole between the top of the low DDR window (0x0F000000) and the SoC MMIO
  window (0x10000000) - see the PcdFlashNvStorage*Base64 and
  PcdLoongsonSpiNor* overrides in Loongson2K1000Pkg.dsc - and this library
  implements NOR semantics on top of that plain DRAM.

  It is a smoke-test vehicle: it lets the DXE variable, FTW and BDS chain run
  under QEMU so the platform code around it can be validated.  It is never part
  of a board image; those use LoongsonSpiNorFlashDeviceLib, which drives the
  on-chip SPI controller instead.

  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#include <Base.h>
#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/DebugLib.h>
#include <Library/VirtNorFlashDeviceLib.h>

/*
 * Matches the 4K sector size the SPI NOR part and LoongsonSpiNorFlashPlatformLib
 * report; VirtNorFlashDxe's erase call passes a block address only.
 */
#define QEMU_NOR_BLOCK_SIZE  0x1000

STATIC
VOID
QemuNorProgram (
  IN UINTN  Address,
  IN UINT8  Value
  )
{
  //
  // NOR program can only clear bits (erase polarity is 1).
  //
  *(volatile UINT8 *)Address &= Value;
}

EFI_STATUS
EFIAPI
NorFlashReadBlocks (
  IN UINTN    DeviceBaseAddress,
  IN UINTN    RegionBaseAddress,
  IN EFI_LBA  Lba,
  IN EFI_LBA  LastBlock,
  IN UINT32   BlockSize,
  IN UINTN    BufferSizeInBytes,
  OUT VOID    *Buffer
  )
{
  UINTN  StartAddress;

  if ((Lba > LastBlock) ||
      (BufferSizeInBytes > ((UINTN)LastBlock - (UINTN)Lba + 1) * BlockSize) ||
      ((BufferSizeInBytes % BlockSize) != 0 && ((UINTN)Lba != LastBlock)))
  {
    return EFI_INVALID_PARAMETER;
  }

  StartAddress = GET_NOR_BLOCK_ADDRESS (RegionBaseAddress, Lba, BlockSize);

  CopyMem (Buffer, (VOID *)StartAddress, BufferSizeInBytes);

  return EFI_SUCCESS;
}

EFI_STATUS
EFIAPI
NorFlashRead (
  IN UINTN    DeviceBaseAddress,
  IN UINTN    RegionBaseAddress,
  IN EFI_LBA  Lba,
  IN UINT32   BlockSize,
  IN UINTN    Size,
  IN UINTN    Offset,
  IN UINTN    BufferSizeInBytes,
  OUT VOID    *Buffer
  )
{
  UINTN  StartAddress;

  if (BufferSizeInBytes > Size) {
    return EFI_INVALID_PARAMETER;
  }

  StartAddress = GET_NOR_BLOCK_ADDRESS (RegionBaseAddress, Lba, BlockSize) + Offset;

  CopyMem (Buffer, (VOID *)StartAddress, BufferSizeInBytes);

  return EFI_SUCCESS;
}

EFI_STATUS
EFIAPI
NorFlashWriteSingleBlock (
  IN UINTN      DeviceBaseAddress,
  IN UINTN      RegionBaseAddress,
  IN EFI_LBA    Lba,
  IN UINT32     LastBlock,
  IN UINT32     BlockSize,
  IN UINTN      Size,
  IN UINTN      Offset,
  IN OUT UINTN  *NumBytes,
  IN UINT8      *Buffer,
  IN VOID       *ShadowBuffer
  )
{
  UINTN  StartAddress;
  UINTN  Index;

  if ((Lba > LastBlock) || (Offset + *NumBytes > BlockSize)) {
    return EFI_INVALID_PARAMETER;
  }

  StartAddress = GET_NOR_BLOCK_ADDRESS (RegionBaseAddress, Lba, BlockSize) + Offset;

  for (Index = 0; Index < *NumBytes; Index++) {
    QemuNorProgram (StartAddress + Index, Buffer[Index]);
  }

  return EFI_SUCCESS;
}

EFI_STATUS
EFIAPI
NorFlashWriteBlocks (
  IN UINTN    DeviceBaseAddress,
  IN UINTN    RegionBaseAddress,
  IN EFI_LBA  Lba,
  IN EFI_LBA  LastBlock,
  IN UINT32   BlockSize,
  IN UINTN    BufferSizeInBytes,
  IN VOID     *Buffer
  )
{
  UINTN  StartAddress;
  UINTN  Index;

  if ((Lba > LastBlock) ||
      (BufferSizeInBytes > ((UINTN)LastBlock - (UINTN)Lba + 1) * BlockSize))
  {
    return EFI_INVALID_PARAMETER;
  }

  StartAddress = GET_NOR_BLOCK_ADDRESS (RegionBaseAddress, Lba, BlockSize);

  for (Index = 0; Index < BufferSizeInBytes; Index++) {
    QemuNorProgram (StartAddress + Index, ((UINT8 *)Buffer)[Index]);
  }

  return EFI_SUCCESS;
}

EFI_STATUS
EFIAPI
NorFlashWriteSingleWord (
  IN UINTN   DeviceBaseAddress,
  IN UINTN   WordAddress,
  IN UINT32  WriteData
  )
{
  UINTN  Index;

  for (Index = 0; Index < sizeof (UINT32); Index++) {
    QemuNorProgram (WordAddress + Index, (UINT8)(WriteData >> (Index * 8)));
  }

  return EFI_SUCCESS;
}

EFI_STATUS
EFIAPI
NorFlashWriteBuffer (
  IN UINTN   DeviceBaseAddress,
  IN UINTN   TargetAddress,
  IN UINTN   BufferSizeInBytes,
  IN UINT32  *Buffer
  )
{
  UINTN  Index;

  for (Index = 0; Index < BufferSizeInBytes; Index++) {
    QemuNorProgram (TargetAddress + Index, ((UINT8 *)Buffer)[Index]);
  }

  return EFI_SUCCESS;
}

EFI_STATUS
EFIAPI
NorFlashWriteFullBlock (
  IN UINTN     DeviceBaseAddress,
  IN UINTN     RegionBaseAddress,
  IN EFI_LBA   Lba,
  IN UINT32    *DataBuffer,
  IN UINT32    BlockSizeInWords
  )
{
  return NorFlashWriteBuffer (
           DeviceBaseAddress,
           GET_NOR_BLOCK_ADDRESS (RegionBaseAddress, Lba, BlockSizeInWords * sizeof (UINT32)),
           BlockSizeInWords * sizeof (UINT32),
           DataBuffer
           );
}

EFI_STATUS
EFIAPI
NorFlashEraseSingleBlock (
  IN UINTN  DeviceBaseAddress,
  IN UINTN  BlockAddress
  )
{
  SetMem ((VOID *)BlockAddress, QEMU_NOR_BLOCK_SIZE, 0xFF);

  return EFI_SUCCESS;
}

EFI_STATUS
EFIAPI
NorFlashUnlockSingleBlockIfNecessary (
  IN UINTN  DeviceBaseAddress,
  IN UINTN  BlockAddress
  )
{
  return EFI_SUCCESS;
}

EFI_STATUS
EFIAPI
NorFlashUnlockAndEraseSingleBlock (
  IN UINTN  DeviceBaseAddress,
  IN UINTN  BlockAddress
  )
{
  return NorFlashEraseSingleBlock (DeviceBaseAddress, BlockAddress);
}

EFI_STATUS
EFIAPI
NorFlashReset (
  IN UINTN  DeviceBaseAddress
  )
{
  return EFI_SUCCESS;
}