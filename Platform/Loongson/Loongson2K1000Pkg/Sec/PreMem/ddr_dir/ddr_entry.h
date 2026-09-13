//##########################################
//DDR config start
//cxk
#include "lsmc_ddr_param_define.h"
#include "ddr_config_define.h"
//#define DDR_DLL_BYPASS
#define DISABLE_DIMM_ECC
#define PRINT_MSG
#ifdef  ARB_LEVEL
#define AUTO_ARB_LEVEL
#endif
#ifdef  AUTO_ARB_LEVEL
#define CHECK_ARB_LEVEL_FREQ
#ifdef  AUTO_DDR_CONFIG
#define CHECK_ARB_LEVEL_DIMM
#endif
//#define DEBUG_AUTO_ARB_LEVEL
#endif
//#define  DISABLE_DDR_A15
//#define DEBUG_DDR
//#define DEBUG_DDR_PARAM
#ifdef FASTBOOT
#undef PRINT_DDR_LEVELING
#else
#define PRINT_DDR_LEVELING
#endif
//#define DLL_DELAY_LOOP
//#define NO_AUTO_TRFC   //adjust TRFC param manually if defined
#define MM_PRINTSTR(x) \
    .section .rodata;98: .asciz x; .text; la a0, 98b; bl mm_stringserial

#define MM_TTYDBG MM_PRINTSTR
