DEFINE BLOCK_SIZE                 = 0x1000

#
# QEMU fit-out.  The ls2k machine memory-maps only the first 1 MB of the SPI
# NOR at the reset window (0x1c000000); everything past 0x1c0fffff reads back
# as zero.  A full-feature build puts about 1.4 MB of content in front of the
# DXE volume, so DxeIpl truncates the LZMA stream and fails to load DXE core.
# Building with -D QEMU_FIT=TRUE drops the drivers that the emulator cannot
# exercise anyway, which brings the whole image below 1 MB and lets the DXE
# phase be boot-tested.  Real firmware builds leave this FALSE.
#
!ifndef QEMU_FIT
  DEFINE QEMU_FIT                  = FALSE
!endif

#
# BOARD_MIN: cut the image down so that everything fits inside the chip's 1 MB
# boot window.  The 2K1000LA maps only 0x1C000000-0x1C0FFFFF to the boot device
# (manual section 6.1); anything the firmware must execute or read as memory has
# to live in that first megabyte, and this board's full-feature image is 1.4 MB.
#
!ifndef BOARD_MIN
  DEFINE BOARD_MIN                 = FALSE
!endif

#
# Pre-DRAM stack top used by Sec/LoongArch64/Start.S.  The board default is the
# top of the 1 MB boot window the SPI NOR is mapped into; it is a board value
# (proven by v7's field boot), not one the manual states - that window is
# documented as a read-only flash space.  QEMU's ls2k machine maps 0x1c000000
# as read-only RAM, so the emulator smoke test overrides it
# (build -D PREMEM_STACK_TOP=0x90040000); see the comment in Start.S.
#
!ifndef PREMEM_STACK_TOP
  DEFINE PREMEM_STACK_TOP         = 0x9000000090040000
!endif

#
# CRMD (CSR 0x0) written at the top of Sec/LoongArch64/Start.S.  Two values
# have been used on this board and they are not interchangeable:
#
#   0xb8  DA=1, PG=1 - what the board's last known-good boot ran (v7, commit
#         c76951b).  0xb8 is the only CRMD value ever seen booting on silicon;
#         0xa8 has never run on this board.  This is the default.
#   0xa8  DA=1, PG=0 - required by QEMU: when da&!pg the emulator bypasses the
#         DMW entirely and masks the address to 48 bits
#         (qemu/target/loongarch/tcg/tlb_helper.c:195-203), which is the only
#         reason the 0x9000_0000_... MMIO accesses land anywhere in the
#         emulator.  With 0xb8 QEMU fetches 0x5555 filler and never reaches
#         the SEC entry, so the emulator build passes it explicitly:
#
#           build -D QEMU_FIT=TRUE -D BOARD_MIN=TRUE \
#                 -D PREMEM_STACK_TOP=0x90040000 -D BOOT_CRMD=0xa8
#
# The default used to follow QEMU_FIT, and that was the wrong way round: every
# image, board or emulator, is built with -D QEMU_FIT=TRUE - that is what makes
# FVMAIN_SIZE fit the 1 MB window - so a board build that forgot
# -D BOOT_CRMD=0xb8 silently carried 0xa8, the value that has never booted on
# hardware.  A wrong number on the board is silence; a wrong number in the
# emulator fails loudly and immediately on the development machine, which is
# the side that can afford to be wrong.  So the board value is the default and
# the emulator override has to be explicit.
#
# Start.S keeps the same value as its own #ifndef fallback, so a build that
# does not define this still assembles.  Override with
# `build -D BOOT_CRMD=0x...`.
#
!ifndef BOOT_CRMD
  DEFINE BOOT_CRMD                 = 0xb8
!endif

############################################################################
# FW total: 4MB of SPI NOR starting at the LoongArch reset vector window
DEFINE FW_BASE_ADDRESS            = 0x1c000000
DEFINE FW_BLOCKS                  = 0x400
DEFINE FW_SIZE                    = 0x400000

#
# Chip layout.  Every address below is a flash offset; add FW_BASE_ADDRESS for
# the XIP alias.  The variable/FTW addresses reach the DSC PCDs through the
# DEFINEs at the end of this block, so this table is the single source of truth:
#
#   0x000000..$(FVMAIN_SIZE)  FVMAIN_COMPACT - the whole bootable image
#                             (0xF0000 with BOARD_MIN=TRUE, 0x360000 otherwise)
#   ..0x360000                not written by the image when BOARD_MIN=TRUE:
#                             keeps whatever the programmer left there
#                             (0xFF on an erased part)
#   0x360000..0x36F000        boot progress log (Library/LoongsonBootLogLib;
#                             LS2K_BOOTLOG_SIZE, 60 KB)
#   0x36F000..0x370000        progress marks: one erased 4 KB sector, held out
#                             of the log's tail (LS2K_MARK_BASE in
#                             Include/Library/Loongson2K1000.h).  Programmed
#                             only when the library is built with its own
#                             BOOTMARK_FLASH_ENABLE set to 1 (a source edit, not
#                             a build -D: command-line defines never reach C
#                             code); the firmware never writes it otherwise.
#   0x370000..0x3B0000        variable store
#   0x3B0000..0x3C0000        FTW working block
#   0x3C0000..0x400000        FTW spare block
#
# The variable/FTW pair must stay contiguous and total 0x90000, because that
# is what PcdLoongsonSpiNorVarStoreSize hands to VirtNorFlashDxe as one region;
# a mismatch silently disables UEFI variables (Loongson2K1000Pkg.dec:36-41),
# and 0x370000+0x90000 == 0x400000 == the end of the W25Q32.
#
# Region geometry, consumed by the DSC PCDs.
#
DEFINE FLASH_VARSTORE_OFFSET      = 0x370000
DEFINE FLASH_VARSTORE_SIZE        = 0x40000
DEFINE FLASH_FTW_WORK_OFFSET      = 0x3B0000
DEFINE FLASH_FTW_WORK_SIZE        = 0x10000
DEFINE FLASH_FTW_SPARE_OFFSET     = 0x3C0000
DEFINE FLASH_FTW_SPARE_SIZE       = 0x40000
#
# The firmware volume has to declare a length that fits inside the chip's 1 MB
# boot window -- anything past it reads back as local-bus data, which the FV
# parser would walk into.  BOARD_MIN keeps the whole volume below the window.
#
!if $(BOARD_MIN) == TRUE
  DEFINE FVMAIN_SIZE              = 0xF0000
!else
  DEFINE FVMAIN_SIZE              = 0x360000
!endif

#Set Memory layout (inside the 2MB firmware-reserve area of low RAM)
DEFINE SEC_PEI_TEMP_RAM_BASE      = 0x10000
DEFINE SEC_PEI_TEMP_RAM_SIZE      = 0x80000
DEFINE DEVICE_TREE_RAM_BASE       = 0x100000
