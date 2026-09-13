## @file
#  Loongson 2K1000LA (education board) platform DSC.
#
#  Forked from OvmfPkg/LoongArchVirt/LoongArchVirtQemu.dsc (BSD-2-Patent,
#  Copyright (c) 2024-2026 Loongson Technology Corporation Limited) and
#  adapted for real hardware: QEMU fw_cfg, virtio and ACPI-platform pieces
#  are replaced by on-chip drivers.
#
#  SPDX-License-Identifier: BSD-2-Clause-Patent
##

################################################################################
#
# Defines Section - statements that will be processed to create a Makefile.
#
###############################################################################
[Defines]
  PLATFORM_NAME                  = Loongson2K1000Pkg
  PLATFORMPKG_NAME               = Loongson2K1000Pkg
  PLATFORM_GUID                  = 8a9b0c1d-2e3f-4a5b-8c7d-6e5f4a3b2c1d
  PLATFORM_VERSION               = 0.1
  DSC_SPECIFICATION              = 1.29
  OUTPUT_DIRECTORY               = Build/$(PLATFORM_NAME)
  SUPPORTED_ARCHITECTURES        = LOONGARCH64
  BUILD_TARGETS                  = DEBUG|RELEASE|NOOPT
  SKUID_IDENTIFIER               = DEFAULT
  FLASH_DEFINITION               = Platform/Loongson/Loongson2K1000Pkg/Loongson2K1000Pkg.fdf

!include Platform/Loongson/Loongson2K1000Pkg/Loongson2K1000Pkg.fdf.inc

  DEFINE TTY_TERMINAL            = TRUE
  DEFINE BUILD_SHELL             = TRUE

############################################################################
#
# Defines for default states.
#
############################################################################
[BuildOptions]
  GCC:RELEASE_*_*_CC_FLAGS       = -DSPEEDUP

  #
  # Disable deprecated APIs.
  #
  GCC:*_*_*_CC_FLAGS = -D DISABLE_NEW_DEPRECATED_INTERFACES

[BuildOptions.LOONGARCH64.EDKII.SEC]
  *_*_*_CC_FLAGS                 =

#
# Default page size is 16K for loongarch; code section separated with data
# section with 16K page alignment.
#
[BuildOptions.common.EDKII.DXE_CORE,BuildOptions.common.EDKII.DXE_DRIVER,BuildOptions.common.EDKII.UEFI_DRIVER,BuildOptions.common.EDKII.UEFI_APPLICATION]
  GCC:*_*_*_DLINK_FLAGS = -z common-page-size=0x4000

[BuildOptions.common.EDKII.DXE_RUNTIME_DRIVER]
  GCC:*_*_LOONGARCH64_DLINK_FLAGS = -z common-page-size=0x10000

################################################################################
#
# SKU Identification section
#
################################################################################
[SkuIds]
  0|DEFAULT

################################################################################
#
# Library Class section
#
################################################################################

!include MdePkg/MdeLibs.dsc.inc

