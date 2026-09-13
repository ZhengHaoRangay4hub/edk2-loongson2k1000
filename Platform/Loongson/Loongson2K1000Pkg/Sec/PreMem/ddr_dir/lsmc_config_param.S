/**********************************
    Author: chenxinke
    Date:   20150708
    a5.0
        support lsmc(3A8, 3B5~)
    input param:
    a2: mc param address
    t7(option ARB_LEVEL)--do arb level, 0--not level; 1--do level;
    t8: input, Memory Controller config register base
    t3: controller select
        0: MC0
        1: MC1
**********************************/

        .globl ddr2_config
ddr2_config:
    sub.d   a2, a2, s0
    li.d     t1, DDR_PARAM_NUM
    addi.d  a4, t8, 0x0
//write param registers
1:
    ld.d      a1, a2, 0x0
    st.d      a1, a4, 0x0
    addi.d  t1, t1, -1
    addi.d  a2, a2, 0x8
    addi.d  a4, a4, 0x8
    bnez    t1, 1b
    nop
#ifdef DDR_RESET_REVERT
#define DDR_PARAM_150_RESET 0x0002000000000000
#else
#define DDR_PARAM_150_RESET 0
#endif

#ifdef LS2K_STR
    /*If S3 mode: configure memory controller, make sure the memory reset is high*/
    ld.d      t1, t8, 0x150
    li.d	    a0, (0xff<<48)
    nor	    a0, a0, zero
    and	    t1, t1, a0

    li.d     a1, PHYS_TO_UNCACHED(0x1fe27050)
    ld.w	    a4, a1, 0x0
    li.w	    a1, 0x5a5a5a5a
    bne	    a1, a4, 1f
    nop
    
    li.d	    a0, (0x01<<48) ^ DDR_PARAM_150_RESET
    b	    2f
    nop

1:
    li.d	    a0, (0x02<<48) ^ DDR_PARAM_150_RESET
2:
    or	    t1, t1, a0
    st.d      t1, t8, 0x150
    /*clear mem_ctrl_flag*/
    li.d     a0, PHYS_TO_UNCACHED(0x1fe27050)
    st.w      zero, a0, 0x0
#endif
#if 0
//autoset param registers
set_tMOD:
	li.d		t1, FREQ
	li.d		t3, 15
	mul.d	t3, t3, t1
	li.d  tp, 2000;  div.du	t3, t3, tp
	addi.d	t3, t3, 1
	bge		t3, 12, 1f
	nop
	li.w		t3, 0xc
1:
	li.d		t1,	0x1c0
	or 		t1, t1, t8
	st.b		t3, t1, 0x4

set_tFAW:
	li.d		t1, FREQ
	li.d		t3, 0x1e
	mul.d	t3, t3, t1
	li.d  tp, 2000;  div.du	t3, t3, tp
	addi.d	t3, t3, 1

	li.d		t1, 0x1c8
	or		t1, t1, t8
	st.b		t3, t1, 0x7

set_tRRD:
	li.d		t1, FREQ
	li.d		t3, 0x6
	mul.d	t3, t3, t1
	li.d  tp, 2000;  div.du	t3, t3, tp
	addi.d	t3, t3, 1
	bge		t3, 4, 1f
	nop
	li.w		t3, 0x4
1:
	li.d		t1, 0x1c8
	or		t1, t1, t8
	st.b		t3, t1, 0x6

/*set_tRCD:
	li.d		t1, FREQ
	li.d		t3, 0xb
	mul.d	t3, t3, t1
	li.d  tp, 1600;  div.du	t3, t3, tp
	addi.d	t3, t3, 1

	li.d		t1, 0x1c8
	or		t1, t1, t8
	st.b		t3, t1, 0x5
	nop

set_tRP:
	li.d		t1, FREQ
	li.d		t3, 0xb
	mul.d	t3, t3, t1
	li.d  tp, 1600;  div.du	t3, t3, tp
	addi.d	t3, t3, 1

	li.d		t1, 0x1c8
	or		t1, t1, t8
	st.b		t3, t1, 0x4
	nop
*/
set_tREFI:
	li.d		t1, FREQ
	li.d  tp, 10;  div.du	t1, t1, tp
	li.d		t3, 78
	mul.d	t3, t3, t1
	srli.d	t3, t3, 9
	addi.d	t3, t3, 1

	li.d		t1, 0x1c8
	or		t1, t1, t8
	st.b		t3, t1, 0x3

set_tRFC:
    GET_MC0_MEMSIZE
    or	t1, a1, zero
//	or	a0, a1, zero
//	bl		mm_hexserial
	nop
	GET_MC_CS_MAP
//	or	a0, a1, zero
//	bl		mm_hexserial
	nop
	li.d 	t5, 0x4
	li.d		t3, 0x0
cal_memsize:
	li.d  tp, 1;  sub.d	t5, t5, tp
	beqz	t5, 1f
	nop
	andi		t4, a1, 0x1
	srli.d	a1, a1, 0x1
	beqz	t4, cal_memsize
	nop
	addi.d	t3, t3, 1
	b		cal_memsize
	nop

1:
	div.du	a2, t1, t3

	li.d		t1, 0x1
	li.d		t3, 0x9
	blt		a2, t1, 21f

	li.d		t1, 0x2
	li.d		t3, 0xb
	blt		a2, t1, 21f

	li.d		t1, 0x4
	li.d		t3, 0x10
	blt		a2, t1, 21f

	li.d		t1, 0x8
	li.d		t3, 0x1a
	blt		a2, t1, 21f

	li.d		t1, 0x10
	li.d		t3, 0x22
	blt		a2, t1, 21f

	MM_PRINTSTR("\r\n memsize wrong \r\n")
	b 		2f
	nop

21:

	li.d		t1, FREQ
	mul.d	t3, t3, t1
	li.d  tp, 200;  div.du	t3, t3, tp

	li.d		t1, 0x1c8
	or		t1, t1, t8
	st.b		t3, t1, 0x2
2:

set_ZQCS:
	li.d		t1, FREQ
	li.d		t3, 0x50
	mul.d	t3, t3, t1
	li.d  tp, 2000;  div.du	t3, t3, tp
	addi.d	t3, t3, 1
	bge		t3, 64, 1f
	nop
	li.d		t3, 64
1:
	li.d		t1, 0x1c8
	or		t1, t1, t8

	/*ld.b		t4, t1, 0x3
	div.du	t3, t3, t4
	addi.d	t3, t3, 1*/

	st.b		t3, t1, 0x1

set_tXPDLL:
	li.d		t1, FREQ
	li.d		t3, 0x18
	mul.d	t3, t3, t1
	li.d  tp, 2000;  div.du	t3, t3, tp
	addi.d	t3, t3, 1
	bge		t3, 10, 1f
	nop
	li.d		t3, 10
1:
	li.d		t1, 0x1d8
	or		t1, t1, t8
	st.b		t3, t1, 0x7

set_tXP:
	li.d		t1, FREQ
	li.d		t3, 0x6
	mul.d	t3, t3, t1
	li.d  tp, 2000;  div.du	t3, t3, tp
	addi.d	t3, t3, 1
	bge		t3, 3, 1f
	nop
	li.d		t3, 3
1:
	li.d		t1, 0x1d8
	or		t1, t1, t8
	st.b		t3, t1, 0x6

set_tWR:
	li.d		t1, FREQ
	li.d		t3, 0x15
	mul.d	t3, t3, t1
	li.d  tp, 2000;  div.du	t3, t3, tp
	addi.d	t3, t3, 1
1:
	li.d		t1, 0x1d8
	or		t1, t1, t8
	st.b		t3, t1, 0x5


set_tRTP:
	li.d		t1, FREQ
	li.d		t3, 0x8
	mul.d	t3, t3, t1
	li.d  tp, 2000;  div.du	t3, t3, tp
	addi.d	t3, t3, 1
	bge		t3, 4, 1f
	nop
	li.d		t3, 4
1:
	li.d		t1, 0x1d8
	or		t1, t1, t8
	st.b		t3, t1, 0x4


