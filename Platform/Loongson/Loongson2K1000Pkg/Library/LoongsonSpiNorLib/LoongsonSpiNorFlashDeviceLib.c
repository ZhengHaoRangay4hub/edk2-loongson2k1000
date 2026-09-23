/** @file
  VirtNorFlashDeviceLib implementation for the Loongson 2K1000LA
  on-chip SPI flash controller ("loongson,ls-spi" @ 0x1fff0220).

  Reads are served from the XIP window; erase and program go through the
  SPI controller command engine, following the sequences used by Loongson
  PMON (Targets/ls2k/dev/spi_w.c):
    - soft CS:  SOFTCS = 0x01 (assert) / 0x11 (release)
    - init:     SPSR=0xc0, PARAM=0x10, PARAM2=0x01, SPER=0x04, SPCR=0x51
    - erase 4K: WREN, cmd 0x20 + 24 bit address
    - program : WREN, cmd 0x02 + 24 bit address + one data byte

  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#include <Base.h>
#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/DebugLib.h>
#include <Library/IoLib.h>
#include <Library/PcdLib.h>
#include <Library/VirtNorFlashDeviceLib.h>

/* Uncached alias of a physical address (DMW0 configured in Start.S). */
#define UNCACHED(x)  ((UINTN)(0x8000000000000000ULL | (UINT64)(x)))

/* SPI controller registers. */
#define SPI_REG_BASE    (UNCACHED (FixedPcdGet32 (PcdLoongsonSpiControllerBase)))
#define SPI_SPCR        0x0
#define SPI_SPSR        0x1
#define SPI_FIFO        0x2
#define SPI_SPER        0x3
#define SPI_PARAM       0x4
#define SPI_SOFTCS      0x5
#define SPI_PARAM2      0x6

#define SPI_RFEMPTY     0x1

/* NOR flash commands. */
#define NOR_WREN        0x06
#define NOR_WRDI        0x04
#define NOR_RDSR        0x05
#define NOR_READ        0x03
#define NOR_PROGRAM     0x02
#define NOR_ERASE_4K    0x20

#define SPI_CS_ASSERT   0x01
#define SPI_CS_RELEASE  0x11

STATIC
VOID
SpiSend (
  IN UINT8  Value
  )
{
  UINT32  Timeout = 100000;

  MmioWrite8 (SPI_REG_BASE + SPI_FIFO, Value);
  while (((MmioRead8 (SPI_REG_BASE + SPI_SPSR)) & SPI_RFEMPTY) != 0) {
    if (Timeout-- == 0) {
      break;
    }
  }

  MmioRead8 (SPI_REG_BASE + SPI_FIFO);
}

STATIC
UINT8
SpiRecv (
  VOID
  )
{
  UINT32  Timeout = 100000;

  MmioWrite8 (SPI_REG_BASE + SPI_FIFO, 0x00);
  while (((MmioRead8 (SPI_REG_BASE + SPI_SPSR)) & SPI_RFEMPTY) != 0) {
    if (Timeout-- == 0) {
      break;
    }
  }

  return MmioRead8 (SPI_REG_BASE + SPI_FIFO);
}

STATIC
VOID
SpiCs (
  IN UINT8  State
  )
{
  MmioWrite8 (SPI_REG_BASE + SPI_SOFTCS, State);
}

STATIC
VOID
SpiInit (
  VOID
  )
{
  MmioWrite8 (SPI_REG_BASE + SPI_SPSR, 0xc0);
  MmioWrite8 (SPI_REG_BASE + SPI_PARAM, 0x10);
  MmioWrite8 (SPI_REG_BASE + SPI_PARAM2, 0x01);
  MmioWrite8 (SPI_REG_BASE + SPI_SPER, 0x04);
  MmioWrite8 (SPI_REG_BASE + SPI_SPCR, 0x51);
}

STATIC
UINT8
SpiReadStatus (
  VOID
  )
{
  UINT8  Status;

  SpiCs (SPI_CS_ASSERT);
  SpiSend (NOR_RDSR);
  Status = SpiRecv ();
  SpiCs (SPI_CS_RELEASE);

  return Status;
}

STATIC
EFI_STATUS
SpiWaitBusy (
  VOID
  )
{
  UINT32  Timeout = 10000000;

  while ((SpiReadStatus () & 0x01) != 0) {
    if (Timeout-- == 0) {
      DEBUG ((DEBUG_ERROR, "%a: SPI flash busy timeout\n", __func__));
      return EFI_DEVICE_ERROR;
    }
  }

  return EFI_SUCCESS;
}

STATIC
EFI_STATUS
SpiWriteEnable (
  VOID
  )
{
  SpiCs (SPI_CS_ASSERT);
  SpiSend (NOR_WREN);
  SpiCs (SPI_CS_RELEASE);

  return SpiWaitBusy ();
}

STATIC
EFI_STATUS
SpiWriteStatus (
  IN UINT8  Status
  )
{
  SpiCs (SPI_CS_ASSERT);
  SpiSend (0x50);            /* enable write to status register */
  SpiCs (SPI_CS_RELEASE);

  SpiCs (SPI_CS_ASSERT);
  SpiSend (0x01);
  SpiSend (Status);
  SpiCs (SPI_CS_RELEASE);

  return SpiWaitBusy ();
}

