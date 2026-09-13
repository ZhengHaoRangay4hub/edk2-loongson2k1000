/**********************************
	Author: chenxinke
	Date:   20150707
	mc_init for 3A8
	a5.0
	input:
	t7(option ARB_LEVEL)--do arb level, 0--not level; 1--do level;
	t3--MC select: 0--MC0; 1--MC1
**********************************/
#include "lsmc_config_param.S"

	.globl mc_init
mc_init:
	or    t7, ra, zero


	MM_TTYDBG("\r\nEnable register space of MEMORY\r\n")
	bl     enable_mc_conf_space
	nop

	GET_NODE_ID_a0;
	li.d     t8, DDR_MC_CONFIG_BASE
	or      t8, t8, a0

	//set parameter start location
#ifdef  ARB_LEVEL
	bnez    t7, 1f
	nop
	//if use leveled ddr param, the param location is fixed
	la     a2, ddr2_reg_data_mc0_leveled
	beqz    t3, 21f
	nop
	la     a2, ddr2_reg_data_mc1_leveled
21:
#ifdef  MULTI_CHIP
	GET_NODE_ID_a1
	beqz    a1, 21f
	nop
	la     a2, n1_ddr2_reg_data_mc0_leveled
	beqz    t3, 21f
	nop
	la     a2, n1_ddr2_reg_data_mc1_leveled
21:
#endif
	b       4f
	nop
1:
#endif
	GET_SDRAM_TYPE
	li.d     t1, 0x2
	beq     t1, a1, 2f
	nop
	li.d     t1, 0x3
	beq     t1, a1, 3f
	nop
	//not DDR2 and not DDR3, errors
	MM_PRINTSTR("\r\n!!! ERROR: NOT recognized DDR SDRAM TYPE. !!!\r\n");
	b       3f
	nop
2:  //DDR2
	GET_DIMM_TYPE
	bnez    a1, 1f
	nop
	//UDIMM
	la     a2, ddr2_reg_data
	beqz    t3, 21f
	nop
	la     a2, ddr2_reg_data_mc1
21:
#ifdef  MULTI_NODE_DDR_PARAM
	GET_NODE_ID_a1
	beqz    a1, 4f
	nop
	la     a2, n1_ddr2_reg_data
	beqz    t3, 21f
	nop
	la     a2, n1_ddr2_reg_data_mc1
21:
#endif
	b       4f
	nop
1:  //RDIMM
	la     a2, ddr2_RDIMM_reg_data
	beqz    t3, 21f
	nop
	la     a2, ddr2_RDIMM_reg_data_mc1
21:
#ifdef  MULTI_NODE_DDR_PARAM
	GET_NODE_ID_a1
	beqz    a1, 4f
	nop
	la     a2, n1_ddr2_RDIMM_reg_data
	beqz    t3, 21f
	nop
	la     a2, n1_ddr2_RDIMM_reg_data_mc1
21:
#endif
	b       4f
	nop
3:  //DDR3
	GET_DIMM_TYPE
	bnez    a1, 1f
	nop
	//UDIMM
	la     a2, ddr3_reg_data
	beqz    t3, 21f
	nop
	la     a2, ddr3_reg_data_mc1
21:
#ifdef  MULTI_NODE_DDR_PARAM
	GET_NODE_ID_a1
	beqz    a1, 4f
	nop
	la     a2, n1_ddr3_reg_data
	beqz    t3, 21f
	nop
	la     a2, n1_ddr3_reg_data_mc1
21:
#endif
	b       4f
	nop
1:  //RDIMM
	la     a2, ddr3_RDIMM_reg_data
	beqz    t3, 21f
	nop
	la     a2, ddr3_RDIMM_reg_data_mc1
21:
#ifdef  MULTI_NODE_DDR_PARAM
	GET_NODE_ID_a1
	beqz    a1, 4f
	nop
	la     a2, n1_ddr3_RDIMM_reg_data
	beqz    t3, 21f
	nop
	la     a2, n1_ddr3_RDIMM_reg_data_mc1
21:
#endif
	b       4f
	nop
4:

	bl     ddr2_config
	nop

#ifdef  PRINT_DDR_LEVELING   //print registers
	MM_PRINTSTR("The MC param is:\r\n")
	li.d     t1, DDR_PARAM_NUM
	GET_NODE_ID_a0
	li.d     t5, DDR_MC_CONFIG_BASE
	or      t5, t5, a0