/*set_tRL:
	li.d		t1, FREQ
	li.d		t3, 0xb
	mul.d	t3, t3, t1
	li.d  tp, 1600;  div.du	t3, t3, tp
	addi.d	t3, t3, 1

	li.d		t1, 0x1d8
	or		t1, t1, t8
	st.b		t3, t1, 0x3

	li.d  tp, 2;  sub.d	t3, t3, tp
	li.d		t1, 0x1c0
	or 		t1, t1, t8
	st.b		t3, t1, 0x0

	li.d		t1, 0x1a0
	or 		t1, t1, t8
	ld.b		t4, t1, 0x0
	li.w		t5, 0x8b//10001011
	and		t4, t4, t5
	li.d  tp, 2;  sub.d	t3, t3, tp
	li.w		t5, 0x7
	and		t3, t3, t5
	slli.d	t3, t3, 4
	or		t4, t4, t3

	li.d		t1, FREQ
	li.d		t3, 0xb
	mul.d	t3, t3, t1
	li.d  tp, 1600;  div.du	t3, t3, tp
	addi.d	t3, t3, 1
	li.d  tp, 4;  sub.d	t3, t3, tp
	li.d		t5, 0x8
	and		t3, t3, t5
	srli.d	t3, t3, 1
	or		t4, t4, t3

	li.d		t1, 0x1a0
	or		t1, t1, t8
	st.b		t4, t1, 0x0
	st.b		t4, t1, 0x8
	st.b		t4, t1, 0x10
	st.b		t4, t1, 0x18
*/
#endif
set_tREFI:
	li.d		t1, DDR_FREQ
	li.d  tp, 10;  div.du	t1, t1, tp
	li.d		a2, 78
	mul.d	a2, a2, t1
#ifndef TEMP_EXTREME
	srli.d	a2, a2, 8
#else
	srli.d	a2, a2, 9
#endif
//	add.d	a2, a2, 1
	li.d		t1, 0x1c8
	or		t1, t1, t8
	st.b		a2, t1, 0x3

#ifndef NO_AUTO_TRFC
set_tRFC:
    GET_MC0_MEMSIZE
    beqz    t3, 1f
    nop
    GET_MC1_MEMSIZE
1:
    or	t1, a1, zero
	GET_MC_CS_MAP
    beqz    t3, 1f
    nop
	GET_MC1_CS_MAP
1:
	li.d 	t5, 0x4
	li.d		a2, 0x0
cal_memsize:
	li.d  tp, 1;  sub.d	t5, t5, tp
	beqz	t5, 1f
	nop
	andi		t4, a1, 0x1
	srli.d	a1, a1, 0x1
	beqz	t4, cal_memsize
	nop
	addi.d	a2, a2, 1
	b		cal_memsize
	nop
1:
	div.du	a2, t1, a2

    GET_SDRAM_WIDTH
    beqz    t3, 1f
    nop
    GET_MC1_SDRAM_WIDTH
1:
	li.d     t5, 0x2
    beqz    a1, x8
    nop
	li.d     t5, 0x1
x8:
	div.du	a2, a2, t5

	li.d		t1, 0x1
	li.d		t5, 0x9
	blt		a2, t1, 21f

	li.d		t1, 0x2
	li.d		t5, 0xb
	blt		a2, t1, 21f

	li.d		t1, 0x4
	li.d		t5, 0x10
	blt		a2, t1, 21f

	li.d		t1, 0x8
	li.d		t5, 0x1a
	blt		a2, t1, 21f

	li.d		t1, 0x10
	li.d		t5, 0x23
	blt		a2, t1, 21f

	MM_PRINTSTR("\r\n memsize wrong \r\n")
	b 		2f
	nop
21:

	li.d		t1, DDR_FREQ
	mul.d	t5, t5, t1
	li.d  tp, 100;  div.du	t5, t5, tp

	li.d		t1, 0x1c8
	or		t1, t1, t8
	st.b		t5, t1, 0x2

2:
#endif

    //for UDIMM 4cs,open 2T mode
    GET_DIMM_TYPE
    bnez    a1, 1f
    nop
    //UDIMM
    GET_MC_CS_MAP
    li.d     a2, 0xf
    bne     a1, a2, 1f
    nop
    //add cmd_timing ,trddata and tphy_wrlat by one
    ld.d      a2, t8, CMD_TIMING
    li.d     a1, 0x1
    slli.d    a1, a1, CMD_TIMING_OFFSET
    add.d   a2, a2, a1
    st.d      a2, t8, CMD_TIMING

    ld.d      a2, t8, TRDDATA
    li.d     a1, 0x1
    slli.d    a1, a1, TRDDATA_OFFSET
    add.d   a2, a2, a1
    st.d      a2, t8, TRDDATA

    ld.d      a2, t8, TPHY_WRLAT
    li.d     a1, 0x1
    slli.d    a1, a1, TPHY_WRLAT_OFFSET
    add.d   a2, a2, a1
    st.d      a2, t8, TPHY_WRLAT

1:
    //rewrite eight_bank_mode
    //rewrite pm_bank_diff_0 and pm_bank

    //for UDIMM 4cs,open 2T mode
    GET_DIMM_TYPE
    bnez    a1, 1f
    nop
    //UDIMM
    GET_MC_CS_MAP
    li.d     a2, 0xf
    bne     a1, a2, 1f
    nop
    //add cmd_timing ,trddata and tphy_wrlat by one
    ld.d      a2, t8, CMD_TIMING
    li.d     a1, 0x1
    slli.d    a1, a1, CMD_TIMING_OFFSET
    add.d   a2, a2, a1
    st.d      a2, t8, CMD_TIMING

    ld.d      a2, t8, TRDDATA
    li.d     a1, 0x1
    slli.d    a1, a1, TRDDATA_OFFSET
    add.d   a2, a2, a1
    st.d      a2, t8, TRDDATA

    ld.d      a2, t8, TPHY_WRLAT
    li.d     a1, 0x1
    slli.d    a1, a1, TPHY_WRLAT_OFFSET
    add.d   a2, a2, a1
    st.d      a2, t8, TPHY_WRLAT

1:
    //rewrite eight_bank_mode
    //rewrite pm_bank_diff_0 and pm_bank
    ld.d      a2, t8, EIGHT_BANK_MODE_ADDR
    li.d     a1, 0x3
    slli.d    a1, a1, EIGHT_BANK_MODE_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1
    GET_EIGHT_BANK
    xori     a1, a1, 0x1
    slli.d    a1, a1, EIGHT_BANK_MODE_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, EIGHT_BANK_MODE_ADDR

    //for version 3, pm_bank not used, changed to cs_redbar 0
    ld.w      a2, t8, 0x0
    li.d     a1, 0x3
    beq     a2, a1, 1f
    nop
    //rewrite pm_bank
    ld.d      a2, t8, BANK_NUM_ADDR
    li.d     a1, 0x7
    slli.d    a1, a1, BANK_NUM_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1
    li.d     a4, 0x7
    GET_EIGHT_BANK
    xori     a1, a1, 0x1
    srl.d    a1, a4, a1
    slli.d    a1, a1, BANK_NUM_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, BANK_NUM_ADDR

#ifndef MC_MULTI_CHANNEL
    //rewrite pm_addr_win
    ld.d      a2, t8, ADDR_WIN_BANK_NUM_ADDR
    li.d     a1, 0x3
    slli.d    a1, a1, ADDR_WIN_BANK_NUM_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1
    li.d     a4, 0x2
    GET_EIGHT_BANK
    or      a1, a4, a1
    slli.d    a1, a1, ADDR_WIN_BANK_NUM_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, ADDR_WIN_BANK_NUM_ADDR
#endif

1:

    //rewrite row_diff and column_diff
    ld.d      a2, t8, ROW_DIFF_ADDR
    li.d     a1, 0x7
    slli.d    a1, a1, ROW_DIFF_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1
    GET_ROW_SIZE
    slli.d    a1, a1, ROW_DIFF_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, ROW_DIFF_ADDR

    ld.d      a2, t8, COLUMN_DIFF_ADDR
    li.d     a1, 0x7
    slli.d    a1, a1, COLUMN_DIFF_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1
    GET_COL_SIZE
    addi.d   a1, a1, 0x4
    slli.d    a1, a1, COLUMN_DIFF_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, COLUMN_DIFF_ADDR

    //rewrite cs_diff
    ld.d      a2, t8, CS_DIFF_ADDR
    li.d     a1, 0x3
    slli.d    a1, a1, CS_DIFF_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1
    //count cs num to a3
    GET_MC_CS_MAP
    andi     a0, a1, 0x1
    or    a3, a0, zero
    srli.d    a1, a1, 1
    andi     a0, a1, 0x1
    add.d   a3, a3, a0
    srli.d    a1, a1, 1
    andi     a0, a1, 0x1
    add.d   a3, a3, a0
    srli.d    a1, a1, 1
    andi     a0, a1, 0x1
    add.d   a3, a3, a0

    or    a1, zero, zero
    //li.d   a0, 0x2
    addi.d   a0, zero, 0x1
    addi.d   a0, a0, 0x1
    beq  a3, a0, 99f;     bge     a3, a0, 1f;99:  //4 or 3 ranks
    nop
    addi.d   a1, a1, 0x1
    beq     a3, a0, 1f  //2 ranks
    nop
    addi.d   a1, a1, 0x1 //1 or 0 rank
