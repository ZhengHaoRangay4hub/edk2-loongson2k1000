#include "PmonDefs.h"
#include "ddr_dir/ddr_entry.h"
	.text
ASM_GLOBAL ASM_PFX(ClkSettingAsm)
ASM_PFX(ClkSettingAsm):
	addi.d	$sp, $sp, -16
	st.d	$ra, $sp, 0
/*whd : loongson3_clksetting.S
	change the PLL settings of each core

ATTENTION:

         Using S1 for passing the NODE ID

	PLL
	40M > refclk/L1_div_ref >20M
	3.2G > refclk/ L1_div_ref*L1_loopc > 1.2G
	node_clock=refclk/L1_div_ref*L1_loopc/L1_divout/L2_divout
*/
#define SOFT_CLKSEL


#ifndef DDR_FREQ
/* MEM @ 500Mhz */
//#define DDR_FREQ   500   //this param must change with DDR freq together,ether soft or hard freq modified!!!
/* MEM @ 400Mhz */
#define DDR_FREQ   400
//#define DDR_FREQ   300
#endif
#ifdef SOFT_CLKSEL
#if 1
#define DDR_REFC   3
#define DDR_DIV    1
#define DDR_DIV_L2    6
#else
#define DDR_REFC   4
#define DDR_DIV    1
#define DDR_DIV_L2    4

#endif
#define DDR_LOOPC  (DDR_FREQ*DDR_REFC*DDR_DIV*DDR_DIV_L2/100)

#ifndef CORE_FREQ
/* CPU @ 800Mhz */
#define CORE_FREQ   800
#endif

#define L1_REFC     4
#define L1_DIV      1
#define L2_DIV      2
#define L1_LOOPC  (CORE_FREQ*L1_DIV*L2_DIV*L1_REFC/100)

/* GPU @ 400Mhz */
#define GPU_DIV_L2    7
#define HDA_DIV_L2    (DDR_FREQ*DDR_DIV_L2/24)

/* DC @ 200Mhz */
/* GMAC @ 125Mhz */
#define DC_LOOPC    80
#define DC_REFC     4
#define DC_DIV      1
#define DC_DIV_L2   8
#define GMAC_DIV    16

#define PIX0_LOOPC	109
#define PIX0_REFC	5
#define PIX0_DIV	1
#define PIX0_DIV_L2	20

#define PIX1_LOOPC	109
#define PIX1_REFC	5
#define PIX1_DIV	1
#define PIX1_DIV_L2	20
#define BYPASS_CORE 0x0
#define BYPASS_NODE 0x0
#define BYPASS_L1   0x0

#define PLL_CHANG_COMMIT 0x1
/*
#define BYPASS_REFIN 		(0x1 << 0)
*/
#define PLL_L1_LOCKED 		(0x1 << 16)
#define PLL_L1_ENA		(0x1 << 2)

#define PLL_MEM_ENA		(0x1 << 2)//chg
#define PLL_MEM_LOCKED 		(01 << 16)

#define HT_HSEL			(0x1 << 15)

	MM_PRINTSTR ("Soft CLK SEL adjust begin\r\n")

	li.d	t0, PHYS_TO_UNCACHED(0x1fe00480)
	li.d	t1, (0x1 << 19) 	//power down pll L1 first
	st.d	t1, t0, 0
	li.d	t1, (L1_LOOPC << 32) | (L1_DIV << 42) | (L1_REFC << 26) | (0x3 << 10) | (0x1 << 7)
	li.d	t2, L2_DIV
	st.d	t1, t0, 0
	st.d	t2, t0, 8
	ori	t1, t1, PLL_L1_ENA
	st.d    t1, t0, 0