[LibraryClasses.common]
  GptLib|MdeModulePkg/Library/GptLib/GptLib.inf
  PcdLib                           | MdePkg/Library/DxePcdLib/DxePcdLib.inf
  TimerLib                         | UefiCpuPkg/Library/CpuTimerLib/BaseCpuTimerLib.inf
  PrintLib                         | MdePkg/Library/BasePrintLib/BasePrintLib.inf
  BaseMemoryLib                    | MdePkg/Library/BaseMemoryLib/BaseMemoryLib.inf
  BaseLib                          | MdePkg/Library/BaseLib/BaseLib.inf
  SafeIntLib                       | MdePkg/Library/BaseSafeIntLib/BaseSafeIntLib.inf
  TimeBaseLib                      | EmbeddedPkg/Library/TimeBaseLib/TimeBaseLib.inf
  BmpSupportLib                    | MdeModulePkg/Library/BaseBmpSupportLib/BaseBmpSupportLib.inf
  SynchronizationLib               | MdePkg/Library/BaseSynchronizationLib/BaseSynchronizationLib.inf
  CpuLib                           | MdePkg/Library/BaseCpuLib/BaseCpuLib.inf
  PerformanceLib                   | MdePkg/Library/BasePerformanceLibNull/BasePerformanceLibNull.inf
  PeCoffLib                        | MdePkg/Library/BasePeCoffLib/BasePeCoffLib.inf
  CacheMaintenanceLib              | MdePkg/Library/BaseCacheMaintenanceLib/BaseCacheMaintenanceLib.inf
  UefiDecompressLib                | MdePkg/Library/BaseUefiDecompressLib/BaseUefiDecompressLib.inf
  UefiHiiServicesLib               | MdeModulePkg/Library/UefiHiiServicesLib/UefiHiiServicesLib.inf
  HiiLib                           | MdeModulePkg/Library/UefiHiiLib/UefiHiiLib.inf
  CapsuleLib                       | MdeModulePkg/Library/DxeCapsuleLibNull/DxeCapsuleLibNull.inf
  DxeServicesLib                   | MdePkg/Library/DxeServicesLib/DxeServicesLib.inf
  DxeServicesTableLib              | MdePkg/Library/DxeServicesTableLib/DxeServicesTableLib.inf
  PeCoffGetEntryPointLib           | MdePkg/Library/BasePeCoffGetEntryPointLib/BasePeCoffGetEntryPointLib.inf
  PciLib                           | Platform/Loongson/Loongson2K1000Pkg/Library/LoongsonPciLib/LoongsonPciLib.inf
  PciSegmentLib                    | MdePkg/Library/BasePciSegmentLibPci/BasePciSegmentLibPci.inf
  PciCapLib                        | OvmfPkg/Library/BasePciCapLib/BasePciCapLib.inf
  PciCapPciSegmentLib              | OvmfPkg/Library/BasePciCapPciSegmentLib/BasePciCapPciSegmentLib.inf
  PciCapPciIoLib                   | OvmfPkg/Library/UefiPciCapPciIoLib/UefiPciCapPciIoLib.inf
  IoLib                            | MdePkg/Library/BaseIoLibIntrinsic/BaseIoLibIntrinsic.inf
  FdtSerialPortAddressLib          | OvmfPkg/Library/FdtSerialPortAddressLib/FdtSerialPortAddressLib.inf
  PlatformHookLib                  | OvmfPkg/LoongArchVirt/Library/Fdt16550SerialPortHookLib/Fdt16550SerialPortHookLib.inf
  SerialPortLib                    | OvmfPkg/LoongArchVirt/Library/EarlyFdtSerialPortLib16550/EarlyFdtSerialPortLib16550.inf
  ResetSystemLib                   | Platform/Loongson/Loongson2K1000Pkg/Library/ResetSystemLib/Loongson2KResetSystemLib.inf

  UefiLib                          | MdePkg/Library/UefiLib/UefiLib.inf
  UefiBootServicesTableLib         | MdePkg/Library/UefiBootServicesTableLib/UefiBootServicesTableLib.inf
  UefiRuntimeServicesTableLib      | MdePkg/Library/UefiRuntimeServicesTableLib/UefiRuntimeServicesTableLib.inf
  UefiDriverEntryPoint             | MdePkg/Library/UefiDriverEntryPoint/UefiDriverEntryPoint.inf
  UefiApplicationEntryPoint        | MdePkg/Library/UefiApplicationEntryPoint/UefiApplicationEntryPoint.inf
  DevicePathLib                    | MdePkg/Library/UefiDevicePathLibDevicePathProtocol/UefiDevicePathLibDevicePathProtocol.inf
  FileHandleLib                    | MdePkg/Library/UefiFileHandleLib/UefiFileHandleLib.inf
  SecurityManagementLib            | MdeModulePkg/Library/DxeSecurityManagementLib/DxeSecurityManagementLib.inf
  UefiUsbLib                       | MdePkg/Library/UefiUsbLib/UefiUsbLib.inf
  SerializeVariablesLib            | OvmfPkg/Library/SerializeVariablesLib/SerializeVariablesLib.inf
  CustomizedDisplayLib             | MdeModulePkg/Library/CustomizedDisplayLib/CustomizedDisplayLib.inf
  DebugPrintErrorLevelLib          | MdePkg/Library/BaseDebugPrintErrorLevelLib/BaseDebugPrintErrorLevelLib.inf
  VarCheckLib                      | MdeModulePkg/Library/VarCheckLib/VarCheckLib.inf
  TpmMeasurementLib                | MdeModulePkg/Library/TpmMeasurementLibNull/TpmMeasurementLibNull.inf
  AuthVariableLib                  | MdeModulePkg/Library/AuthVariableLibNull/AuthVariableLibNull.inf
  ShellLib                         | ShellPkg/Library/UefiShellLib/UefiShellLib.inf
  HandleParsingLib                 | ShellPkg/Library/UefiHandleParsingLib/UefiHandleParsingLib.inf
  QemuFwCfgLib                     | OvmfPkg/Library/QemuFwCfgLib/QemuFwCfgLibNull.inf
  VariablePolicyLib                | MdeModulePkg/Library/VariablePolicyLib/VariablePolicyLib.inf
  VariablePolicyHelperLib          | MdeModulePkg/Library/VariablePolicyHelperLib/VariablePolicyHelperLib.inf
  VariableFlashInfoLib             | MdeModulePkg/Library/BaseVariableFlashInfoLib/BaseVariableFlashInfoLib.inf
  SortLib                          | MdeModulePkg/Library/UefiSortLib/UefiSortLib.inf
  FdtLib                           | MdePkg/Library/BaseFdtLib/BaseFdtLib.inf
  PciHostBridgeLib                 | Platform/Loongson/Loongson2K1000Pkg/Library/LoongsonPciHostBridgeLib/LoongsonPciHostBridgeLib.inf
  PciHostBridgeUtilityLib          | OvmfPkg/Library/PciHostBridgeUtilityLib/PciHostBridgeUtilityLib.inf
  DxeHardwareInfoLib               | OvmfPkg/Library/HardwareInfoLib/DxeHardwareInfoLib.inf
  FileExplorerLib                  | MdeModulePkg/Library/FileExplorerLib/FileExplorerLib.inf
  ImagePropertiesRecordLib         | MdeModulePkg/Library/ImagePropertiesRecordLib/ImagePropertiesRecordLib.inf
  UefiBootManagerLib               | MdeModulePkg/Library/UefiBootManagerLib/UefiBootManagerLib.inf
  OrderedCollectionLib             | MdePkg/Library/BaseOrderedCollectionRedBlackTreeLib/BaseOrderedCollectionRedBlackTreeLib.inf
  ReportStatusCodeLib              | MdePkg/Library/BaseReportStatusCodeLibNull/BaseReportStatusCodeLibNull.inf
  PeCoffExtraActionLib             | MdePkg/Library/BasePeCoffExtraActionLibNull/BasePeCoffExtraActionLibNull.inf
  DebugAgentLib                    | MdeModulePkg/Library/DebugAgentLibNull/DebugAgentLibNull.inf
  TpmPlatformHierarchyLib          | SecurityPkg/Library/PeiDxeTpmPlatformHierarchyLibNull/PeiDxeTpmPlatformHierarchyLib.inf
  PlatformBmPrintScLib             | OvmfPkg/Library/PlatformBmPrintScLib/PlatformBmPrintScLib.inf
  PlatformBootManagerLib           | Platform/Loongson/Loongson2K1000Pkg/Library/PlatformBootManagerLib/PlatformBootManagerLib.inf
  BootLogoLib                      | MdeModulePkg/Library/BootLogoLib/BootLogoLib.inf
  PlatformBootManagerCommonLib     | OvmfPkg/Library/PlatformBootManagerCommonLib/PlatformBootManagerCommonLib.inf
  LockBoxLib                       | MdeModulePkg/Library/LockBoxNullLib/LockBoxNullLib.inf
  FrameBufferBltLib                | MdeModulePkg/Library/FrameBufferBltLib/FrameBufferBltLib.inf
  DebugLib                         | MdePkg/Library/BaseDebugLibSerialPort/BaseDebugLibSerialPort.inf
  PeiServicesLib                   | MdePkg/Library/PeiServicesLib/PeiServicesLib.inf
  VirtNorFlashDeviceLib            | Platform/Loongson/Loongson2K1000Pkg/Library/LoongsonSpiNorLib/LoongsonSpiNorFlashDeviceLib.inf
  VirtNorFlashPlatformLib          | Platform/Loongson/Loongson2K1000Pkg/Library/LoongsonSpiNorLib/LoongsonSpiNorFlashPlatformLib.inf
  ShellCEntryLib                   | ShellPkg/Library/UefiShellCEntryLib/UefiShellCEntryLib.inf