1:
    slli.d    a1, a1, CS_DIFF_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, CS_DIFF_ADDR

    andi     a0, a3, 0x1
    beqz    a0, 1f
    nop
    //if there are 1 or 3 ranks, disable cs_place
    ld.d      a2, t8, CS_PLACE_ADDR
    li.d     a1, 0x1
    slli.d    a1, a1, CS_PLACE_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1
    st.d      a2, t8, CS_PLACE_ADDR
1:
    //rewrite cs_enable cs_mrs and cs_zq
    ld.d      a2, t8, CS_ENABLE_ADDR
    li.d     a1, 0xf
    slli.d    a1, a1, CS_ENABLE_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1
    //GET_MC_CS_MAP
    li.d     a1, 0xf
    slli.d    a1, a1, CS_ENABLE_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, CS_ENABLE_ADDR

    ld.d      a2, t8, CS_MRS_ADDR
    li.d     a1, 0xf
    slli.d    a1, a1, CS_MRS_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1
    GET_MC_CS_MAP
    slli.d    a1, a1, CS_MRS_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, CS_MRS_ADDR

    ld.d      a2, t8, CS_ZQ_ADDR
    li.d     a1, 0xf
    slli.d    a1, a1, CS_ZQ_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1
    GET_MC_CS_MAP
    slli.d    a1, a1, CS_ZQ_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, CS_ZQ_ADDR

    //for version 3, pm_bank not used, changed to cs_redbar 0
    ld.w      a2, t8, 0x0
    li.d     a1, 0x3
    bne     a2, a1, 1f
    nop
    ld.d      a2, t8, BANK_NUM_ADDR
    li.d     a1, 0xf
    slli.d    a1, a1, BANK_NUM_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1
    GET_MC_CS_MAP
    slli.d    a1, a1, BANK_NUM_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, BANK_NUM_ADDR

1:

    //reconfigure pm_cs_map
    ld.d      a2, t8, CS_MAP_ADDR
    li.d     a1, 0xff
    slli.d    a1, a1, CS_MAP_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1

    //a0: logic cs; a3: pm_cs_map; a4: temp; a5: DDR_CS pin;
    or    a0, zero, zero
    or    a3, zero, zero
    or    a5, zero, zero
    GET_MC_CS_MAP
2:
    andi     a4, a1, 0x1
    beqz    a4, 1f
    nop
    slli.d    a4, a0, 1   //a4 = a0 * 2
    sll.d    a4, a5, a4
    or      a3, a3, a4
    addi.d   a0, a0, 0x1
1:
    addi.d   a5, a5, 0x1
    srli.d    a1, a1, 1
    li.d     a4, 0x4
    blt     a5, a4, 2b
    nop

    slli.d    a3, a3, CS_MAP_OFFSET
    or      a2, a2, a3
    st.d      a2, t8, CS_MAP_ADDR

    //rewrite lvl_cs
    ld.d      a2, t8, LEVEL_CS_ADDR
    li.d     a1, 0xf
    slli.d    a1, a1, LEVEL_CS_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1
    GET_MC_CS_MAP
    beqz    a1, 4f
    nop
    addi.d   a5, zero, 0x1
1:
    and     a4, a1, a5
    bnez    a4, 2f
    nop
    slli.d    a5, a5, 1
    b       1b
    nop
2:
    slli.d    a5, a5, LEVEL_CS_OFFSET
    or      a2, a2, a5
    st.d      a2, t8, LEVEL_CS_ADDR
4:

    //reconfig address_mirroring
    ld.d      a2, t8, ADDRESS_MIRROR_ADDR
    li.d     a1, 0xf
    slli.d    a1, a1, ADDRESS_MIRROR_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1
    //When use RDIMM, ignore address mirror bit
    GET_DIMM_TYPE
    bnez    a1, 1f
    nop
    GET_ADDR_MIRROR
    beqz    a1, 1f
    nop
    li.d     a1, 0xa
    b       2f
    nop
1:
    li.d     a1, 0x0
2:
    slli.d    a1, a1, ADDRESS_MIRROR_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, ADDRESS_MIRROR_ADDR
#ifndef MANAUL_ODT_MAP
    //reconfig ODT map
    //set default first
    //clear map first
    li.d     a1, 0x0000ffff0000ffff
    ld.d      a2, t8, ODT_MAP_CS_ADDR
    and     a2, a2, a1
    st.d      a2, t8, ODT_MAP_CS_ADDR

    li.d     a2, 0x8421000000000000  //DDR3
    GET_SDRAM_TYPE
    li.d     a0, 0x3
    beq     a0, a1, 2f
    nop

    li.d     a2, 0x8421000084210000  //DDR2
2:
    ld.d      a1, t8, ODT_MAP_CS_ADDR
    or      a2, a2, a1
    st.d      a2, t8, ODT_MAP_CS_ADDR

    //a4 store cs map
    GET_MC_CS_MAP
    or    a4, a1, zero
    //step 1: swap open wr odt if it's a Dual Rank DIMM
    //check cs_map[3]
    srli.d    a2, a4, 3
    beqz    a2, 1f
    nop
    //slot 1 is a DR DIMM
    ld.d      a2, t8, ODT_MAP_CS_ADDR
    li.d     a1, 0x00ffffffffffffff
    and     a2, a2, a1
    li.d     a1, 0x4800000000000000
    or      a2, a2, a1
    st.d      a2, t8, ODT_MAP_CS_ADDR
1:
    //check cs_map[1]
    srli.d    a2, a4, 1
    andi     a2, a2, 0x1
    beqz    a2, 1f
    nop
    //slot 0 is a DR DIMM
    ld.d      a2, t8, ODT_MAP_CS_ADDR
    li.d     a1, 0xff00ffffffffffff
    and     a2, a2, a1
    li.d     a1, 0x0012000000000000
    or      a2, a2, a1
    st.d      a2, t8, ODT_MAP_CS_ADDR
1:
    //step 2: open extra RD/WR ODT CS if there is 2 DIMM
    //check CS[0] and CS[2]
    srli.d    a2, a4, 2
    xor     a2, a4, a2
    andi     a2, a2, 0x1
    bnez    a2, 1f
    nop
    //2 DIMM: open the first rank of the non-target DIMM
    ld.d      a2, t8, ODT_MAP_CS_ADDR
    li.d     a1, 0x1144000011440000
    or      a2, a2, a1
    st.d      a2, t8, ODT_MAP_CS_ADDR
1:  //1 DIMM
#if 0
    //if its DDR3_DIMM, enable dynamic ODT and reset ODT value
    GET_SDRAM_TYPE
    li.d     a2, 0x3
    bne     a2, a1, 1f
    nop
    //DDR3 DIMM, enable RTT_wr
    ld.d      a2, t8, MR2_DATA_0_ADDR
    li.d     a1, 0x0400
    slli.d    a1, a1, MR2_DATA_0_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, MR2_DATA_0_ADDR

    ld.d      a2, t8, MR2_DATA_1_ADDR
    li.d     a1, 0x0400
    slli.d    a1, a1, MR2_DATA_1_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, MR2_DATA_1_ADDR

    ld.d      a2, t8, MR2_DATA_2_ADDR
    li.d     a1, 0x0400
    slli.d    a1, a1, MR2_DATA_2_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, MR2_DATA_2_ADDR

    ld.d      a2, t8, MR2_DATA_3_ADDR
    li.d     a1, 0x0400
    slli.d    a1, a1, MR2_DATA_3_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, MR2_DATA_3_ADDR
1:
#endif
#endif
#if !defined(CONFIG_DDR_32BIT) &&  !defined(CONFIG_DDR_16BIT) 
    //set data bus width
    ld.d      a2, t8, DATA_WIDTH_32_ADDR
    li.d     a1, 0x1
    slli.d    a1, a1, DATA_WIDTH_32_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1
    GET_DIMM_WIDTH
    slli.d    a1, a1, DATA_WIDTH_32_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, DATA_WIDTH_32_ADDR
#ifndef MC_MULTI_CHANNEL
    //rewrite multi_channel mode
    ld.d      a2, t8, MC_MULTI_CHANNEL_ADDR
    li.d     a1, 0x1
    slli.d    a1, a1, MC_MULTI_CHANNEL_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1
    GET_DIMM_WIDTH
    slli.d    a1, a1, MC_MULTI_CHANNEL_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, MC_MULTI_CHANNEL_ADDR
#endif
#ifndef MC_MULTI_CHANNEL
    //rewrite pm_addr_win(data width)
    ld.d      a2, t8, ADDR_WIN_DATA_WIDTH_ADDR
    li.d     a1, 0x3
    slli.d    a1, a1, ADDR_WIN_DATA_WIDTH_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1
    li.d     a4, 0x3
    GET_DIMM_WIDTH
    xor     a1, a4, a1
    slli.d    a1, a1, ADDR_WIN_DATA_WIDTH_OFFSET
    or      a2, a2, a1
    st.d      a2, t8, ADDR_WIN_DATA_WIDTH_ADDR