11:
	ld.d	a0, t0, 0
	li.d	a1, PLL_L1_LOCKED
	and	a0, a1, a0
	beqz	a0, 11b //wait_locked_sys
	nop

	ld.d	a0, t0, 0
	ori     a0, a0, PLL_CHANG_COMMIT
	st.d    a0, t0, 0

	bl     hexserial
	nop

	MM_PRINTSTR ("\r\nMEM        :")

	li.d	t0, PHYS_TO_UNCACHED(0x1fe00490)
	li.d	t1, (0x1 << 19) 	//power down pll  first
	st.d	t1, t0, 0
	li.d    t1, (DDR_DIV << 42) | (DDR_REFC << 26) | (DDR_LOOPC << 32) | (0x3 << 10) | (0x1 << 7)
	li.d	t2, (GPU_DIV_L2 << 22) | (DDR_DIV_L2) | (HDA_DIV_L2 << 44)
	st.d	t1, t0, 0
	st.d	t2, t0, 0x8
	ori	t1, t1, PLL_L1_ENA
	st.d    t1, t0, 0

21:
	ld.w	a0, t0, 0
	li.w    a1, PLL_MEM_LOCKED
	and     a0, a0, a1
	beqz    a0, 21b //wait_locked_ddr
	nop

	ld.w	a0, t0, 0
	ori	a0, a0, 0x3
	st.w	a0, t0, 0

	bl     hexserial
	nop

	MM_PRINTSTR ("\r\nDC        :")

	li.d	t0, PHYS_TO_UNCACHED(0x1fe004a0)
	li.w	t1, (0x1 << 19) 	//power down pll  first
	st.d	t1, t0, 0
	li.d    t1, (DC_DIV << 42) | (DC_REFC << 26) | (DC_LOOPC << 32) | (0x3 << 10) | (0x1 << 7)
	li.d	t2, (GMAC_DIV << 22) | (DC_DIV_L2)
	st.d	t1, t0, 0
	st.d	t2, t0, 0x8
	ori	t1, t1, PLL_L1_ENA
	st.d    t1, t0, 0

21:
	ld.w	a0, t0, 0
	li.w    a1, PLL_MEM_LOCKED
	and     a0, a0, a1
	beqz    a0, 21b //wait_locked_ddr
	nop

	bl	initserial_later

	ld.w	a0, t0, 0
	ori     a0, a0, 0x3
	st.w	a0, t0, 0

	bl     hexserial
	nop

	MM_PRINTSTR ("\r\nPIX0        :")

	li.d	t0, PHYS_TO_UNCACHED(0x1fe004b0)		//pll_pix0
	li.w	t1, (0x1 << 19) 	//power down pll  first
	st.d	t1, t0, 0
	li.d    t1, (PIX0_DIV << 42) | (PIX0_REFC << 26) | (PIX0_LOOPC << 32) | (0x3 << 10) | (0x1 << 7)
	li.d	t2, PIX0_DIV_L2
	st.d	t1, t0, 0
	st.d	t2, t0, 0x8
	ori	t1, t1, PLL_L1_ENA
	st.d    t1, t0, 0

21:
	ld.w    a0, t0, 0
	li.w    a1, PLL_MEM_LOCKED
	and     a0, a0, a1
	beqz    a0, 21b
	nop

	ld.w    a0, t0, 0
	ori     a0, a0, 0x1
	st.w    a0, t0, 0

	bl     hexserial
	nop

	MM_PRINTSTR ("\r\nPIX1        :")


	li.d	t0, PHYS_TO_UNCACHED(0x1fe004c0)		//pll_pix1
	li.w	t1, (0x1 << 19) 	//power down pll  first
	st.d	t1, t0, 0
	li.d    t1, (PIX1_DIV << 42) | (PIX1_REFC << 26) | (PIX1_LOOPC << 32) | (0x3 << 10) | (0x1 << 7)
	li.d	t2, PIX1_DIV_L2
	st.d	t1, t0, 0
	st.d	t2, t0, 0x8
	ori	t1, t1, PLL_L1_ENA
	st.d    t1, t0, 0

21:
	ld.w    a0, t0, 0
	li.w    a1, PLL_MEM_LOCKED
	and     a0, a0, a1
	beqz    a0, 21b
	nop

	ld.w    a0, t0, 0
	ori     a0, a0, 0x1
	st.w    a0, t0, 0

	bl     hexserial
	nop


#endif
	ld.d	$ra, $sp, 0
	addi.d	$sp, $sp, 16
	jr	$ra