[LibraryClasses.common.SEC]
  PcdLib                           | MdePkg/Library/BasePcdLibNull/BasePcdLibNull.inf
  ReportStatusCodeLib              | MdeModulePkg/Library/PeiReportStatusCodeLib/PeiReportStatusCodeLib.inf
  HobLib                           | MdePkg/Library/PeiHobLib/PeiHobLib.inf
  MemoryAllocationLib              | MdePkg/Library/PeiMemoryAllocationLib/PeiMemoryAllocationLib.inf
  PeiServicesTablePointerLib       | MdePkg/Library/PeiServicesTablePointerLibKs0/PeiServicesTablePointerLibKs0.inf
  PlatformHookLib                  | OvmfPkg/LoongArchVirt/Library/Fdt16550SerialPortHookLib/EarlyFdt16550SerialPortHookLib.inf
  CpuExceptionHandlerLib           | UefiCpuPkg/Library/CpuExceptionHandlerLib/SecPeiCpuExceptionHandlerLib.inf

[LibraryClasses.common.PEI_CORE]
  PcdLib                           | MdePkg/Library/PeiPcdLib/PeiPcdLib.inf
  HobLib                           | MdePkg/Library/PeiHobLib/PeiHobLib.inf
  PeiServicesTablePointerLib       | MdePkg/Library/PeiServicesTablePointerLibKs0/PeiServicesTablePointerLibKs0.inf
  MemoryAllocationLib              | MdePkg/Library/PeiMemoryAllocationLib/PeiMemoryAllocationLib.inf
  PeiCoreEntryPoint                | MdePkg/Library/PeiCoreEntryPoint/PeiCoreEntryPoint.inf
  ReportStatusCodeLib              | MdeModulePkg/Library/PeiReportStatusCodeLib/PeiReportStatusCodeLib.inf
  OemHookStatusCodeLib             | MdeModulePkg/Library/OemHookStatusCodeLibNull/OemHookStatusCodeLibNull.inf
  PeCoffGetEntryPointLib           | MdePkg/Library/BasePeCoffGetEntryPointLib/BasePeCoffGetEntryPointLib.inf
  PlatformHookLib                  | OvmfPkg/LoongArchVirt/Library/Fdt16550SerialPortHookLib/EarlyFdt16550SerialPortHookLib.inf
  PerformanceLib                   | MdeModulePkg/Library/PeiPerformanceLib/PeiPerformanceLib.inf