1:
	ld.d      t6, t5, 0x0
	or    a0, t5, zero
	andi     a0, a0, 0xfff
	bl     mm_hexserial
	nop
	MM_PRINTSTR(":  ")
	srli.d    a0, t6, 32
	bl     mm_hexserial
	nop
	or    a0, t6, zero
	bl     mm_hexserial
	nop
	MM_PRINTSTR("\r\n")

	addi.d  t1, t1, -1
	addi.d  t5, t5, 8
	bnez    t1, 1b
	nop
#endif

	MM_TTYDBG("\r\nDisable register space of MEMORY\r\n")
	bl     disable_mc_conf_space
	nop
	MM_TTYDBG("\r\nDisable register space of MEMORY done.\r\n")

#ifdef  ARB_LEVEL   //Can not enable. because the ra destroy t7 and code is not port ok.
#ifdef  DEBUG_DDR_PARAM
	MM_PRINTSTR("\r\nSkip Memory training?(0: use mark to decide;1: skip ARB_level;)\r\n");
	li.d     t6, 0x00
	bl     inputaddress    #input value stored in a4
	nop
	bnez    a4, 8f
	nop
#endif
	//read ARB_level
	beqz    t7, 8f
	nop

	//route 0x1000000000 ~ 0x1FFFFFFFFF(64G) to MC for ARB_level
	dbar 0
	nop
	nop
	nop
	nop
	GET_NODE_ID_a0;
    /*WIN4 4G*/
	XBAR_CONFIG_NODE_a0(ARB_TEMP_L2WINDOW_OFFSET, \
				0x0000000200000000, \
				0xFFFFFFFF00000000, \
				0x00000000000000F0)
	beqz    t3, 2f
	nop
	GET_NODE_ID_a0;
    /*WIN4 4G*/
	XBAR_CONFIG_NODE_a0(ARB_TEMP_L2WINDOW_OFFSET, \
				0x0000000200000000, \
				0xFFFFFFFF00000000, \
				0x00000000000000F1)
2:
	dbar 0
	nop
	nop
	nop
	nop

	bl     ARB_level
	nop

	dbar 0
	nop
	nop
	nop
	nop

	L2XBAR_CLEAR_WINDOW(ARB_TEMP_L2WINDOW_OFFSET)

	dbar 0
	nop
	nop
	nop
	nop

8:
#else
#ifndef DISABLE_HARD_LEVELING
	li.d     a2, 0x3
	GET_SDRAM_TYPE
	bne     a1, a2, 88f
	nop
	//DDR3 SDRAM, do hard leveling
	MM_PRINTSTR("Start Hard Leveling...\r\n")
	MM_TTYDBG("\r\nEnable register space of MEMORY\r\n")
	bl     enable_mc_conf_space
	nop

	or    tp, t3, zero  //store t3, because ddr3_leveling will demage t3
#ifdef DLL_DELAY_LOOP
	or    k1, s2, zero
	li.d     s2, 0x0
	st.d      s2, t8, 0x350
	st.d      s2, t8, 0x358

	MM_PRINTSTR("\r\nPlease input the min value of dllclkloop: ");
	bl     inputaddress
	nop
	or    s2, a4, zero    #a4 is the input value

	MM_PRINTSTR("\r\nPlease input the max value of dllclkloop: ");
	bl     inputaddress
	nop
	li.d     t6, 0x0
	slli.d    t6, a4, 32   #a4 is the input value
	or      k1, t6, k1

loop_test_leveling:
//	la     a2, ddr3_RDIMM_reg_data
//	beqz    tp, mc0
//	nop
	la     a2, ddr3_RDIMM_reg_data_mc1
mc0:
	ld.d      t2, t8, 0x350
	ld.d      a6, t8, 0x358

	bl     ddr2_config
	nop

	st.d      t2, t8, 0x350
	st.d      a6, t8, 0x358

	li.d     t6, 0xfffffffffffffffe
	ld.d      t1, t8, START_ADDR
	and     t1, t1, t6
	st.d      t1, t8, START_ADDR
	dbar 0

	li.d     t6, 0x0
	st.b      t6, t8, 0x162
	dbar 0

	li.d     t6, 0x0
	or      t6, t6, s2
	slli.d    t6, t6, 8
	or      t6, t6, s2
	slli.d    t6, t6, 8
	or      t6, t6, s2
	slli.d    t6, t6, 8
	or      t6, t6, s2
	slli.d    t6, t6, 32

	ld.d      t1, t8, START_ADDR
	andi     t1, t1, 0x00000000ffffffff
	or      t1, t1, t6
	st.d      t1, t8, START_ADDR
	dbar 0

	li.d     t6, 0x1
	ld.d      t1, t8, START_ADDR
	or      t1, t1, t6
	st.d      t1, t8, START_ADDR
	dbar 0