#endif
#endif
    //disable ECC module here for leveling, ECC will be enabled later
    ld.d      a2, t8, ECC_ENABLE_ADDR
    li.d     a1, 0x7
    slli.d    a1, a1, ECC_ENABLE_OFFSET
    nor     a1, a1, zero
    and     a2, a2, a1
#ifndef DISABLE_DIMM_ECC
    GET_DIMM_ECC
    beqz    a1, 1f
    nop
    slli.d    a1, a1, ECC_ENABLE_OFFSET
    or      a2, a2, a1
1:
#endif
    st.d      a2, t8, ECC_ENABLE_ADDR

    //reconfigure CS_1/2/3 addr info as CS_0
    ld.d      a2, t8, ADDR_INFO_CS_0_ADDR
    st.d      a2, t8, ADDR_INFO_CS_1_ADDR
    st.d      a2, t8, ADDR_INFO_CS_2_ADDR
    st.d      a2, t8, ADDR_INFO_CS_3_ADDR

#ifdef DEBUG_DDR_PARAM   //debug
//input once, change all byte lanes parameters.
    /* store the ra */
    or    t1, ra, zero

41:
    MM_PRINTSTR("\r\nChange parameters:\r\n0--skip;1--dll_clock;2--dll_rddqs_gate;3--dll_rddqs_p;4--dll_rddqs_n;5--dll_wrdqs;6--dll_wrdq;\r\n7--rd_oe_end/start-edge_stop/start;8--wr_dqs_oe_end/start-edge_stop/start;9--wr_dq_oe_end/start-edge_stop/start;a--wr_odt_oe_end/start-edge_stop/start;\r\nb--wrdq_clk_delay;c--rddata_delay;d--rddqs_lt_half;e--wrdqs_lt_half;f--wrdq_lt_half;\r\n");
    li.d     t6, 0x00
    bl     inputaddress
    nop
    beqz    a4, 90f;
    nop
    or    t5, a4, zero
    MM_PRINTSTR("\r\nPlease input the data-hex: ");
    li.d     t6, 0x00
    bl     inputaddress
    nop
    or    a2, t5, zero
    li.d     a1, 0xffffffff
    and     t5, a4, a1
/*****************
a2: change select
t5: value
*****************/

//!!!!!note: don't change the switch order of the code bellow, because we use
//add instr to change a1 instead of li.d instr to reduce code size.
    li.d     a1, 0x1
    beq     a2, a1, 1f;
    nop
    addi.d  a1, a1, 0x1
    beq     a2, a1, 2f;
    nop
    addi.d  a1, a1, 0x1
    beq     a2, a1, 3f;
    nop
    addi.d  a1, a1, 0x1
    beq     a2, a1, 4f;
    nop
    addi.d  a1, a1, 0x1
    beq     a2, a1, 5f;
    nop
    addi.d  a1, a1, 0x1
    beq     a2, a1, 6f;
    nop
    addi.d  a1, a1, 0x1
    beq     a2, a1, 7f;
    nop
    addi.d  a1, a1, 0x1
    beq     a2, a1, 8f;
    nop
    addi.d  a1, a1, 0x1
    beq     a2, a1, 9f;
    nop
    addi.d  a1, a1, 0x1
    beq     a2, a1, 10f;
    nop
    addi.d  a1, a1, 0x1
    beq     a2, a1, 11f;
    nop
    addi.d  a1, a1, 0x1
    beq     a2, a1, 12f;
    nop
    addi.d  a1, a1, 0x1
    beq     a2, a1, 13f;
    nop
    addi.d  a1, a1, 0x1
    beq     a2, a1, 14f;
    nop
    addi.d  a1, a1, 0x1
    beq     a2, a1, 15f;
    nop
    MM_PRINTSTR("\r\n--------Wrong selection: no parameter will be changed.");
    b       40f
    nop
1:
    andi     t5, t5, CLKLVL_DELAY_MASK

    ld.d      a1, t8, CLKLVL_DELAY_2_ADDR
    li.d     a2, CLKLVL_DELAY_MASK
    slli.d    a2, a2, CLKLVL_DELAY_2_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, CLKLVL_DELAY_2_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, CLKLVL_DELAY_2_ADDR

    ld.d      a1, t8, CLKLVL_DELAY_1_ADDR
    li.d     a2, CLKLVL_DELAY_MASK
    slli.d    a2, a2, CLKLVL_DELAY_1_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, CLKLVL_DELAY_1_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, CLKLVL_DELAY_1_ADDR

    ld.d      a1, t8, CLKLVL_DELAY_0_ADDR
    li.d     a2, CLKLVL_DELAY_MASK
    slli.d    a2, a2, CLKLVL_DELAY_0_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, CLKLVL_DELAY_0_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, CLKLVL_DELAY_0_ADDR
    b       40f
    nop
2:
    andi     t5, t5, RDLVL_GATE_DELAY_MASK

    ld.d      a1, t8, RDLVL_GATE_DELAY_8_ADDR
    li.d     a2, RDLVL_GATE_DELAY_MASK
    slli.d    a2, a2, RDLVL_GATE_DELAY_8_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_GATE_DELAY_8_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_GATE_DELAY_8_ADDR

    ld.d      a1, t8, RDLVL_GATE_DELAY_7_ADDR
    li.d     a2, RDLVL_GATE_DELAY_MASK
    slli.d    a2, a2, RDLVL_GATE_DELAY_7_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_GATE_DELAY_7_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_GATE_DELAY_7_ADDR

    ld.d      a1, t8, RDLVL_GATE_DELAY_6_ADDR
    li.d     a2, RDLVL_GATE_DELAY_MASK
    slli.d    a2, a2, RDLVL_GATE_DELAY_6_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_GATE_DELAY_6_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_GATE_DELAY_6_ADDR

    ld.d      a1, t8, RDLVL_GATE_DELAY_5_ADDR
    li.d     a2, RDLVL_GATE_DELAY_MASK
    slli.d    a2, a2, RDLVL_GATE_DELAY_5_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_GATE_DELAY_5_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_GATE_DELAY_5_ADDR

    ld.d      a1, t8, RDLVL_GATE_DELAY_4_ADDR
    li.d     a2, RDLVL_GATE_DELAY_MASK
    slli.d    a2, a2, RDLVL_GATE_DELAY_4_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_GATE_DELAY_4_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_GATE_DELAY_4_ADDR

    ld.d      a1, t8, RDLVL_GATE_DELAY_3_ADDR
    li.d     a2, RDLVL_GATE_DELAY_MASK
    slli.d    a2, a2, RDLVL_GATE_DELAY_3_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_GATE_DELAY_3_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_GATE_DELAY_3_ADDR

    ld.d      a1, t8, RDLVL_GATE_DELAY_2_ADDR
    li.d     a2, RDLVL_GATE_DELAY_MASK
    slli.d    a2, a2, RDLVL_GATE_DELAY_2_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_GATE_DELAY_2_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_GATE_DELAY_2_ADDR

    ld.d      a1, t8, RDLVL_GATE_DELAY_1_ADDR
    li.d     a2, RDLVL_GATE_DELAY_MASK
    slli.d    a2, a2, RDLVL_GATE_DELAY_1_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_GATE_DELAY_1_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_GATE_DELAY_1_ADDR

    ld.d      a1, t8, RDLVL_GATE_DELAY_0_ADDR
    li.d     a2, RDLVL_GATE_DELAY_MASK
    slli.d    a2, a2, RDLVL_GATE_DELAY_0_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_GATE_DELAY_0_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_GATE_DELAY_0_ADDR
    b       40f
    nop