[LibraryClasses.common.PEIM]
  HobLib                           | MdePkg/Library/PeiHobLib/PeiHobLib.inf
  PeiServicesTablePointerLib       | MdePkg/Library/PeiServicesTablePointerLibKs0/PeiServicesTablePointerLibKs0.inf
  MemoryAllocationLib              | MdePkg/Library/PeiMemoryAllocationLib/PeiMemoryAllocationLib.inf
  PeimEntryPoint                   | MdePkg/Library/PeimEntryPoint/PeimEntryPoint.inf
  PerformanceLib                   | MdeModulePkg/Library/PeiPerformanceLib/PeiPerformanceLib.inf
  ReportStatusCodeLib              | MdeModulePkg/Library/PeiReportStatusCodeLib/PeiReportStatusCodeLib.inf
  OemHookStatusCodeLib             | MdeModulePkg/Library/OemHookStatusCodeLibNull/OemHookStatusCodeLibNull.inf
  PeCoffGetEntryPointLib           | MdePkg/Library/BasePeCoffGetEntryPointLib/BasePeCoffGetEntryPointLib.inf
  ResourcePublicationLib           | MdePkg/Library/PeiResourcePublicationLib/PeiResourcePublicationLib.inf
  ExtractGuidedSectionLib          | MdePkg/Library/PeiExtractGuidedSectionLib/PeiExtractGuidedSectionLib.inf
  PcdLib                           | MdePkg/Library/PeiPcdLib/PeiPcdLib.inf
  CpuMmuLib                        | UefiCpuPkg/Library/CpuMmuLib/CpuMmuLib.inf
  CpuMmuInitLib                    | OvmfPkg/LoongArchVirt/Library/CpuMmuInitLib/CpuMmuInitLib.inf
  MpInitLib                        | UefiCpuPkg/Library/MpInitLib/PeiMpInitLib.inf
  PlatformHookLib                  | OvmfPkg/LoongArchVirt/Library/Fdt16550SerialPortHookLib/EarlyFdt16550SerialPortHookLib.inf

[LibraryClasses.common.DXE_CORE]
  HobLib                           | MdePkg/Library/DxeCoreHobLib/DxeCoreHobLib.inf
  DxeCoreEntryPoint                | MdePkg/Library/DxeCoreEntryPoint/DxeCoreEntryPoint.inf
  MemoryAllocationLib              | MdeModulePkg/Library/DxeCoreMemoryAllocationLib/DxeCoreMemoryAllocationLib.inf
  ReportStatusCodeLib              | MdeModulePkg/Library/DxeReportStatusCodeLib/DxeReportStatusCodeLib.inf
  CpuExceptionHandlerLib           | UefiCpuPkg/Library/CpuExceptionHandlerLib/DxeCpuExceptionHandlerLib.inf
  PerformanceLib                   | MdeModulePkg/Library/DxeCorePerformanceLib/DxeCorePerformanceLib.inf

[LibraryClasses.common.DXE_RUNTIME_DRIVER]
  PcdLib                           | MdePkg/Library/DxePcdLib/DxePcdLib.inf
  HobLib                           | MdePkg/Library/DxeHobLib/DxeHobLib.inf
  MemoryAllocationLib              | MdePkg/Library/UefiMemoryAllocationLib/UefiMemoryAllocationLib.inf
  ReportStatusCodeLib              | MdeModulePkg/Library/RuntimeDxeReportStatusCodeLib/RuntimeDxeReportStatusCodeLib.inf
  UefiRuntimeLib                   | MdePkg/Library/UefiRuntimeLib/UefiRuntimeLib.inf
  ExtractGuidedSectionLib          | MdePkg/Library/DxeExtractGuidedSectionLib/DxeExtractGuidedSectionLib.inf
  RealTimeClockLib                 | Platform/Loongson/Loongson2K1000Pkg/Library/Ls2kRealTimeClockLib/LsRealTimeClockLib.inf
  VariablePolicyLib                | MdeModulePkg/Library/VariablePolicyLib/VariablePolicyLibRuntimeDxe.inf