/* 1. wait until init done */
	li.d     t1, 0x160
	or      t1, t1, t8
wait_dram_init_done1:
	ld.d      a0, t1, 0x0
	li.d     t4, 0x00000000ff000000
	and     a0, a0, t4
	beqz    a0, wait_dram_init_done1
	nop
#endif

	GET_NODE_ID_a0
	li.d     t8, DDR_MC_CONFIG_BASE
	or      t8, t8, a0
	bl     ddr3_leveling
	nop

#ifdef  PRINT_DDR_LEVELING   //print registers
	MM_PRINTSTR("The MC param after leveling is:\r\n")
	li.d     t1, DDR_PARAM_NUM
	GET_NODE_ID_a0
	li.d     t5, DDR_MC_CONFIG_BASE
	or      t5, t5, a0
1:
	ld.d      t6, t5, 0x0
	or    a0, t5, zero
	andi     a0, a0, 0xfff
	bl     mm_hexserial
	nop
	MM_PRINTSTR(":  ")
	srli.d    a0, t6, 32
	bl     mm_hexserial
	nop
	//MM_PRINTSTR("  ")
	or    a0, t6, zero
	bl     mm_hexserial
	nop
	MM_PRINTSTR("\r\n")

	addi.d  t1, t1, -1
	addi.d  t5, t5, 8
	bnez    t1, 1b
	nop
#endif

#ifdef DLL_DELAY_LOOP
/* test memory */
	li.d      t0, PHYS_TO_UNCACHED(0x1fe00424)
	ld.b      a0, t0, 0x1
	andi     a0, a0, 0xfd
	st.b      a0, t0, 0x1
	dbar 0

	li.d      t0, PHYS_TO_UNCACHED(0x00000000)
	li.d     a0, 0x5555555555555555
	st.d      a0, t0, 0x0
	li.d     a0, 0xaaaaaaaaaaaaaaaa
	st.d      a0, t0, 0x8
	li.d     a0, 0x3333333333333333
	st.d      a0, t0, 0x10
	li.d     a0, 0xcccccccccccccccc
	st.d      a0, t0, 0x18
	li.d     a0, 0x7777777777777777
	st.d      a0, t0, 0x20
	li.d     a0, 0x8888888888888888
	st.d      a0, t0, 0x28
	li.d     a0, 0x1111111111111111
	st.d      a0, t0, 0x30
	li.d     a0, 0xeeeeeeeeeeeeeeee
	st.d      a0, t0, 0x38

	MM_PRINTSTR("The uncache data is:\r\n")
	li.d     t1, 8
	li.d     t5, PHYS_TO_UNCACHED(0x00000000)
1:
	ld.d      t6, t5, 0x0
	or    a0, t5, zero
	andi     a0, a0, 0xfff
	bl     mm_hexserial
	nop
	MM_PRINTSTR(":  ")
	srli.d    a0, t6, 32
	bl     mm_hexserial
	nop
	or    a0, t6, zero
	bl     mm_hexserial
	nop
	MM_PRINTSTR("\r\n")
	beq     t1, 0x8, 2f
	nop
	beq     t1, 0x7, 3f
	nop
	beq     t1, 0x6, 4f
	nop
	beq     t1, 0x5, 5f
	nop
	beq     t1, 0x4, 6f
	nop
	beq     t1, 0x3, 7f
	nop
	beq     t1, 0x2, 8f
	nop
	beq     t1, 0x1, 9f
	nop

2:
	beq     t6, 0x5555555555555555, testok
	nop
	b       testfail
	nop

3:
	beq     t6, 0xaaaaaaaaaaaaaaaa, testok
	nop
	b       testfail
	nop

4:
	beq     t6, 0x3333333333333333, testok
	nop
	b       testfail
	nop

5:
	beq     t6, 0xcccccccccccccccc, testok
	nop
	b       testfail
	nop

