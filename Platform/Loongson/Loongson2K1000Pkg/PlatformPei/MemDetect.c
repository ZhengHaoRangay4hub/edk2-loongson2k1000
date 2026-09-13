/** @file
  Memory Detection for the Loongson 2K1000LA education board.

  Forked from OvmfPkg/LoongArchVirt/PlatformPei/MemDetect.c (QEMU fw_cfg
  based) with the board's fixed memory map:

    0x00000000 - 0x00200000  firmware reserve (SEC temp RAM, DTB)
    0x00200000 - 0x0F000000  DDR low window
    0x0F00000 - 0x90000000   MMIO (sysconf, flash, PCIe, devices)
    0x90000000 - 0x100000000 DDR high window

  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

#include <PiPei.h>
#include <Library/BaseMemoryLib.h>
#include <Library/DebugLib.h>
#include <Library/HobLib.h>
#include <Library/PcdLib.h>
#include <Library/ResourcePublicationLib.h>
#include <Uefi/UefiSpec.h>
#include "Platform.h"

#define MAX_VIRTUAL_MEMORY_MAP_DESCRIPTORS  (32)

#define LS2K1000_LOW_RAM_BASE   0x00200000ULL
#define LS2K1000_LOW_RAM_LIMIT  0x0F000000ULL
#define LS2K1000_HIGH_RAM_BASE  0x90000000ULL
#define LS2K1000_HIGH_RAM_LIMIT 0x100000000ULL

/**
  Publish PEI core memory.
**/
EFI_STATUS
PublishPeiMemory (
  VOID
  )
{
  EFI_STATUS  Status;
  UINT64      Base;
  UINT64      Size;
  UINT64      RamTop;

  //
  // Determine the range of memory to use during PEI
  //
  Base   = FixedPcdGet64 (PcdOvmfSecPeiTempRamBase) + FixedPcdGet32 (PcdOvmfSecPeiTempRamSize);
  RamTop = LS2K1000_LOW_RAM_LIMIT;

  Size = RamTop - Base;

  //
  // Publish this memory to the PEI Core
  //
  Status = PublishSystemMemory (Base, Size);
  ASSERT_EFI_ERROR (Status);

  DEBUG ((DEBUG_INFO, "Publish Memory Initialize done.\n"));
  return Status;
}

/**
  Perform Memory Detection - publish system RAM and reserve MMIO regions.
**/
VOID
InitializeRamRegions (
  VOID
  )
{
  AddMemoryRangeHob (LS2K1000_LOW_RAM_BASE, LS2K1000_LOW_RAM_LIMIT);
  AddMemoryRangeHob (LS2K1000_HIGH_RAM_BASE, LS2K1000_HIGH_RAM_LIMIT);

  //
  // Describe the MMIO windows so the DXE GCD knows about them.
  //
  BuildResourceDescriptorHob (
    EFI_RESOURCE_MEMORY_MAPPED_IO,
    EFI_RESOURCE_ATTRIBUTE_PRESENT | EFI_RESOURCE_ATTRIBUTE_INITIALIZED |
    EFI_RESOURCE_ATTRIBUTE_UNCACHEABLE | EFI_RESOURCE_ATTRIBUTE_TESTED,
    0x10000000,
    0x10000000
    );

  BuildResourceDescriptorHob (
    EFI_RESOURCE_MEMORY_MAPPED_IO,
    EFI_RESOURCE_ATTRIBUTE_PRESENT | EFI_RESOURCE_ATTRIBUTE_INITIALIZED |
    EFI_RESOURCE_ATTRIBUTE_UNCACHEABLE | EFI_RESOURCE_ATTRIBUTE_TESTED,
    0x20000000,
    0x10000000
    );

  BuildResourceDescriptorHob (
    EFI_RESOURCE_MEMORY_MAPPED_IO,
    EFI_RESOURCE_ATTRIBUTE_PRESENT | EFI_RESOURCE_ATTRIBUTE_INITIALIZED |
    EFI_RESOURCE_ATTRIBUTE_UNCACHEABLE | EFI_RESOURCE_ATTRIBUTE_TESTED,
    0x40000000,
    0x40000000
    );

  //
  // When 0 address protection is enabled,
  // 0-4k memory needs to be preallocated to prevent UEFI applications from
  // allocating use, such as grub
  //
  if (PcdGet8 (PcdNullPointerDetectionPropertyMask) & BIT0) {
    BuildMemoryAllocationHob (
      0,
      EFI_PAGE_SIZE,
      EfiBootServicesData
      );
  }
}