!if $(TARGET) != RELEASE
  DebugLib                         | MdePkg/Library/DxeRuntimeDebugLibSerialPort/DxeRuntimeDebugLibSerialPort.inf
!endif

[LibraryClasses.common.UEFI_DRIVER]
  PcdLib                           | MdePkg/Library/DxePcdLib/DxePcdLib.inf
  HobLib                           | MdePkg/Library/DxeHobLib/DxeHobLib.inf
  PerformanceLib                   | MdeModulePkg/Library/DxePerformanceLib/DxePerformanceLib.inf
  MemoryAllocationLib              | MdePkg/Library/UefiMemoryAllocationLib/UefiMemoryAllocationLib.inf
  ReportStatusCodeLib              | MdeModulePkg/Library/DxeReportStatusCodeLib/DxeReportStatusCodeLib.inf
  UefiScsiLib                      | MdePkg/Library/UefiScsiLib/UefiScsiLib.inf
  ExtractGuidedSectionLib          | MdePkg/Library/DxeExtractGuidedSectionLib/DxeExtractGuidedSectionLib.inf

[LibraryClasses.common.DXE_DRIVER]
  PcdLib                           | MdePkg/Library/DxePcdLib/DxePcdLib.inf
  HobLib                           | MdePkg/Library/DxeHobLib/DxeHobLib.inf
  PerformanceLib                   | MdeModulePkg/Library/DxePerformanceLib/DxePerformanceLib.inf
  MemoryAllocationLib              | MdePkg/Library/UefiMemoryAllocationLib/UefiMemoryAllocationLib.inf
  ReportStatusCodeLib              | MdeModulePkg/Library/DxeReportStatusCodeLib/DxeReportStatusCodeLib.inf
  UefiScsiLib                      | MdePkg/Library/UefiScsiLib/UefiScsiLib.inf
  CpuExceptionHandlerLib           | UefiCpuPkg/Library/CpuExceptionHandlerLib/DxeCpuExceptionHandlerLib.inf
  ExtractGuidedSectionLib          | MdePkg/Library/DxeExtractGuidedSectionLib/DxeExtractGuidedSectionLib.inf
  MpInitLib                        | UefiCpuPkg/Library/MpInitLib/DxeMpInitLib.inf

[LibraryClasses.common.UEFI_APPLICATION]
  PcdLib                           | MdePkg/Library/DxePcdLib/DxePcdLib.inf
  HobLib                           | MdePkg/Library/DxeHobLib/DxeHobLib.inf
  PerformanceLib                   | MdeModulePkg/Library/DxePerformanceLib/DxePerformanceLib.inf
  MemoryAllocationLib              | MdePkg/Library/UefiMemoryAllocationLib/UefiMemoryAllocationLib.inf
  ExtractGuidedSectionLib          | MdePkg/Library/DxeExtractGuidedSectionLib/DxeExtractGuidedSectionLib.inf

################################################################################
#
# Pcd Section
#
################################################################################
[PcdsFeatureFlag]
   gEfiMdeModulePkgTokenSpaceGuid.PcdHiiOsRuntimeSupport               | FALSE
   gEfiMdeModulePkgTokenSpaceGuid.PcdDxeIplSupportUefiDecompress        | TRUE
   gEfiMdeModulePkgTokenSpaceGuid.PcdConOutGopSupport                   | TRUE
   gEfiMdeModulePkgTokenSpaceGuid.PcdPciBusHotplugDeviceSupport         | FALSE

[PcdsFixedAtBuild]
## BaseLib ##
  gEfiMdePkgTokenSpaceGuid.PcdMaximumUnicodeStringLength               | 1000000
  gEfiMdePkgTokenSpaceGuid.PcdMaximumAsciiStringLength                 | 1000000
  gEfiMdePkgTokenSpaceGuid.PcdMaximumLinkedListLength                  | 1000000
  gEfiMdePkgTokenSpaceGuid.PcdSpinLockTimeout                          | 10000000

  gUefiOvmfPkgTokenSpaceGuid.PcdOvmfFdBaseAddress                      | $(FW_BASE_ADDRESS)
  gUefiOvmfPkgTokenSpaceGuid.PcdOvmfFirmwareFdSize                     | $(FW_SIZE)
  gUefiOvmfPkgTokenSpaceGuid.PcdOvmfFirmwareBlockSize                 | $(BLOCK_SIZE)

  gEfiMdeModulePkgTokenSpaceGuid.PcdStatusCodeMemorySize               | 1
  gEfiMdeModulePkgTokenSpaceGuid.PcdResetOnMemoryTypeInformationChange | FALSE
  gEfiMdePkgTokenSpaceGuid.PcdMaximumGuidedExtractHandler              | 0x10
  gEfiMdeModulePkgTokenSpaceGuid.PcdMaxVariableSize                    | 0x2000
  gEfiMdeModulePkgTokenSpaceGuid.PcdMaxHardwareErrorVariableSize       | 0x8000
  gEfiMdeModulePkgTokenSpaceGuid.PcdVpdBaseAddress                     | 0x0
  gEfiMdePkgTokenSpaceGuid.PcdPerformanceLibraryPropertyMask           | 0x1
  gEfiMdePkgTokenSpaceGuid.PcdReportStatusCodePropertyMask             | 0x07

  # Use MMIO for accessing Serial port registers.
  gEfiMdeModulePkgTokenSpaceGuid.PcdSerialUseMmio                      | TRUE
  gEfiMdeModulePkgTokenSpaceGuid.PcdSerialPciDeviceInfo                | {0xFF}
  gEfiMdeModulePkgTokenSpaceGuid.PcdSerialBaudRate                     | 115200
  gEfiMdeModulePkgTokenSpaceGuid.PcdSerialRegisterStride               | 1
  # UART0 APB clock after PLL bring-up.
  gEfiMdeModulePkgTokenSpaceGuid.PcdSerialClockRate                    | 125000000

  gEfiMdePkgTokenSpaceGuid.PcdDebugPrintErrorLevel                     | 0x8000004F