6:
	beq     t6, 0x7777777777777777, testok
	nop
	b       testfail
	nop

7:
	beq     t6, 0x8888888888888888, testok
	nop
	b       testfail
	nop

8:
	beq     t6, 0x1111111111111111, testok
	nop
	b       testfail
	nop

9:
	beq     t6, 0xeeeeeeeeeeeeeeee, testok
	nop

testfail:
	MM_PRINTSTR("The uncached test failed\r\n")
	li.d      t0, PHYS_TO_UNCACHED(0x1fe00424)
	ld.b      a0, t0, 0x1
	or      a0, a0, 0x02
	st.b      a0, t0, 0x1
	dbar 0
	b       1f
	nop

testok:
	addi.d  t1, t1, -1
	addi.d  t5, t5, 8
	bnez    t1, 1b
	nop
	li.d      t0, PHYS_TO_UNCACHED(0x1fe00424)
	ld.b      a0, t0, 0x1
	or      a0, a0, 0x02
	st.b      a0, t0, 0x1
	dbar 0
	or      s2, s2, 0x100

1:
	andi     t6, s2, 0xff
	li.d     t1, 0x350
	beq  t6, 0x5f, 99f; 	bge     t6, 0x5f, 3f;99:
	nop
	beq  t6, 0x3f, 99f; 	bge     t6, 0x3f, 2f;99:
	nop
	beq  t6, 0x1f, 99f; 	bge     t6, 0x1f, 1f;99:
	nop

	or      t1, t1, t8
	ld.w      a0, t1, 0x0
	srli.d    t6, s2, 8
	andi     s2, s2, 0xff
	slli.d    t6, t6, s2
	b       4f
	nop

1:
	add.d   t1, t1, 0x4
	or      t1, t1, t8
	ld.w      a0, t1, 0x0
	srli.d    t6, s2, 8
	andi     s2, s2, 0xff
	sub.d   s2, s2, 0x20
	slli.d    t6, t6, s2
	add.d   s2, s2, 0x20
	b       4f
	nop

2:
	add.d   t1, t1, 0x8
	or      t1, t1, t8
	ld.w      a0, t1, 0x0
	srli.d    t6, s2, 8
	andi     s2, s2, 0xff
	sub.d   s2, s2, 0x40
	slli.d    t6, t6, s2
	add.d   s2, s2, 0x40
	b       4f
	nop

3:
	add.d   t1, t1, 0xc
	or      t1, t1, t8
	ld.w      a0, t1, 0x0
	srli.d    t6, s2, 8
	andi     s2, s2, 0xff
	sub.d   s2, s2, 0x60
	slli.d    t6, t6, s2
	add.d   s2, s2, 0x60

4:
	or      t6, a0, t6
	st.w      t6, t1, 0x0

	or    a0, s2, zero
	bl     mm_hexserial
	nop
	MM_PRINTSTR("\r\n")

	addi.d  s2, s2, 0x1
	li.d     t6, 0x0
	srli.d    t6, k1, 32
	bleu    s2, t6, loop_test_leveling
	nop
	andi     k1, k1, 0xffffffff

	MM_PRINTSTR("\r\nmc_reg_vector_for_diff_dll_training\r\n")
	ld.w      a0, t8, 0x35c
	bl     mm_hexserial
	nop
	ld.w      a0, t8, 0x358
	bl     mm_hexserial
	nop
	ld.w      a0, t8, 0x354
	bl     mm_hexserial
	nop
	ld.w      a0, t8, 0x350
	bl     mm_hexserial
	nop
	MM_PRINTSTR("\r\n")

//	la     a2, ddr3_RDIMM_reg_data
//	beqz    tp, mc0_1
//	nop
	la     a2, ddr3_RDIMM_reg_data_mc1
mc0_1:
	ld.d      t2, t8, 0x350
	ld.d      a6, t8, 0x358

	bl     ddr2_config
	nop

	st.d      t2, t8, 0x350
	st.d      a6, t8, 0x358

	li.d     t6, 0xfffffffffffffffe
	ld.d      t1, t8, 0x18
	and     t1, t1, t6
	st.d      t1, t8, 0x18
	dbar 0