3:
    andi     t5, t5, RDLVL_DELAY_MASK

    ld.d      a1, t8, RDLVL_DELAY_8_ADDR
    li.d     a2, RDLVL_DELAY_MASK
    slli.d    a2, a2, RDLVL_DELAY_8_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DELAY_8_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DELAY_8_ADDR

    ld.d      a1, t8, RDLVL_DELAY_7_ADDR
    li.d     a2, RDLVL_DELAY_MASK
    slli.d    a2, a2, RDLVL_DELAY_7_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DELAY_7_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DELAY_7_ADDR

    ld.d      a1, t8, RDLVL_DELAY_6_ADDR
    li.d     a2, RDLVL_DELAY_MASK
    slli.d    a2, a2, RDLVL_DELAY_6_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DELAY_6_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DELAY_6_ADDR

    ld.d      a1, t8, RDLVL_DELAY_5_ADDR
    li.d     a2, RDLVL_DELAY_MASK
    slli.d    a2, a2, RDLVL_DELAY_5_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DELAY_5_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DELAY_5_ADDR

    ld.d      a1, t8, RDLVL_DELAY_4_ADDR
    li.d     a2, RDLVL_DELAY_MASK
    slli.d    a2, a2, RDLVL_DELAY_4_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DELAY_4_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DELAY_4_ADDR

    ld.d      a1, t8, RDLVL_DELAY_3_ADDR
    li.d     a2, RDLVL_DELAY_MASK
    slli.d    a2, a2, RDLVL_DELAY_3_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DELAY_3_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DELAY_3_ADDR

    ld.d      a1, t8, RDLVL_DELAY_2_ADDR
    li.d     a2, RDLVL_DELAY_MASK
    slli.d    a2, a2, RDLVL_DELAY_2_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DELAY_2_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DELAY_2_ADDR

    ld.d      a1, t8, RDLVL_DELAY_1_ADDR
    li.d     a2, RDLVL_DELAY_MASK
    slli.d    a2, a2, RDLVL_DELAY_1_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DELAY_1_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DELAY_1_ADDR

    ld.d      a1, t8, RDLVL_DELAY_0_ADDR
    li.d     a2, RDLVL_DELAY_MASK
    slli.d    a2, a2, RDLVL_DELAY_0_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DELAY_0_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DELAY_0_ADDR
    b       40f
    nop
4:
    andi     t5, t5, RDLVL_DQSN_DELAY_MASK

    ld.d      a1, t8, RDLVL_DQSN_DELAY_8_ADDR
    li.d     a2, RDLVL_DQSN_DELAY_MASK
    slli.d    a2, a2, RDLVL_DQSN_DELAY_8_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DQSN_DELAY_8_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DQSN_DELAY_8_ADDR

    ld.d      a1, t8, RDLVL_DQSN_DELAY_7_ADDR
    li.d     a2, RDLVL_DQSN_DELAY_MASK
    slli.d    a2, a2, RDLVL_DQSN_DELAY_7_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DQSN_DELAY_7_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DQSN_DELAY_7_ADDR

    ld.d      a1, t8, RDLVL_DQSN_DELAY_6_ADDR
    li.d     a2, RDLVL_DQSN_DELAY_MASK
    slli.d    a2, a2, RDLVL_DQSN_DELAY_6_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DQSN_DELAY_6_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DQSN_DELAY_6_ADDR

    ld.d      a1, t8, RDLVL_DQSN_DELAY_5_ADDR
    li.d     a2, RDLVL_DQSN_DELAY_MASK
    slli.d    a2, a2, RDLVL_DQSN_DELAY_5_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DQSN_DELAY_5_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DQSN_DELAY_5_ADDR

    ld.d      a1, t8, RDLVL_DQSN_DELAY_4_ADDR
    li.d     a2, RDLVL_DQSN_DELAY_MASK
    slli.d    a2, a2, RDLVL_DQSN_DELAY_4_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DQSN_DELAY_4_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DQSN_DELAY_4_ADDR

    ld.d      a1, t8, RDLVL_DQSN_DELAY_3_ADDR
    li.d     a2, RDLVL_DQSN_DELAY_MASK
    slli.d    a2, a2, RDLVL_DQSN_DELAY_3_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DQSN_DELAY_3_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DQSN_DELAY_3_ADDR

    ld.d      a1, t8, RDLVL_DQSN_DELAY_2_ADDR
    li.d     a2, RDLVL_DQSN_DELAY_MASK
    slli.d    a2, a2, RDLVL_DQSN_DELAY_2_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DQSN_DELAY_2_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DQSN_DELAY_2_ADDR

    ld.d      a1, t8, RDLVL_DQSN_DELAY_1_ADDR
    li.d     a2, RDLVL_DQSN_DELAY_MASK
    slli.d    a2, a2, RDLVL_DQSN_DELAY_1_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DQSN_DELAY_1_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DQSN_DELAY_1_ADDR

    ld.d      a1, t8, RDLVL_DQSN_DELAY_0_ADDR
    li.d     a2, RDLVL_DQSN_DELAY_MASK
    slli.d    a2, a2, RDLVL_DQSN_DELAY_0_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDLVL_DQSN_DELAY_0_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDLVL_DQSN_DELAY_0_ADDR
    b       40f
    nop
5:
    andi     t5, t5, WRLVL_DELAY_MASK

    ld.d      a1, t8, WRLVL_DELAY_8_ADDR
    li.d     a2, WRLVL_DELAY_MASK
    slli.d    a2, a2, WRLVL_DELAY_8_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DELAY_8_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DELAY_8_ADDR

    ld.d      a1, t8, WRLVL_DELAY_7_ADDR
    li.d     a2, WRLVL_DELAY_MASK
    slli.d    a2, a2, WRLVL_DELAY_7_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DELAY_7_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DELAY_7_ADDR

    ld.d      a1, t8, WRLVL_DELAY_6_ADDR
    li.d     a2, WRLVL_DELAY_MASK
    slli.d    a2, a2, WRLVL_DELAY_6_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DELAY_6_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DELAY_6_ADDR

    ld.d      a1, t8, WRLVL_DELAY_5_ADDR
    li.d     a2, WRLVL_DELAY_MASK
    slli.d    a2, a2, WRLVL_DELAY_5_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DELAY_5_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DELAY_5_ADDR

    ld.d      a1, t8, WRLVL_DELAY_4_ADDR
    li.d     a2, WRLVL_DELAY_MASK
    slli.d    a2, a2, WRLVL_DELAY_4_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DELAY_4_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DELAY_4_ADDR

    ld.d      a1, t8, WRLVL_DELAY_3_ADDR
    li.d     a2, WRLVL_DELAY_MASK
    slli.d    a2, a2, WRLVL_DELAY_3_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DELAY_3_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DELAY_3_ADDR

    ld.d      a1, t8, WRLVL_DELAY_2_ADDR
    li.d     a2, WRLVL_DELAY_MASK
    slli.d    a2, a2, WRLVL_DELAY_2_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DELAY_2_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DELAY_2_ADDR

    ld.d      a1, t8, WRLVL_DELAY_1_ADDR
    li.d     a2, WRLVL_DELAY_MASK
    slli.d    a2, a2, WRLVL_DELAY_1_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DELAY_1_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DELAY_1_ADDR

    ld.d      a1, t8, WRLVL_DELAY_0_ADDR
    li.d     a2, WRLVL_DELAY_MASK
    slli.d    a2, a2, WRLVL_DELAY_0_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DELAY_0_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DELAY_0_ADDR
    b       40f
    nop
6:
    andi     t5, t5, WRLVL_DQ_DELAY_MASK

    ld.d      a1, t8, WRLVL_DQ_DELAY_8_ADDR
    li.d     a2, WRLVL_DQ_DELAY_MASK
    slli.d    a2, a2, WRLVL_DQ_DELAY_8_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DQ_DELAY_8_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DQ_DELAY_8_ADDR

    ld.d      a1, t8, WRLVL_DQ_DELAY_7_ADDR
    li.d     a2, WRLVL_DQ_DELAY_MASK
    slli.d    a2, a2, WRLVL_DQ_DELAY_7_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DQ_DELAY_7_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DQ_DELAY_7_ADDR

    ld.d      a1, t8, WRLVL_DQ_DELAY_6_ADDR
    li.d     a2, WRLVL_DQ_DELAY_MASK
    slli.d    a2, a2, WRLVL_DQ_DELAY_6_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DQ_DELAY_6_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DQ_DELAY_6_ADDR

    ld.d      a1, t8, WRLVL_DQ_DELAY_5_ADDR
    li.d     a2, WRLVL_DQ_DELAY_MASK
    slli.d    a2, a2, WRLVL_DQ_DELAY_5_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DQ_DELAY_5_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DQ_DELAY_5_ADDR

    ld.d      a1, t8, WRLVL_DQ_DELAY_4_ADDR
    li.d     a2, WRLVL_DQ_DELAY_MASK
    slli.d    a2, a2, WRLVL_DQ_DELAY_4_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DQ_DELAY_4_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DQ_DELAY_4_ADDR

    ld.d      a1, t8, WRLVL_DQ_DELAY_3_ADDR
    li.d     a2, WRLVL_DQ_DELAY_MASK
    slli.d    a2, a2, WRLVL_DQ_DELAY_3_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DQ_DELAY_3_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DQ_DELAY_3_ADDR

    ld.d      a1, t8, WRLVL_DQ_DELAY_2_ADDR
    li.d     a2, WRLVL_DQ_DELAY_MASK
    slli.d    a2, a2, WRLVL_DQ_DELAY_2_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DQ_DELAY_2_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DQ_DELAY_2_ADDR

    ld.d      a1, t8, WRLVL_DQ_DELAY_1_ADDR
    li.d     a2, WRLVL_DQ_DELAY_MASK
    slli.d    a2, a2, WRLVL_DQ_DELAY_1_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DQ_DELAY_1_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DQ_DELAY_1_ADDR

    ld.d      a1, t8, WRLVL_DQ_DELAY_0_ADDR
    li.d     a2, WRLVL_DQ_DELAY_MASK
    slli.d    a2, a2, WRLVL_DQ_DELAY_0_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRLVL_DQ_DELAY_0_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRLVL_DQ_DELAY_0_ADDR
    b       40f
    nop