!if $(TARGET) == RELEASE
  gEfiMdePkgTokenSpaceGuid.PcdDebugPropertyMask                        | 0x21
!else
  gEfiMdePkgTokenSpaceGuid.PcdDebugPropertyMask                        | 0x2f
!endif

  gUefiOvmfPkgTokenSpaceGuid.PcdOvmfSecPeiTempRamBase                  | $(SEC_PEI_TEMP_RAM_BASE)
  gUefiOvmfPkgTokenSpaceGuid.PcdOvmfSecPeiTempRamSize                  | $(SEC_PEI_TEMP_RAM_SIZE)
  gUefiOvmfPkgTokenSpaceGuid.PcdDeviceTreeInitialBaseAddress           | $(DEVICE_TREE_RAM_BASE)

  gUefiCpuPkgTokenSpaceGuid.PcdLoongArchExceptionVectorBaseAddress     | gUefiOvmfPkgTokenSpaceGuid.PcdOvmfSecPeiTempRamBase

  # Stable counter frequency (100MHz constant clock on 2K1000LA).
  gUefiCpuPkgTokenSpaceGuid.PcdCpuCoreCrystalClockFrequency             | 100000000

  gEfiMdeModulePkgTokenSpaceGuid.PcdBootManagerMenuFile                | { 0x21, 0xaa, 0x2c, 0x46, 0x14, 0x76, 0x03, 0x45, 0x83, 0x6e, 0x8a, 0xb6, 0xf4, 0x66, 0x23, 0x31 }

  # UEFI variable store lives in the SPI NOR behind the 4MB firmware image.
  gEfiMdeModulePkgTokenSpaceGuid.PcdFlashNvStorageVariableBase64       | 0x1c040000
  gEfiMdeModulePkgTokenSpaceGuid.PcdFlashNvStorageVariableSize         | 0x40000
  gEfiMdeModulePkgTokenSpaceGuid.PcdFlashNvStorageFtwWorkingBase64     | 0x1c080000
  gEfiMdeModulePkgTokenSpaceGuid.PcdFlashNvStorageFtwWorkingSize       | 0x10000
  gEfiMdeModulePkgTokenSpaceGuid.PcdFlashNvStorageFtwSpareBase64       | 0x1c090000
  gEfiMdeModulePkgTokenSpaceGuid.PcdFlashNvStorageFtwSpareSize         | 0x40000

  gEfiMdeModulePkgTokenSpaceGuid.PcdNullPointerDetectionPropertyMask   | 1

  ## Default Terminal Type
!if $(TTY_TERMINAL) == TRUE
  gEfiMdePkgTokenSpaceGuid.PcdDefaultTerminalType                      | 4
  gUefiOvmfPkgTokenSpaceGuid.PcdTerminalTypeGuidBuffer                 | {0x80, 0x6d, 0x91, 0x7d, 0xb1, 0x5b, 0x8c, 0x45, 0xa4, 0x8f, 0xe2, 0x5f, 0xdd, 0x51, 0xef, 0x94}
!else
  gEfiMdePkgTokenSpaceGuid.PcdDefaultTerminalType                      | 1
!endif

[PcdsDynamicDefault]
  gEfiMdeModulePkgTokenSpaceGuid.PcdEmuVariableNvStoreReserved         | 0
  gEfiMdeModulePkgTokenSpaceGuid.PcdPciDisableBusEnumeration           | FALSE
  gEfiMdeModulePkgTokenSpaceGuid.PcdVideoHorizontalResolution          | 800
  gEfiMdeModulePkgTokenSpaceGuid.PcdVideoVerticalResolution            | 600
  gEfiMdePkgTokenSpaceGuid.PcdPlatformBootTimeOut                      | 3

  gEfiMdeModulePkgTokenSpaceGuid.PcdSetupVideoHorizontalResolution     | 640
  gEfiMdeModulePkgTokenSpaceGuid.PcdSetupVideoVerticalResolution       | 480

  gEfiMdePkgTokenSpaceGuid.PcdPciIoTranslation                         | 0x0