calculate_best_successful_value:
//s2 reg struct explaination:
/*|15:8                                |7:0                           |
	|beginning value of biggest section  |currently scaning value       |
	|31:24                               |23:16                         |
	|temple beginning value to be compare|end value of biggest section  |
	|47:40                               |39:32                         |
	|end value of first section          |temple end value to be compare|*/

//	li.d     a0, 0xfff0000ffff00000
//	st.d      a0, 0x350(t8)      //for_test
//	li.d     a0, 0x0fffffff00000000
//	st.d      a0, t8, 0x358

	li.d     s2, 0x0
	li.d     t6, 0x0
	li.d     a0, 0x0
	li.d     t1, 0x0

	ld.d      a0, t8, 0x350
	andi     a0, a0, 0x1
	beqz    a0, scan1
	nop
1:
	andi     t6, s2, 0xff
	bgeu    t6, 63, 2f
	nop
	add.d   t6, t6, 0x1
	andi     s2, s2, 0xffffffffffffff00
	or      s2, t6, s2
	ld.d      a0, t8, 0x350
	srli.d    a0, a0, t6
	andi     a0, a0, 0x1
	bnez    a0, 1b
	nop
	b       record_first_section
	nop
2:
	bgeu    t6, 127, calculate
	nop
	ld.d      a0, t8, 0x358
	add.d   t6, t6, 0x1
	sub.d   t6, t6, 64
	srli.d    a0, a0, t6
	andi     a0, a0, 0x1
	add.d   t6, t6, 64
	andi     s2, s2, 0xffffffffffffff00
	or      s2, t6, s2
	bnez    a0, 2b
	nop

record_first_section:
	sub.d   t6, t6, 0x1
	slli.d    t6, t6, 40
	or      s2, s2, t6

scan1:
	andi     t6, s2, 0xff
	bgeu    t6, 63, 1f
	nop
	ld.d      a0, t8, 0x350
	add.d   t6, t6, 0x1
	andi     s2, s2, 0xffffffffffffff00
	or      s2, t6, s2
	srli.d    a0, a0, t6
	andi     a0, a0, 0x1
	beqz    a0, scan1
	nop
	b       record_start1
	nop

1:
	bgeu    t6, 127, calculate
	nop
	ld.d      a0, t8, 0x358
	add.d   t6, t6, 0x1
	andi     s2, s2, 0xffffffffffffff00
	or      s2, t6, s2
	sub.d   t6, t6, 64
	srli.d    a0, a0, t6
	add.d   t6, t6, 64
	andi     a0, a0, 0x1
	beqz    a0, scan1
	nop
	b       record_start1
	nop

record_start1:
	slli.d    t6, t6, 24
	andi     s2, s2, 0xffffffff00ffffff
	or      s2, t6, s2

scan0:
	andi     t6, s2, 0xff
	bgeu    t6, 63, 1f
	nop
	ld.d      a0, t8, 0x350
	add.d   t6, t6, 0x1
	andi     s2, s2, 0xffffffffffffff00
	or      s2, t6, s2
	srli.d    a0, a0, t6
	andi     a0, a0, 0x1
	bnez    a0, scan0
	nop
	b       record_end1
	nop
1:
	bgeu    t6, 127, calculate
	nop
	ld.d      a0, t8, 0x358
	add.d   t6, t6, 0x1
	andi     s2, s2, 0xffffffffffffff00
	or      s2, t6, s2
	sub.d   t6, t6, 64
	srli.d    a0, a0, t6
	add.d   t6, t6, 64
	andi     a0, a0, 0x1
	bnez    a0, scan0
	nop

record_end1:
	sub.d   t6, t6, 0x1
	slli.d    t6, t6, 32
	andi     s2, s2, 0xffffff00ffffffff
	or      s2, t6, s2
	andi     a0, s2, 0xff00
	srli.d    a0, a0, 8
	andi     t6, s2, 0xff0000
	srli.d    t6, t6, 16
	sub.d   t6, t6, a0
	andi     a0, s2, 0xff000000
	srli.d    a0, a0, 24
	andi     t1, s2, 0xff00000000
	srli.d    t1, t1, 32
	sub.d   t1, t1, a0
	bge     t1, t6, exchange
	nop
	b       scan1
	nop

exchange:
	srli.d    t6, s2, 16
	andi     t6, t6, 0xffff00
	andi     s2, s2, 0xffffffffff0000ff
	or      s2, t6, s2
	b       scan1
	nop