7:
    li.d tp, RD_OE_EDGE_MASK; and     t5, t5, tp

    ld.d      a1, t8, RD_OE_EDGE_8_ADDR
    li.d     a2, RD_OE_EDGE_MASK
    slli.d    a2, a2, RD_OE_EDGE_8_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RD_OE_EDGE_8_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RD_OE_EDGE_8_ADDR

    ld.d      a1, t8, RD_OE_EDGE_7_ADDR
    li.d     a2, RD_OE_EDGE_MASK
    slli.d    a2, a2, RD_OE_EDGE_7_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RD_OE_EDGE_7_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RD_OE_EDGE_7_ADDR

    ld.d      a1, t8, RD_OE_EDGE_6_ADDR
    li.d     a2, RD_OE_EDGE_MASK
    slli.d    a2, a2, RD_OE_EDGE_6_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RD_OE_EDGE_6_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RD_OE_EDGE_6_ADDR

    ld.d      a1, t8, RD_OE_EDGE_5_ADDR
    li.d     a2, RD_OE_EDGE_MASK
    slli.d    a2, a2, RD_OE_EDGE_5_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RD_OE_EDGE_5_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RD_OE_EDGE_5_ADDR

    ld.d      a1, t8, RD_OE_EDGE_4_ADDR
    li.d     a2, RD_OE_EDGE_MASK
    slli.d    a2, a2, RD_OE_EDGE_4_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RD_OE_EDGE_4_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RD_OE_EDGE_4_ADDR

    ld.d      a1, t8, RD_OE_EDGE_3_ADDR
    li.d     a2, RD_OE_EDGE_MASK
    slli.d    a2, a2, RD_OE_EDGE_3_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RD_OE_EDGE_3_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RD_OE_EDGE_3_ADDR

    ld.d      a1, t8, RD_OE_EDGE_2_ADDR
    li.d     a2, RD_OE_EDGE_MASK
    slli.d    a2, a2, RD_OE_EDGE_2_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RD_OE_EDGE_2_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RD_OE_EDGE_2_ADDR

    ld.d      a1, t8, RD_OE_EDGE_1_ADDR
    li.d     a2, RD_OE_EDGE_MASK
    slli.d    a2, a2, RD_OE_EDGE_1_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RD_OE_EDGE_1_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RD_OE_EDGE_1_ADDR

    ld.d      a1, t8, RD_OE_EDGE_0_ADDR
    li.d     a2, RD_OE_EDGE_MASK
    slli.d    a2, a2, RD_OE_EDGE_0_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RD_OE_EDGE_0_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RD_OE_EDGE_0_ADDR
    b       40f
    nop
8:
    li.d tp, WR_DQS_OE_EDGE_MASK; and     t5, t5, tp

    ld.d      a1, t8, WR_DQS_OE_EDGE_8_ADDR
    li.d     a2, WR_DQS_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQS_OE_EDGE_8_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQS_OE_EDGE_8_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQS_OE_EDGE_8_ADDR

    ld.d      a1, t8, WR_DQS_OE_EDGE_7_ADDR
    li.d     a2, WR_DQS_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQS_OE_EDGE_7_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQS_OE_EDGE_7_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQS_OE_EDGE_7_ADDR

    ld.d      a1, t8, WR_DQS_OE_EDGE_6_ADDR
    li.d     a2, WR_DQS_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQS_OE_EDGE_6_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQS_OE_EDGE_6_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQS_OE_EDGE_6_ADDR

    ld.d      a1, t8, WR_DQS_OE_EDGE_5_ADDR
    li.d     a2, WR_DQS_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQS_OE_EDGE_5_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQS_OE_EDGE_5_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQS_OE_EDGE_5_ADDR

    ld.d      a1, t8, WR_DQS_OE_EDGE_4_ADDR
    li.d     a2, WR_DQS_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQS_OE_EDGE_4_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQS_OE_EDGE_4_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQS_OE_EDGE_4_ADDR

    ld.d      a1, t8, WR_DQS_OE_EDGE_3_ADDR
    li.d     a2, WR_DQS_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQS_OE_EDGE_3_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQS_OE_EDGE_3_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQS_OE_EDGE_3_ADDR

    ld.d      a1, t8, WR_DQS_OE_EDGE_2_ADDR
    li.d     a2, WR_DQS_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQS_OE_EDGE_2_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQS_OE_EDGE_2_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQS_OE_EDGE_2_ADDR

    ld.d      a1, t8, WR_DQS_OE_EDGE_1_ADDR
    li.d     a2, WR_DQS_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQS_OE_EDGE_1_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQS_OE_EDGE_1_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQS_OE_EDGE_1_ADDR

    ld.d      a1, t8, WR_DQS_OE_EDGE_0_ADDR
    li.d     a2, WR_DQS_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQS_OE_EDGE_0_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQS_OE_EDGE_0_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQS_OE_EDGE_0_ADDR
    b       40f
    nop
9:
    li.d tp, WR_DQ_OE_EDGE_MASK; and     t5, t5, tp

    ld.d      a1, t8, WR_DQ_OE_EDGE_8_ADDR
    li.d     a2, WR_DQ_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQ_OE_EDGE_8_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQ_OE_EDGE_8_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQ_OE_EDGE_8_ADDR

    ld.d      a1, t8, WR_DQ_OE_EDGE_7_ADDR
    li.d     a2, WR_DQ_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQ_OE_EDGE_7_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQ_OE_EDGE_7_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQ_OE_EDGE_7_ADDR

    ld.d      a1, t8, WR_DQ_OE_EDGE_6_ADDR
    li.d     a2, WR_DQ_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQ_OE_EDGE_6_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQ_OE_EDGE_6_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQ_OE_EDGE_6_ADDR

    ld.d      a1, t8, WR_DQ_OE_EDGE_5_ADDR
    li.d     a2, WR_DQ_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQ_OE_EDGE_5_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQ_OE_EDGE_5_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQ_OE_EDGE_5_ADDR

    ld.d      a1, t8, WR_DQ_OE_EDGE_4_ADDR
    li.d     a2, WR_DQ_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQ_OE_EDGE_4_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQ_OE_EDGE_4_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQ_OE_EDGE_4_ADDR

    ld.d      a1, t8, WR_DQ_OE_EDGE_3_ADDR
    li.d     a2, WR_DQ_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQ_OE_EDGE_3_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQ_OE_EDGE_3_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQ_OE_EDGE_3_ADDR

    ld.d      a1, t8, WR_DQ_OE_EDGE_2_ADDR
    li.d     a2, WR_DQ_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQ_OE_EDGE_2_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQ_OE_EDGE_2_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQ_OE_EDGE_2_ADDR

    ld.d      a1, t8, WR_DQ_OE_EDGE_1_ADDR
    li.d     a2, WR_DQ_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQ_OE_EDGE_1_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQ_OE_EDGE_1_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQ_OE_EDGE_1_ADDR

    ld.d      a1, t8, WR_DQ_OE_EDGE_0_ADDR
    li.d     a2, WR_DQ_OE_EDGE_MASK
    slli.d    a2, a2, WR_DQ_OE_EDGE_0_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_DQ_OE_EDGE_0_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_DQ_OE_EDGE_0_ADDR
    b       40f
    nop