[PcdsPatchableInModule.common]
  gEfiMdeModulePkgTokenSpaceGuid.PcdSerialRegisterBase|0x0

################################################################################
#
# Components Section
#
################################################################################
[Components]

  #
  # SEC Phase modules
  #
  Platform/Loongson/Loongson2K1000Pkg/Sec/SecMain.inf

  #
  # PEI Phase modules
  #
  MdeModulePkg/Core/Pei/PeiMain.inf
  MdeModulePkg/Universal/PCD/Pei/Pcd.inf  {
    <LibraryClasses>
      PcdLib|MdePkg/Library/BasePcdLibNull/BasePcdLibNull.inf
  }
  MdePkg/Library/PeiExtractGuidedSectionLib/PeiExtractGuidedSectionLib.inf
  MdeModulePkg/Core/DxeIplPeim/DxeIpl.inf {
    <LibraryClasses>
      NULL|MdeModulePkg/Library/LzmaCustomDecompressLib/LzmaCustomDecompressLib.inf
  }

  Platform/Loongson/Loongson2K1000Pkg/PlatformPei/PlatformPei.inf {
    <LibraryClasses>
      PcdLib|MdePkg/Library/PeiPcdLib/PeiPcdLib.inf
  }

  #
  # DXE Phase modules
  #
  MdeModulePkg/Core/Dxe/DxeMain.inf {
    <LibraryClasses>
      NULL                             | MdeModulePkg/Library/LzmaCustomDecompressLib/LzmaCustomDecompressLib.inf
      DevicePathLib                    | MdePkg/Library/UefiDevicePathLib/UefiDevicePathLib.inf
      ExtractGuidedSectionLib          | MdePkg/Library/DxeExtractGuidedSectionLib/DxeExtractGuidedSectionLib.inf
  }

  MdeModulePkg/Universal/ReportStatusCodeRouter/RuntimeDxe/ReportStatusCodeRouterRuntimeDxe.inf
  MdeModulePkg/Universal/StatusCodeHandler/RuntimeDxe/StatusCodeHandlerRuntimeDxe.inf
  MdeModulePkg/Universal/PCD/Dxe/Pcd.inf  {
   <LibraryClasses>
      PcdLib|MdePkg/Library/BasePcdLibNull/BasePcdLibNull.inf
  }

  MdeModulePkg/Core/RuntimeDxe/RuntimeDxe.inf
  UefiCpuPkg/CpuDxe/CpuDxe.inf {
    <LibraryClasses>
      CpuMmuLib | UefiCpuPkg/Library/CpuMmuLib/CpuMmuLib.inf
  }
  MdeModulePkg/Universal/WatchdogTimerDxe/WatchdogTimer.inf
  MdeModulePkg/Universal/MonotonicCounterRuntimeDxe/MonotonicCounterRuntimeDxe.inf
  MdeModulePkg/Universal/CapsuleRuntimeDxe/CapsuleRuntimeDxe.inf
  MdeModulePkg/Universal/SecurityStubDxe/SecurityStubDxe.inf
  OvmfPkg/LoongArchVirt/Drivers/StableTimerDxe/TimerDxe.inf
  MdeModulePkg/Universal/ResetSystemRuntimeDxe/ResetSystemRuntimeDxe.inf
  MdeModulePkg/Universal/Metronome/Metronome.inf
  EmbeddedPkg/RealTimeClockRuntimeDxe/RealTimeClockRuntimeDxe.inf

  #
  # Variable
  #
  OvmfPkg/VirtNorFlashDxe/VirtNorFlashDxe.inf
  MdeModulePkg/Universal/FaultTolerantWriteDxe/FaultTolerantWriteDxe.inf {
    <LibraryClasses>
      NULL|EmbeddedPkg/Library/NvVarStoreFormattedLib/NvVarStoreFormattedLib.inf
  }
  MdeModulePkg/Universal/Variable/RuntimeDxe/VariableRuntimeDxe.inf {
    <LibraryClasses>
      NULL|MdeModulePkg/Library/VarCheckUefiLib/VarCheckUefiLib.inf
      NULL|EmbeddedPkg/Library/NvVarStoreFormattedLib/NvVarStoreFormattedLib.inf
      BaseMemoryLib|MdePkg/Library/BaseMemoryLib/BaseMemoryLib.inf
  }

  #
  # PCI
  #
  UefiCpuPkg/CpuMmio2Dxe/CpuMmio2Dxe.inf
  EmbeddedPkg/Drivers/FdtClientDxe/FdtClientDxe.inf
  MdeModulePkg/Bus/Pci/PciHostBridgeDxe/PciHostBridgeDxe.inf
  MdeModulePkg/Bus/Pci/PciBusDxe/PciBusDxe.inf

  #
  # Storage over PCI (SATA / NVMe behind the internal PCIe complex)
  #
  MdeModulePkg/Bus/Pci/SataControllerDxe/SataControllerDxe.inf
  MdeModulePkg/Bus/Ata/AtaBusDxe/AtaBusDxe.inf
  MdeModulePkg/Bus/Ata/AtaAtapiPassThru/AtaAtapiPassThru.inf
  MdeModulePkg/Bus/Pci/NvmExpressDxe/NvmExpressDxe.inf

  #
  # USB (EHCI / OHCI live on the internal PCI bus on 2K1000LA)
  #
  MdeModulePkg/Bus/Pci/EhciDxe/EhciDxe.inf
  MdeModulePkg/Bus/Usb/UsbBusDxe/UsbBusDxe.inf
  MdeModulePkg/Bus/Usb/UsbKbDxe/UsbKbDxe.inf
  MdeModulePkg/Bus/Usb/UsbMassStorageDxe/UsbMassStorageDxe.inf

  #
  # File system
  #
  MdeModulePkg/Universal/Disk/DiskIoDxe/DiskIoDxe.inf
  MdeModulePkg/Universal/Disk/PartitionDxe/PartitionDxe.inf
  MdeModulePkg/Universal/Disk/UnicodeCollation/EnglishDxe/EnglishDxe.inf
  FatPkg/EnhancedFatDxe/Fat.inf
  MdeModulePkg/Universal/Disk/UdfDxe/UdfDxe.inf

  #
  # BDS
  #
  MdeModulePkg/Universal/DevicePathDxe/DevicePathDxe.inf {
    <LibraryClasses>
      DevicePathLib                    | MdePkg/Library/UefiDevicePathLib/UefiDevicePathLib.inf
      PcdLib                           | MdePkg/Library/BasePcdLibNull/BasePcdLibNull.inf
  }
  MdeModulePkg/Universal/HiiDatabaseDxe/HiiDatabaseDxe.inf
  MdeModulePkg/Universal/DisplayEngineDxe/DisplayEngineDxe.inf
  MdeModulePkg/Universal/SetupBrowserDxe/SetupBrowserDxe.inf
  MdeModulePkg/Universal/BdsDxe/BdsDxe.inf
  MdeModulePkg/Logo/LogoDxe.inf
  MdeModulePkg/Application/UiApp/UiApp.inf {
    <LibraryClasses>
      NULL|MdeModulePkg/Library/DeviceManagerUiLib/DeviceManagerUiLib.inf
      NULL|MdeModulePkg/Library/BootManagerUiLib/BootManagerUiLib.inf
      NULL|MdeModulePkg/Library/BootMaintenanceManagerUiLib/BootMaintenanceManagerUiLib.inf
  }

  #
  # Console
  #
  MdeModulePkg/Universal/Console/ConPlatformDxe/ConPlatformDxe.inf
  MdeModulePkg/Universal/Console/ConSplitterDxe/ConSplitterDxe.inf
  MdeModulePkg/Universal/Console/TerminalDxe/TerminalDxe.inf
  MdeModulePkg/Universal/PrintDxe/PrintDxe.inf
  MdeModulePkg/Universal/SerialDxe/SerialDxe.inf

  #
  # UEFI Shell
  #
  ShellPkg/Application/Shell/Shell.inf {
    <LibraryClasses>
      ShellCommandLib|ShellPkg/Library/UefiShellCommandLib/UefiShellCommandLib.inf
      NULL|ShellPkg/Library/UefiShellLevel2CommandsLib/UefiShellLevel2CommandsLib.inf
      NULL|ShellPkg/Library/UefiShellLevel1CommandsLib/UefiShellLevel1CommandsLib.inf
      NULL|ShellPkg/Library/UefiShellLevel3CommandsLib/UefiShellLevel3CommandsLib.inf
      NULL|ShellPkg/Library/UefiShellDriver1CommandsLib/UefiShellDriver1CommandsLib.inf
      NULL|ShellPkg/Library/UefiShellInstall1CommandsLib/UefiShellInstall1CommandsLib.inf
      # network command libs dropped: no NIC stack in firmware yet      # network command libs dropped: no NIC stack in firmware yet      NULL|ShellPkg/Library/UefiShellAcpiViewCommandLib/UefiShellAcpiViewCommandLib.inf
      PcdLib|MdePkg/Library/DxePcdLib/DxePcdLib.inf
  }
  ShellPkg/DynamicCommand/DpDynamicCommand/DpDynamicCommand.inf {
    <PcdsFixedAtBuild>
      gEfiShellPkgTokenSpaceGuid.PcdShellLibAutoInitialize|FALSE
  }
