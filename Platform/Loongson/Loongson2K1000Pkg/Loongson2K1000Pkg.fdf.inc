DEFINE BLOCK_SIZE                 = 0x1000

############################################################################
# FW total: 4MB of SPI NOR starting at the LoongArch reset vector window
DEFINE FW_BASE_ADDRESS            = 0x1c000000
DEFINE FW_BLOCKS                  = 0x400
DEFINE FW_SIZE                    = 0x400000

#Set FVMAIN size
DEFINE FVMAIN_SIZE                = $(FW_SIZE)

#Set Memory layout (inside the 2MB firmware-reserve area of low RAM)
DEFINE SEC_PEI_TEMP_RAM_BASE      = 0x10000
DEFINE SEC_PEI_TEMP_RAM_SIZE      = 0x80000
DEFINE DEVICE_TREE_RAM_BASE       = 0x100000