10:
    li.d tp, WR_ODT_OE_EDGE_MASK; and     t5, t5, tp

    ld.d      a1, t8, WR_ODT_OE_EDGE_8_ADDR
    li.d     a2, WR_ODT_OE_EDGE_MASK
    slli.d    a2, a2, WR_ODT_OE_EDGE_8_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_ODT_OE_EDGE_8_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_ODT_OE_EDGE_8_ADDR

    ld.d      a1, t8, WR_ODT_OE_EDGE_7_ADDR
    li.d     a2, WR_ODT_OE_EDGE_MASK
    slli.d    a2, a2, WR_ODT_OE_EDGE_7_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_ODT_OE_EDGE_7_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_ODT_OE_EDGE_7_ADDR

    ld.d      a1, t8, WR_ODT_OE_EDGE_6_ADDR
    li.d     a2, WR_ODT_OE_EDGE_MASK
    slli.d    a2, a2, WR_ODT_OE_EDGE_6_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_ODT_OE_EDGE_6_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_ODT_OE_EDGE_6_ADDR

    ld.d      a1, t8, WR_ODT_OE_EDGE_5_ADDR
    li.d     a2, WR_ODT_OE_EDGE_MASK
    slli.d    a2, a2, WR_ODT_OE_EDGE_5_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_ODT_OE_EDGE_5_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_ODT_OE_EDGE_5_ADDR

    ld.d      a1, t8, WR_ODT_OE_EDGE_4_ADDR
    li.d     a2, WR_ODT_OE_EDGE_MASK
    slli.d    a2, a2, WR_ODT_OE_EDGE_4_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_ODT_OE_EDGE_4_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_ODT_OE_EDGE_4_ADDR

    ld.d      a1, t8, WR_ODT_OE_EDGE_3_ADDR
    li.d     a2, WR_ODT_OE_EDGE_MASK
    slli.d    a2, a2, WR_ODT_OE_EDGE_3_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_ODT_OE_EDGE_3_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_ODT_OE_EDGE_3_ADDR

    ld.d      a1, t8, WR_ODT_OE_EDGE_2_ADDR
    li.d     a2, WR_ODT_OE_EDGE_MASK
    slli.d    a2, a2, WR_ODT_OE_EDGE_2_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_ODT_OE_EDGE_2_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_ODT_OE_EDGE_2_ADDR

    ld.d      a1, t8, WR_ODT_OE_EDGE_1_ADDR
    li.d     a2, WR_ODT_OE_EDGE_MASK
    slli.d    a2, a2, WR_ODT_OE_EDGE_1_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_ODT_OE_EDGE_1_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_ODT_OE_EDGE_1_ADDR

    ld.d      a1, t8, WR_ODT_OE_EDGE_0_ADDR
    li.d     a2, WR_ODT_OE_EDGE_MASK
    slli.d    a2, a2, WR_ODT_OE_EDGE_0_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WR_ODT_OE_EDGE_0_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WR_ODT_OE_EDGE_0_ADDR
    b       40f
    nop
11:
    andi     t5, t5, WRDQ_CLK_DELAY_MASK

    ld.d      a1, t8, WRDQ_CLK_DELAY_8_ADDR
    li.d     a2, WRDQ_CLK_DELAY_MASK
    slli.d    a2, a2, WRDQ_CLK_DELAY_8_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_CLK_DELAY_8_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_CLK_DELAY_8_ADDR

    ld.d      a1, t8, WRDQ_CLK_DELAY_7_ADDR
    li.d     a2, WRDQ_CLK_DELAY_MASK
    slli.d    a2, a2, WRDQ_CLK_DELAY_7_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_CLK_DELAY_7_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_CLK_DELAY_7_ADDR

    ld.d      a1, t8, WRDQ_CLK_DELAY_6_ADDR
    li.d     a2, WRDQ_CLK_DELAY_MASK
    slli.d    a2, a2, WRDQ_CLK_DELAY_6_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_CLK_DELAY_6_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_CLK_DELAY_6_ADDR

    ld.d      a1, t8, WRDQ_CLK_DELAY_5_ADDR
    li.d     a2, WRDQ_CLK_DELAY_MASK
    slli.d    a2, a2, WRDQ_CLK_DELAY_5_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_CLK_DELAY_5_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_CLK_DELAY_5_ADDR

    ld.d      a1, t8, WRDQ_CLK_DELAY_4_ADDR
    li.d     a2, WRDQ_CLK_DELAY_MASK
    slli.d    a2, a2, WRDQ_CLK_DELAY_4_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_CLK_DELAY_4_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_CLK_DELAY_4_ADDR

    ld.d      a1, t8, WRDQ_CLK_DELAY_3_ADDR
    li.d     a2, WRDQ_CLK_DELAY_MASK
    slli.d    a2, a2, WRDQ_CLK_DELAY_3_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_CLK_DELAY_3_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_CLK_DELAY_3_ADDR

    ld.d      a1, t8, WRDQ_CLK_DELAY_2_ADDR
    li.d     a2, WRDQ_CLK_DELAY_MASK
    slli.d    a2, a2, WRDQ_CLK_DELAY_2_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_CLK_DELAY_2_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_CLK_DELAY_2_ADDR

    ld.d      a1, t8, WRDQ_CLK_DELAY_1_ADDR
    li.d     a2, WRDQ_CLK_DELAY_MASK
    slli.d    a2, a2, WRDQ_CLK_DELAY_1_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_CLK_DELAY_1_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_CLK_DELAY_1_ADDR

    ld.d      a1, t8, WRDQ_CLK_DELAY_0_ADDR
    li.d     a2, WRDQ_CLK_DELAY_MASK
    slli.d    a2, a2, WRDQ_CLK_DELAY_0_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_CLK_DELAY_0_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_CLK_DELAY_0_ADDR
    b       40f
    nop
12:
    andi     t5, t5, RDDATA_DELAY_MASK

    ld.d      a1, t8, RDDATA_DELAY_8_ADDR
    li.d     a2, RDDATA_DELAY_MASK
    slli.d    a2, a2, RDDATA_DELAY_8_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDATA_DELAY_8_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDATA_DELAY_8_ADDR

    ld.d      a1, t8, RDDATA_DELAY_7_ADDR
    li.d     a2, RDDATA_DELAY_MASK
    slli.d    a2, a2, RDDATA_DELAY_7_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDATA_DELAY_7_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDATA_DELAY_7_ADDR

    ld.d      a1, t8, RDDATA_DELAY_6_ADDR
    li.d     a2, RDDATA_DELAY_MASK
    slli.d    a2, a2, RDDATA_DELAY_6_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDATA_DELAY_6_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDATA_DELAY_6_ADDR

    ld.d      a1, t8, RDDATA_DELAY_5_ADDR
    li.d     a2, RDDATA_DELAY_MASK
    slli.d    a2, a2, RDDATA_DELAY_5_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDATA_DELAY_5_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDATA_DELAY_5_ADDR

    ld.d      a1, t8, RDDATA_DELAY_4_ADDR
    li.d     a2, RDDATA_DELAY_MASK
    slli.d    a2, a2, RDDATA_DELAY_4_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDATA_DELAY_4_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDATA_DELAY_4_ADDR

    ld.d      a1, t8, RDDATA_DELAY_3_ADDR
    li.d     a2, RDDATA_DELAY_MASK
    slli.d    a2, a2, RDDATA_DELAY_3_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDATA_DELAY_3_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDATA_DELAY_3_ADDR

    ld.d      a1, t8, RDDATA_DELAY_2_ADDR
    li.d     a2, RDDATA_DELAY_MASK
    slli.d    a2, a2, RDDATA_DELAY_2_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDATA_DELAY_2_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDATA_DELAY_2_ADDR

    ld.d      a1, t8, RDDATA_DELAY_1_ADDR
    li.d     a2, RDDATA_DELAY_MASK
    slli.d    a2, a2, RDDATA_DELAY_1_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDATA_DELAY_1_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDATA_DELAY_1_ADDR

    ld.d      a1, t8, RDDATA_DELAY_0_ADDR
    li.d     a2, RDDATA_DELAY_MASK
    slli.d    a2, a2, RDDATA_DELAY_0_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDATA_DELAY_0_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDATA_DELAY_0_ADDR
    b       40f
    nop
13:
    andi     t5, t5, RDDQS_LT_HALF_MASK

    ld.d      a1, t8, RDDQS_LT_HALF_8_ADDR
    li.d     a2, RDDQS_LT_HALF_MASK
    slli.d    a2, a2, RDDQS_LT_HALF_8_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDQS_LT_HALF_8_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDQS_LT_HALF_8_ADDR

    ld.d      a1, t8, RDDQS_LT_HALF_7_ADDR
    li.d     a2, RDDQS_LT_HALF_MASK
    slli.d    a2, a2, RDDQS_LT_HALF_7_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDQS_LT_HALF_7_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDQS_LT_HALF_7_ADDR

    ld.d      a1, t8, RDDQS_LT_HALF_6_ADDR
    li.d     a2, RDDQS_LT_HALF_MASK
    slli.d    a2, a2, RDDQS_LT_HALF_6_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDQS_LT_HALF_6_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDQS_LT_HALF_6_ADDR

    ld.d      a1, t8, RDDQS_LT_HALF_5_ADDR
    li.d     a2, RDDQS_LT_HALF_MASK
    slli.d    a2, a2, RDDQS_LT_HALF_5_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDQS_LT_HALF_5_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDQS_LT_HALF_5_ADDR

    ld.d      a1, t8, RDDQS_LT_HALF_4_ADDR
    li.d     a2, RDDQS_LT_HALF_MASK
    slli.d    a2, a2, RDDQS_LT_HALF_4_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDQS_LT_HALF_4_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDQS_LT_HALF_4_ADDR

    ld.d      a1, t8, RDDQS_LT_HALF_3_ADDR
    li.d     a2, RDDQS_LT_HALF_MASK
    slli.d    a2, a2, RDDQS_LT_HALF_3_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDQS_LT_HALF_3_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDQS_LT_HALF_3_ADDR

    ld.d      a1, t8, RDDQS_LT_HALF_2_ADDR
    li.d     a2, RDDQS_LT_HALF_MASK
    slli.d    a2, a2, RDDQS_LT_HALF_2_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDQS_LT_HALF_2_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDQS_LT_HALF_2_ADDR

    ld.d      a1, t8, RDDQS_LT_HALF_1_ADDR
    li.d     a2, RDDQS_LT_HALF_MASK
    slli.d    a2, a2, RDDQS_LT_HALF_1_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDQS_LT_HALF_1_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDQS_LT_HALF_1_ADDR

    ld.d      a1, t8, RDDQS_LT_HALF_0_ADDR
    li.d     a2, RDDQS_LT_HALF_MASK
    slli.d    a2, a2, RDDQS_LT_HALF_0_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, RDDQS_LT_HALF_0_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, RDDQS_LT_HALF_0_ADDR
    b       40f
    nop
