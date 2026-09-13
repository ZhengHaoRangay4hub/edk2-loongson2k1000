/** @file
  PCI Host Bridge Library for Loongson 2K1000LA.

  Single root bridge covering the internal PCIe complex:
    bus   : 0x00 - 0xFF
    io    : 0x18008000 - 0x1800FFFF
    memory: 0x60000000 - 0x7FFFFFFF
    config: 0xFE00000000 - 0xFE1FFFFFFF (Loongson compressed ECAM,
            handled by LoongsonPciLib)

  SPDX-License-Identifier: BSD-2-Clause-Patent
**/
#include <PiDxe.h>

#include <Library/DebugLib.h>
#include <Library/PciHostBridgeLib.h>
#include <Library/PciHostBridgeUtilityLib.h>
#include <Library/MemoryAllocationLib.h>

STATIC PCI_ROOT_BRIDGE_APERTURE  mNonExistAperture = { MAX_UINT64, 0 };

STATIC PCI_ROOT_BRIDGE_APERTURE  mIoAperture  = { 0x18008000, 0x8000 };

STATIC PCI_ROOT_BRIDGE_APERTURE  mMemAperture = { 0x60000000, 0x20000000 };

STATIC PCI_ROOT_BRIDGE  mRootBridge;

/**
  Return all the root bridge instances in an array.

  @param Count  Return the count of root bridge instances.

  @return All the root bridge instances in an array.
**/
PCI_ROOT_BRIDGE *
EFIAPI
PciHostBridgeGetRootBridges (
  UINTN  *Count
  )
{
  UINT64  AllocationAttributes;

  AllocationAttributes = EFI_PCI_HOST_BRIDGE_COMBINE_MEM_PMEM;

  PciHostBridgeUtilityInitRootBridge (
    0,
    EFI_PCI_ATTRIBUTE_IDE_PRIMARY_IO | EFI_PCI_ATTRIBUTE_IDE_SECONDARY_IO |
    EFI_PCI_ATTRIBUTE_VGA_PALETTE_IO | EFI_PCI_ATTRIBUTE_ISA_MOTHERBOARD_IO |
    EFI_PCI_ATTRIBUTE_ISA_IO,
    AllocationAttributes,
    FALSE,                 /* DmaAbove4G  */
    FALSE,                 /* NoExtendedConfigSpace */
    0x00,                  /* RootBusNumber */
    0xFF,                  /* MaxSubBusNumber */
    &mIoAperture,
    &mMemAperture,
    &mNonExistAperture,    /* MemAbove4G  */
    &mNonExistAperture,    /* PMem        */
    &mNonExistAperture,    /* PMemAbove4G */
    &mRootBridge
    );

  mRootBridge.DevicePath = NULL;

  *Count = 1;
  return &mRootBridge;
}

/**
  Free the root bridge instances array returned from
  PciHostBridgeGetRootBridges().
**/
VOID
EFIAPI
PciHostBridgeFreeRootBridges (
  PCI_ROOT_BRIDGE  *Bridges,
  UINTN            Count
  )
{
  PciHostBridgeUtilityFreeRootBridges (Bridges, Count);
}

/**
  Inform the platform that the resource conflict happens.
**/
VOID
EFIAPI
PciHostBridgeResourceConflict (
  EFI_HANDLE  HostBridgeHandle,
  VOID        *Configuration
  )
{
  PciHostBridgeUtilityResourceConflict (Configuration);
}