/**
  Gets the Virtual Memory Map of the platform.

  @param[out]   MemoryTable    Array of EFI_MEMORY_DESCRIPTOR
                               describing a Physical-to-Virtual Memory
                               mapping. This array must be ended by a
                               zero-filled entry. The allocated memory
                               will not be freed.
**/
VOID
EFIAPI
GetMemoryMapPolicy (
  OUT EFI_MEMORY_DESCRIPTOR  **MemoryTable
  )
{
  EFI_MEMORY_DESCRIPTOR  *VirtualMemoryTable;
  UINTN                  Index = 0;

  ASSERT (MemoryTable != NULL);

  VirtualMemoryTable = AllocatePool (
                         sizeof (EFI_MEMORY_DESCRIPTOR) *
                         MAX_VIRTUAL_MEMORY_MAP_DESCRIPTORS
                         );

  /* Firmware reserved low region (SEC temp RAM + DTB). */
  VirtualMemoryTable[Index].PhysicalStart = 0x00000000;
  VirtualMemoryTable[Index].VirtualStart  = VirtualMemoryTable[Index].PhysicalStart;
  VirtualMemoryTable[Index].NumberOfPages = EFI_SIZE_TO_PAGES (0x00200000);
  VirtualMemoryTable[Index].Attribute     = EFI_MEMORY_WB;
  ++Index;

  /* DDR low window. */
  VirtualMemoryTable[Index].PhysicalStart = LS2K1000_LOW_RAM_BASE;
  VirtualMemoryTable[Index].VirtualStart  = VirtualMemoryTable[Index].PhysicalStart;
  VirtualMemoryTable[Index].NumberOfPages = EFI_SIZE_TO_PAGES (LS2K1000_LOW_RAM_LIMIT - LS2K1000_LOW_RAM_BASE);
  VirtualMemoryTable[Index].Attribute     = EFI_MEMORY_WB;
  ++Index;

  /* SoC MMIO: sysconf, UART, flash, PIC, LPC. */
  VirtualMemoryTable[Index].PhysicalStart = 0x10000000;
  VirtualMemoryTable[Index].VirtualStart  = VirtualMemoryTable[Index].PhysicalStart;
  VirtualMemoryTable[Index].NumberOfPages = EFI_SIZE_TO_PAGES (0x10000000);
  VirtualMemoryTable[Index].Attribute     = EFI_MEMORY_UC;
  ++Index;

  /* MMIO window continuation. */
  VirtualMemoryTable[Index].PhysicalStart = 0x20000000;
  VirtualMemoryTable[Index].VirtualStart  = VirtualMemoryTable[Index].PhysicalStart;
  VirtualMemoryTable[Index].NumberOfPages = EFI_SIZE_TO_PAGES (0x10000000);
  VirtualMemoryTable[Index].Attribute     = EFI_MEMORY_UC;
  ++Index;

  /* Device window (OTG, EHCI, GMAC, DC, GPU, SATA, VPU). */
  VirtualMemoryTable[Index].PhysicalStart = 0x40000000;
  VirtualMemoryTable[Index].VirtualStart  = VirtualMemoryTable[Index].PhysicalStart;
  VirtualMemoryTable[Index].NumberOfPages = EFI_SIZE_TO_PAGES (0x20000000);
  VirtualMemoryTable[Index].Attribute     = EFI_MEMORY_UC;
  ++Index;

  /* PCIe memory window. */
  VirtualMemoryTable[Index].PhysicalStart = 0x60000000;
  VirtualMemoryTable[Index].VirtualStart  = VirtualMemoryTable[Index].PhysicalStart;
  VirtualMemoryTable[Index].NumberOfPages = EFI_SIZE_TO_PAGES (0x20000000);
  VirtualMemoryTable[Index].Attribute     = EFI_MEMORY_UC;
  ++Index;

  /* PCIe configuration space (Loongson compressed ECAM). */
  VirtualMemoryTable[Index].PhysicalStart = 0xFE00000000ULL;
  VirtualMemoryTable[Index].VirtualStart  = VirtualMemoryTable[Index].PhysicalStart;
  VirtualMemoryTable[Index].NumberOfPages = EFI_SIZE_TO_PAGES (0x20000000);
  VirtualMemoryTable[Index].Attribute     = EFI_MEMORY_UC;
  ++Index;

  /* DDR high window. */
  VirtualMemoryTable[Index].PhysicalStart = LS2K1000_HIGH_RAM_BASE;
  VirtualMemoryTable[Index].VirtualStart  = VirtualMemoryTable[Index].PhysicalStart;
  VirtualMemoryTable[Index].NumberOfPages = EFI_SIZE_TO_PAGES (LS2K1000_HIGH_RAM_LIMIT - LS2K1000_HIGH_RAM_BASE);
  VirtualMemoryTable[Index].Attribute     = EFI_MEMORY_WB;
  ++Index;

  // End of Table
  ZeroMem (&VirtualMemoryTable[Index], sizeof (EFI_MEMORY_DESCRIPTOR));
  *MemoryTable = VirtualMemoryTable;
}