14:
    andi     t5, t5, WRDQS_LT_HALF_MASK

    ld.d      a1, t8, WRDQS_LT_HALF_8_ADDR
    li.d     a2, WRDQS_LT_HALF_MASK
    slli.d    a2, a2, WRDQS_LT_HALF_8_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQS_LT_HALF_8_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQS_LT_HALF_8_ADDR

    ld.d      a1, t8, WRDQS_LT_HALF_7_ADDR
    li.d     a2, WRDQS_LT_HALF_MASK
    slli.d    a2, a2, WRDQS_LT_HALF_7_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQS_LT_HALF_7_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQS_LT_HALF_7_ADDR

    ld.d      a1, t8, WRDQS_LT_HALF_6_ADDR
    li.d     a2, WRDQS_LT_HALF_MASK
    slli.d    a2, a2, WRDQS_LT_HALF_6_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQS_LT_HALF_6_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQS_LT_HALF_6_ADDR

    ld.d      a1, t8, WRDQS_LT_HALF_5_ADDR
    li.d     a2, WRDQS_LT_HALF_MASK
    slli.d    a2, a2, WRDQS_LT_HALF_5_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQS_LT_HALF_5_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQS_LT_HALF_5_ADDR

    ld.d      a1, t8, WRDQS_LT_HALF_4_ADDR
    li.d     a2, WRDQS_LT_HALF_MASK
    slli.d    a2, a2, WRDQS_LT_HALF_4_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQS_LT_HALF_4_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQS_LT_HALF_4_ADDR

    ld.d      a1, t8, WRDQS_LT_HALF_3_ADDR
    li.d     a2, WRDQS_LT_HALF_MASK
    slli.d    a2, a2, WRDQS_LT_HALF_3_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQS_LT_HALF_3_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQS_LT_HALF_3_ADDR

    ld.d      a1, t8, WRDQS_LT_HALF_2_ADDR
    li.d     a2, WRDQS_LT_HALF_MASK
    slli.d    a2, a2, WRDQS_LT_HALF_2_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQS_LT_HALF_2_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQS_LT_HALF_2_ADDR

    ld.d      a1, t8, WRDQS_LT_HALF_1_ADDR
    li.d     a2, WRDQS_LT_HALF_MASK
    slli.d    a2, a2, WRDQS_LT_HALF_1_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQS_LT_HALF_1_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQS_LT_HALF_1_ADDR

    ld.d      a1, t8, WRDQS_LT_HALF_0_ADDR
    li.d     a2, WRDQS_LT_HALF_MASK
    slli.d    a2, a2, WRDQS_LT_HALF_0_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQS_LT_HALF_0_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQS_LT_HALF_0_ADDR
    b       40f
    nop
15:
    andi     t5, t5, WRDQ_LT_HALF_MASK

    ld.d      a1, t8, WRDQ_LT_HALF_8_ADDR
    li.d     a2, WRDQ_LT_HALF_MASK
    slli.d    a2, a2, WRDQ_LT_HALF_8_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_LT_HALF_8_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_LT_HALF_8_ADDR

    ld.d      a1, t8, WRDQ_LT_HALF_7_ADDR
    li.d     a2, WRDQ_LT_HALF_MASK
    slli.d    a2, a2, WRDQ_LT_HALF_7_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_LT_HALF_7_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_LT_HALF_7_ADDR

    ld.d      a1, t8, WRDQ_LT_HALF_6_ADDR
    li.d     a2, WRDQ_LT_HALF_MASK
    slli.d    a2, a2, WRDQ_LT_HALF_6_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_LT_HALF_6_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_LT_HALF_6_ADDR

    ld.d      a1, t8, WRDQ_LT_HALF_5_ADDR
    li.d     a2, WRDQ_LT_HALF_MASK
    slli.d    a2, a2, WRDQ_LT_HALF_5_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_LT_HALF_5_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_LT_HALF_5_ADDR

    ld.d      a1, t8, WRDQ_LT_HALF_4_ADDR
    li.d     a2, WRDQ_LT_HALF_MASK
    slli.d    a2, a2, WRDQ_LT_HALF_4_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_LT_HALF_4_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_LT_HALF_4_ADDR

    ld.d      a1, t8, WRDQ_LT_HALF_3_ADDR
    li.d     a2, WRDQ_LT_HALF_MASK
    slli.d    a2, a2, WRDQ_LT_HALF_3_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_LT_HALF_3_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_LT_HALF_3_ADDR

    ld.d      a1, t8, WRDQ_LT_HALF_2_ADDR
    li.d     a2, WRDQ_LT_HALF_MASK
    slli.d    a2, a2, WRDQ_LT_HALF_2_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_LT_HALF_2_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_LT_HALF_2_ADDR

    ld.d      a1, t8, WRDQ_LT_HALF_1_ADDR
    li.d     a2, WRDQ_LT_HALF_MASK
    slli.d    a2, a2, WRDQ_LT_HALF_1_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_LT_HALF_1_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_LT_HALF_1_ADDR

    ld.d      a1, t8, WRDQ_LT_HALF_0_ADDR
    li.d     a2, WRDQ_LT_HALF_MASK
    slli.d    a2, a2, WRDQ_LT_HALF_0_OFFSET
    nor     a2, a2, zero
    and     a1, a1, a2
    slli.d    a2, t5, WRDQ_LT_HALF_0_OFFSET
    or      a1, a1, a2
    st.d      a1, t8, WRDQ_LT_HALF_0_ADDR
    b       40f
    nop
40:
    dbar 0
    b        41b
    nop

90:

    MM_PRINTSTR("\r\nChange some parameters of MC:");
1:
    MM_PRINTSTR("\r\nPlease input the register number you want to change!!!(0xfff:jump out.): ");
    li.d     t6, 0x00
    bl     inputaddress
    nop
    or    t5, a4, zero

    li.d     a1, DDR_PARAM_NUM
    slli.d    a1, a1, 3
    bge     t5, a1, 2f    #if input address offset exceed range,jump out
    nop
    andi     t5, t5, 0xff8
    add.d   t5, t5, t8

    MM_PRINTSTR("\r\nPlease input the data-hex: ");
    li.d     t6, 0x00
    bl     inputaddress
    nop
    st.d      a4, t5, 0x0    #a4 is the input value

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

    b       1b
    nop
2:
    /* recover the ra */
    or    ra, t1, zero
#endif
    dbar 0

    ############start##########
    /***** set start to 1,start to initialize SDRAM *****/
    addi.d  a4, t8, START_ADDR
    li.d     a2, 0x1
    slli.d    a2, a2, START_OFFSET
    ld.d      a1, a4, 0x0
    or      a1, a1, a2
    st.d      a1, a4, 0x0
    dbar 0

wait_dram_init:
    //wait initialization complete
    //delay
    li.d     a4, 0x100
1:
    addi.d   a4, a4, -1
    bnez    a4, 1b
    nop

#if 1
    /* store the ra */
    or    t1, ra, zero

    MM_PRINTSTR("run to wait dram init ok!3\r\n")

    /* recover the ra */
    or    ra, t1, zero
#endif

    addi.d  a4, t8, DRAM_INIT_ADDR
    GET_MC_CS_MAP
1:
    ld.d      a2, a4, 0x0
    srli.d    a2, a2, DRAM_INIT_OFFSET
    and     a2, a2, a1
    //bne     a1, a2, 1b
    bne     a1, a2, wait_dram_init
    nop

ddr2_config_end:
    jirl    zero, ra, 0
    nop