/**
  Erase one 4K sector at the given absolute flash offset.
**/
STATIC
EFI_STATUS
SpiEraseSector (
  IN UINTN  FlashOffset
  )
{
  EFI_STATUS  Status;

  SpiInit ();
  Status = SpiWriteStatus (0x00);
  if (EFI_ERROR (Status)) {
    return Status;
  }

  Status = SpiWriteEnable ();
  if (EFI_ERROR (Status)) {
    return Status;
  }

  SpiCs (SPI_CS_ASSERT);
  SpiSend (NOR_ERASE_4K);
  SpiSend ((UINT8)(FlashOffset >> 16));
  SpiSend ((UINT8)(FlashOffset >> 8));
  SpiSend ((UINT8)FlashOffset);
  SpiCs (SPI_CS_RELEASE);

  return SpiWaitBusy ();
}

/**
  Program a single byte.
**/
STATIC
EFI_STATUS
SpiProgramByte (
  IN UINTN  FlashOffset,
  IN UINT8  Value
  )
{
  EFI_STATUS  Status;

  Status = SpiWriteEnable ();
  if (EFI_ERROR (Status)) {
    return Status;
  }

  SpiCs (SPI_CS_ASSERT);
  SpiSend (NOR_PROGRAM);
  SpiSend ((UINT8)(FlashOffset >> 16));
  SpiSend ((UINT8)(FlashOffset >> 8));
  SpiSend ((UINT8)FlashOffset);
  SpiSend (Value);
  SpiCs (SPI_CS_RELEASE);

  return SpiWaitBusy ();
}

/**
  Read from flash through the XIP window.
**/
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

  //
  // Only the last block can be partially read.
  //
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

/**
  Program a buffer into a single block. The block must have been erased
  beforehand; the variable services / FTW layer guarantee this.
**/
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
  UINTN  FlashOffset;
  UINTN  Count;
  UINTN  Index;

  Count      = *NumBytes;
  FlashOffset = GET_NOR_BLOCK_ADDRESS (RegionBaseAddress, Lba, BlockSize) +
                Offset - FixedPcdGet32 (PcdLoongsonSpiNorBaseAddress);

  for (Index = 0; Index < Count; Index++) {
    if (SpiProgramByte (FlashOffset + Index, Buffer[Index]) != EFI_SUCCESS) {
      *NumBytes = Index;
      return EFI_DEVICE_ERROR;
    }
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
  EFI_STATUS  Status;
  UINTN       StartAddress;
  UINTN       FlashOffset;
  UINTN       Remaining;
  UINTN       Offset;
  UINT8       *Src;

  if ((Lba > LastBlock) ||
      (BufferSizeInBytes > ((UINTN)LastBlock - (UINTN)Lba + 1) * BlockSize))
  {
    return EFI_INVALID_PARAMETER;
  }

  StartAddress = GET_NOR_BLOCK_ADDRESS (RegionBaseAddress, Lba, BlockSize);
  FlashOffset  = StartAddress - FixedPcdGet32 (PcdLoongsonSpiNorBaseAddress);

  Remaining = BufferSizeInBytes;
  Offset    = 0;
  Src       = Buffer;

  while (Remaining != 0) {
    Status = SpiProgramByte (FlashOffset + Offset, Src[Offset]);
    if (EFI_ERROR (Status)) {
      return EFI_DEVICE_ERROR;
    }

    Offset++;
    Remaining--;
  }

  return EFI_SUCCESS;
}

EFI_STATUS
EFIAPI
NorFlashEraseSingleBlock (
  IN UINTN  DeviceBaseAddress,
  IN UINTN  BlockAddress
  )
{
  return SpiEraseSector (BlockAddress - FixedPcdGet32 (PcdLoongsonSpiNorBaseAddress));
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
NorFlashWriteSingleWord (
  IN UINTN   DeviceBaseAddress,
  IN UINTN   WordAddress,
  IN UINT32  WriteData
  )
{
  UINTN  Index;

  for (Index = 0; Index < 4; Index++) {
    EFI_STATUS  Status;

    Status = SpiProgramByte (
               WordAddress - FixedPcdGet32 (PcdLoongsonSpiNorBaseAddress) + Index,
               (UINT8)(WriteData >> (Index * 8))
               );
    if (EFI_ERROR (Status)) {
      return EFI_DEVICE_ERROR;
    }
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
    EFI_STATUS  Status;

    Status = SpiProgramByte (
               TargetAddress - FixedPcdGet32 (PcdLoongsonSpiNorBaseAddress) + Index,
               ((UINT8 *)Buffer)[Index]
               );
    if (EFI_ERROR (Status)) {
      return EFI_DEVICE_ERROR;
    }
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
  UINTN  FlashOffset;

  FlashOffset = GET_NOR_BLOCK_ADDRESS (RegionBaseAddress, Lba, BlockSizeInWords * 4) -
                FixedPcdGet32 (PcdLoongsonSpiNorBaseAddress);

  return NorFlashWriteBuffer (
           DeviceBaseAddress,
           FixedPcdGet32 (PcdLoongsonSpiNorBaseAddress) + FlashOffset,
           BlockSizeInWords * 4,
           DataBuffer
           );
}

EFI_STATUS
EFIAPI
NorFlashReset (
  IN UINTN  DeviceBaseAddress
  )
{
  SpiInit ();
  return EFI_SUCCESS;
}