calculate:
	ld.d      a0, t8, 0x358
	andi     a0, a0, 0x8000000000000000
	beqz    a0, 1f
	nop
	andi     a0, s2, 0xff000000
	srli.d    a0, a0, 24
	li.d     t6, 0x80
	sub.d   a0, t6, a0
	andi     t6, s2, 0xff0000000000
	srli.d    t6, t6, 40
	add.d   t6, a0, t6
	andi     a0, s2, 0xff00
	srli.d    a0, a0, 8
	andi     t1, s2, 0xff0000
	srli.d    t1, t1, 16
	sub.d   t1, t1, a0
	bgeu    t1, t6, 2f
	nop
	srli.d    t6, t6, 1
	andi     a0, s2, 0xff000000
	srli.d    a0, a0, 24
	li.d     t1, 0x7f
	sub.d   t1, t1, a0
	andi     a0, s2, 0xff0000000000
	srli.d    a0, a0, 40
	bgeu    t1, a0, 3f
	nop
	sub.d   s2, a0, t6
	b       finish
	nop
3:
	andi     a0, s2, 0xff000000
	srli.d    a0, a0, 24
	add.d   s2, a0, t6
	b       finish
	nop
2:
	srli.d    t1, t1, 1
	add.d   s2, a0, t1
	b       finish
	nop
1:
	andi     a0, s2, 0xff00
	srli.d    a0, a0, 8
	andi     t1, s2, 0xff0000
	srli.d    t1, t1, 16
	sub.d   t1, t1, a0
	andi     t6, s2, 0xff0000000000
	srli.d    t6, t6, 40
	bgeu    t1, t6, first_short
	nop
	srli.d    t6, t6, 1
	or    s2, t6, zero
	b       finish
	nop

first_short:
	srli.d    t1, t1, 1
	add.d   s2, a0, t1

finish:
	li.d     t6, 0x0
	or      t6, t6, s2
	slli.d    t6, t6, 8
	or      t6, t6, s2
	slli.d    t6, t6, 8
	or      t6, t6, s2
	slli.d    t6, t6, 8
	or      t6, t6, s2
	slli.d    t6, t6, 32

	ld.d      t1, t8, START_ADDR
	andi     t1, t1, 0x00000000ffffffff
	or      t1, t1, t6
	st.d      t1, t8, START_ADDR
	dbar 0

	or    a0, t1, zero
	srli.d    a0, a0, 32
	bl     mm_hexserial
	nop
	or    a0, t1, zero
	bl     mm_hexserial
	nop
	MM_PRINTSTR("\r\n")

/*init start*/
	li.d     t6, 0x1
	ld.d      t1, t8, START_ADDR
	or      t1, t1, t6
	st.d      t1, t8, START_ADDR
	dbar 0

/* 1. wait until init done */
	li.d     t1, 0x160
	or      t1, t1, t8
wait_dram_init_done2:
	ld.d      a0, t1, 0x0
	li.d     t4, 0x00000000ff000000
	and     a0, a0, t4
	beqz    a0, wait_dram_init_done2
	nop

	GET_NODE_ID_a0
	li.d     t8, DDR_MC_CONFIG_BASE
	or      t8, t8, a0
	bl     ddr3_leveling
	nop

	or    s2, k1, zero
#endif

	or    t3, tp, zero

	//Re-set t0&t2 because mc_init(ddr3_leveling) will change t0~a6
	GET_NODE_ID_a0
	li.d     t2, PHYS_TO_UNCACHED(0x1fe20180)
	li.d     t0, PHYS_TO_UNCACHED(0x3ff00000)
	or      t2, t2, a0
	or      t0, t0, a0

#ifdef  PRINT_DDR_LEVELING   //print registers
	MM_PRINTSTR("The MC param after leveling is:\r\n")
	li.d     t1, DDR_PARAM_NUM
	GET_NODE_ID_a0
	li.d     t5, DDR_MC_CONFIG_BASE
	or      t5, t5, a0
1:
	ld.d      t6, t5, 0x0
	or    a0, t5, zero
	andi     a0, a0, 0xfff
	bl     mm_hexserial
	nop
	MM_PRINTSTR(":  ")
	srli.d    a0, t6, 32
	bl     mm_hexserial
	nop
	//MM_PRINTSTR("  ")
	or    a0, t6, zero
	bl     mm_hexserial
	nop
	MM_PRINTSTR("\r\n")

	addi.d  t1, t1, -1
	addi.d  t5, t5, 8
	bnez    t1, 1b
	nop
#endif
#if 0   //def  DEBUG_DDR_PARAM   //Change parameters of MC
	GET_NODE_ID_a0;
	li.d     a1, DDR_MC_CONFIG_BASE
	or      t8, a0, a1

	MM_PRINTSTR("\r\nChange some parameters of MC:");
1:
	MM_PRINTSTR("\r\nPlease input the register number you want to change!!!(0xfff:jump out.): ");
	li.d     t6, 0x00
	bl     inputaddress
	nop
	or    t5, a4, zero

	li.d     a1, 0x320
	bge     t5, a1, 2f    #if input address offset exceed range,jump out
	nop
	andi     t5, t5, 0xff8
	add.d   t5, t5, t8

	MM_PRINTSTR("\r\nPlease input the data-hex: ");
	li.d     t6, 0x00
	bl     inputaddress
	nop
	st.d      a4, 0x0(t5)    #a4 is the input value

	//print the new register value
	or    t6, t5, zero
	MM_PRINTSTR("\r\nRegister 0x")
	sub.d   t5, t5, t8
	or    a0, t5, zero
	bl     mm_hexserial
	nop
	MM_PRINTSTR(": ")
	ld.d      t6, t6, 0x0
	srli.d    a0, t6, 32
	bl     mm_hexserial
	nop
	or    a0, t6, zero
	bl     mm_hexserial
	nop

	b        1b
	nop
2:
#endif

	//MM_TTYDBG("Disable register space of MEMORY\r\n")
	bl     disable_mc_conf_space
	nop
88:
#endif
#endif

#ifndef  DISABLE_DIMM_ECC
	//Init ECC according to DIMM ECC info
	GET_DIMM_ECC
	beqz    a1, 4f
	nop
	MM_TTYDBG("ECC init start(maybe take 1 minute or so)....\r\n")

	//MM_TTYDBG("Enable register space of MEMORY\r\n")
	bl     enable_mc_conf_space
	nop

	GET_NODE_ID_a0;
	li.d     t8, DDR_MC_CONFIG_BASE
	or      t8, t8, a0

	//disable ECC interrupt
	ld.d      a2, t8, ECC_INT_ENABLE_ADDR
	li.d     a1, 0x3
	slli.d    a1, a1, ECC_INT_ENABLE_OFFSET
	nor     a1, a2, zero
	and     a2, a2, a1
	st.d      a2, t8, ECC_INT_ENABLE_ADDR

	//enable ECC function but without reporting error
	ld.d      a2, t8, ECC_ENABLE_ADDR
	li.d     a1, 0x7
	slli.d    a1, a1, ECC_ENABLE_OFFSET
	nor     a1, a1, zero
	and     a2, a2, a1
	li.d     a1, 0x1
	slli.d    a1, a1, ECC_ENABLE_OFFSET
	or      a2, a2, a1
	st.d      a2, t8, ECC_ENABLE_ADDR

	//MM_TTYDBG("Disable register space of MEMORY\r\n")
	bl     disable_mc_conf_space
	nop

	//route 0x1000000000 ~ 0x1FFFFFFFFF(64G) to MC for ECC init
	dbar 0
	nop
	nop
	nop
	nop
	GET_NODE_ID_a0;
    /*WIN4 4G*/
	XBAR_CONFIG_NODE_a0(ARB_TEMP_L2WINDOW_OFFSET, \
				0x0000000200000000, \
				0xFFFFFFFF00000000, \
				0x00000000000000F0)
	beqz    t3, 1f
	nop
	GET_NODE_ID_a0;
    /*WIN4 4G*/
	XBAR_CONFIG_NODE_a0(ARB_TEMP_L2WINDOW_OFFSET, \
				0x0000000200000000, \
				0xFFFFFFFF00000000, \
				0x00000000000000F1)

1:
	dbar 0
	nop
	nop
	nop
	nop
//init mem to all 0
	li.d     t1, 0xb800001000000000
	GET_NODE_ID_a0
	or      t1, t1, a0
	GET_MC0_MEMSIZE
	beqz    t3, 1f
	nop
	GET_MC1_MEMSIZE
1:
	slli.d    a1, a1, 29   //a1*512M
	add.d   t5, t1, a1
//write memory
1:
	bgeu    t1, t5, 1f
	nop

	st.d      zero, t1, 0x0
	st.d      zero, t1, 0x8
	st.d      zero, t1, 0x10
	st.d      zero, t1, 0x18
	st.d      zero, t1, 0x20
	st.d      zero, t1, 0x28
	st.d      zero, t1, 0x30
	st.d      zero, t1, 0x38
	add.d   t1, t1, 0x40
	b       1b
	nop
1:

	dbar 0
	nop
	nop
	nop
	nop

	L2XBAR_CLEAR_WINDOW(ARB_TEMP_L2WINDOW_OFFSET)

	dbar 0
	nop
	nop
	nop
	nop

	//MM_TTYDBG("Enable register space of MEMORY\r\n")
	bl     enable_mc_conf_space
	nop

	//enable ECC function with reporting error
	ld.d      a2, t8, ECC_ENABLE_ADDR
	li.d     a1, 0x7
	slli.d    a1, a1, ECC_ENABLE_OFFSET
	nor     a1, a1, zero
	and     a2, a2, a1
	li.d     a1, 0x7
	slli.d    a1, a1, ECC_ENABLE_OFFSET
	or      a2, a2, a1
	st.d      a2, t8, ECC_ENABLE_ADDR

	//enable ECC interrupt
	ld.d      a2, t8, ECC_INT_ENABLE_ADDR
	li.d     a1, 0x3
	slli.d    a1, a1, ECC_INT_ENABLE_OFFSET
	or      a2, a2, a1
	st.d      a2, t8, ECC_INT_ENABLE_ADDR

	//MM_PRINTSTR("\r\nDisable register space of MEMORY\r\n")
	bl     disable_mc_conf_space
	nop

	MM_TTYDBG("MC ECC init done.\r\n")
4:
#endif

	or    ra, t7, zero
    jirl    zero, ra, 0
	nop

//for 3A8
LEAF(enable_mc_conf_space)
/*********************
pre-condition::
	t2: chip configure register address
	t3: MC select
*********************/
	li.d t2, PHYS_TO_UNCACHED(0x1fe00420)
	li.w a5, 0x100
	nor a5,a5, zero
	ld.w a2, t2, 0x4
	and     a5, a5, a2
 	st.w      a5, t2, 0x4
	dbar 0
#if 0
	ld.w      a2, t2, 0x0
	li.w      a5, 0x1
	beqz    t3, 1f
	nop
	sll     a5, a5, 5
1:
	sll     a5, a5, DDR_CONFIG_DISABLE_OFFSET
	nor     a5, a5, zero
	and     a2, a2, a5
	st.w      a2, t2, 0x0
	dbar 0
#endif

    jirl    zero, ra, 0
	nop
END(enable_mc_conf_space)

LEAF(disable_mc_conf_space)
/*********************
pre-condition::
	t2: chip configure register address
	t3: MC select
*********************/
#if 0
	ld.w      a2, t2, 0x0
	li.w      a5, 0x1
	beqz    t3, 1f
	nop
	sll     a5, a5, 5
1:
	sll     a5, a5, DDR_CONFIG_DISABLE_OFFSET
	or      a2, a2, a5
	st.w      a2, t2, 0x0
	dbar 0
#endif
	li.d t2, PHYS_TO_UNCACHED(0x1fe00420)
	li.w a5, 0x100
	ld.w a2, t2, 0x4
	or     a5, a5, a2
 	st.w      a5, t2, 0x4
	dbar 0

    jirl    zero, ra, 0
	nop
END(disable_mc_conf_space)

LEAF(enable_mc_read_buffer)

    jirl    zero, ra, 0
	nop
END(enable_mc_read_buffer)

LEAF(disable_mc_read_buffer)

    jirl    zero, ra, 0
	nop
END(disable_mc_read_buffer)

LEAF(disable_cpu_buffer_read)

    jirl    zero, ra, 0
	nop
END(disable_cpu_buffer_read)

LEAF(get_mem_clk)
/*********************
	a4: current ddr freq setting
*********************/
#if 0
	li.d t0,PHYS_TO_UNCACHED(0x1fe20190)
	ld.d t1,t0, 0x0
	srli.d t2,t1,37
	andi t2,t2,0x0000001f
	or a4,t2, zero
#endif

	nop
    jirl    zero, ra, 0
	nop
END(get_mem_clk)
