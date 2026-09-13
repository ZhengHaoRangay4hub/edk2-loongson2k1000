/************************************
    Function:   Access Result Based Software leveling
    Author: Chen Xinke
    v3.2    write level trys all possible Read setting(pop delay * gate cfg), and one success
            means this value is ok, write level all byte slice at the same time.
    v3.1    Write level in byte slice order, and when the two read fit(not necessarily means
            there is no read error!), the write result is recorded.
    v3.0    Rewrite the training method
    v2.0    Multi Node support
    a5.x    Single Node mode
    a5.1    Raw code for LS3A3
    a4.2    used for test

note: don't use s0, because it will be use at some subroutine

change register: a0,a1,a2,a4,a5, a6

register usage:
s3: Level sequence pointer(slice select).
s4: rd pop delay control(local loop control).
s5: Leveled byte mask.
t0: RST store bit pointer during TM process;
    RST parse pointer during result process.
t1: stage globl variable, also used by modify_param functions.
t2: currently used delay value.
t3, t4: variables
t5: delay value interval.
t6: param to Modify_param (object select).
t7: volatile value
t8: ARB_STORE_BASE
a6: save ra; (local used by wrlvl/rdlvl)
a4, a5: return value of arb_test_mem.
algrithm:

***************************************/
/********************************
********************************/
#include "ARB_level.h"

//#define DEBUG_ARB_LEVEL_WR
//#define DEBUG_ARB_LEVEL_WR_TM
//#define DEBUG_ARB_LEVEL_WR_CFG
//#define DEBUG_ARB_LEVEL_RD
//#define DEBUG_ARB_LEVEL_RD_TM
//#define DEBUG_ARB_LEVEL_RD_CFG

//#define CLOCK_LEVEL

//#define USE_WRLVL_CLK_OFFSET_VALUE

//#define ARB_SKIP_WRLVL
#define ADJUST_CPU_ODT  //work ok
#define ADD_DELAY_AFTER_RESET_PHY   //not need any more ?

//Don't change
#define MODIFY_PAD_COMP
#define CONTROL_L2XBAR_DDR_WINDOW  //work ok
#define USE_BIG_GF_POP_DELAY  //work ok
#define ARBLVL_PUT_DRAM_SREF
#ifdef  LS2HMC
//#define CLEAR_HALF_CLK_SHIFT    //for 2H3~1 don't define it
//#define USE_DEFAULT_RDLVL_DELAY
#else
#define CLEAR_HALF_CLK_SHIFT    //necessary
//#define USE_DEFAULT_RDLVL_DELAY
#endif

//#define ALIGN_GATE_DELAY  //obsolete because we use new method

ARB_level:
    or    a6, ra, zero
ARB_start:
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nNODE ID:");
    GET_ARB_LEVEL_NODE_ID
    or    a0, a1, zero
    bl     mm_hexserial
    nop
#endif

/*
 *Lock Scache 9800?01000000000 ~ 9800?01000001000(4K)
 */
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nLock Scache Node x--9800?01000000000~4K...\r\n")
#endif
    li.d     a2, LOCK_SCACHE_CONFIG_BASE_ADDR
#ifdef LS3B
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 14
    add.d   a2, a2, a1
#endif
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    or      a2, a2, a1
    li.d     a3, 0x0000fffffffff000  //set Mask first
    st.d      a3, a2, 0x40
    li.d     a3, 0x8000001000000000
    or      a3, a3, a1
    st.d      a3, a2, 0x0
#ifdef  PRINT_MSG
    MM_PRINTSTR("Lock Scache Done.\r\n")
#endif

//save t0~a6,s1~s7
    li.d     a2, ARB_STACK_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    add.d   a2, a2, a1
    st.d      s0, a2, 0x0
    st.d      s1, a2, 0x8
    st.d      s2, a2, 0x10
    st.d      s3, a2, 0x18
    st.d      s4, a2, 0x20
    st.d      s5, a2, 0x28
    st.d      s6, a2, 0x30
    st.d      s7, a2, 0x38
    st.d      t0, a2, 0x40
    st.d      t1, a2, 0x48
    st.d      t2, a2, 0x50
    st.d      t3, a2, 0x58
    st.d      t4, a2, 0x60
    st.d      t5, a2, 0x68
    st.d      t6, a2, 0x70
    st.d      t7, a2, 0x78
    st.d      t8, a2, 0x80
    st.d      a6, a2, 0x88

#if 0
    bl     arb_test_mem
    nop
#endif
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nStart ARB Leveling....\r\n")
#endif

ARB_level_begin:

#ifndef ARB_SKIP_WRLVL

#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nStart Write Leveling. Wait a while...")
#endif

//prepare for wrlvl
    bl     enable_ddr_confspace
    nop

    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    li.d     t8, ARB_STORE_BASE
    or      t8, t8, a1
    li.d     t7, DDR_MC_CONFIG_BASE
    or      t7, t7, a1

    //Get CLKLVL_DELAY_VALUE
    ld.d      a1, t7, CLKLVL_DELAY_0_ADDR
    srli.d    a2, a1, CLKLVL_DELAY_0_OFFSET
    and     a2, a2, 0x7f
    st.d      a2, t8, CLKLVL_DELAY_VALUE

    //get the current wrlvl_dq_dly value
    or    a3, zero, zero
    li.d     a2, WRLVL_DQ_DELAY_MASK

    ld.d      a1, t7, WRLVL_DQ_DELAY_0_ADDR
    srli.d    a1, a1, WRLVL_DQ_DELAY_0_OFFSET
    and     a1, a1, a2
    slli.d    a1, a1, 0
    or      a3, a1, a3

    ld.d      a1, t7, WRLVL_DQ_DELAY_1_ADDR
    srli.d    a1, a1, WRLVL_DQ_DELAY_1_OFFSET
    and     a1, a1, a2
    slli.d    a1, a1, 8
    or      a3, a1, a3

    ld.d      a1, t7, WRLVL_DQ_DELAY_2_ADDR
    srli.d    a1, a1, WRLVL_DQ_DELAY_2_OFFSET
    and     a1, a1, a2
    slli.d    a1, a1, 16
    or      a3, a1, a3

    ld.d      a1, t7, WRLVL_DQ_DELAY_3_ADDR
    srli.d    a1, a1, WRLVL_DQ_DELAY_3_OFFSET
    and     a1, a1, a2
    slli.d    a1, a1, 24
    or      a3, a1, a3

    ld.d      a1, t7, WRLVL_DQ_DELAY_4_ADDR
    srli.d    a1, a1, WRLVL_DQ_DELAY_4_OFFSET
    and     a1, a1, a2
    slli.d    a1, a1, 32
    or      a3, a1, a3

    ld.d      a1, t7, WRLVL_DQ_DELAY_5_ADDR
    srli.d    a1, a1, WRLVL_DQ_DELAY_5_OFFSET
    and     a1, a1, a2
    slli.d    a1, a1, 40
    or      a3, a1, a3

    ld.d      a1, t7, WRLVL_DQ_DELAY_6_ADDR
    srli.d    a1, a1, WRLVL_DQ_DELAY_6_OFFSET
    and     a1, a1, a2
    slli.d    a1, a1, 48
    or      a3, a1, a3

    ld.d      a1, t7, WRLVL_DQ_DELAY_7_ADDR
    srli.d    a1, a1, WRLVL_DQ_DELAY_7_OFFSET
    and     a1, a1, a2
    slli.d    a1, a1, 56
    or      a3, a1, a3

    st.d      a3, t8, WRLVL_DQ_VALUE_ADDR

    bl     disable_ddr_confspace
    nop

#ifdef  USE_WRLVL_CLK_OFFSET_VALUE
    b       arb_wrlvl_default_value
    nop
#endif

arb_wrlvl_start:
#ifdef  DEBUG_ARB_LEVEL_WR_CFG
    MM_PRINTSTR("\r\nThe MC configuration is:\r\n")
    bl     enable_ddr_confspace
    nop

    li.d     t1, DDR_PARAM_NUM
    li.d     t7, DDR_MC_CONFIG_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    or      t7, t7, a1
1:
    ld.d      t8, t7, 0x0
    srli.d    a0, t8, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("  ")
    or    a0, t8, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")

    addi.d  t1, t1, -1
    addi.d  t7, t7, 16
    bnez    t1, 1b
    nop

    bl     disable_ddr_confspace
    nop
#endif
    li.d     s3, 0xf //change all 8 byte slices

#ifndef KEEP_GATE_INIT_DLY_FIXED
    //set rdlvl gate delay value
    li.d     t6, 0x2
    li.d     t2, RDLVL_GATE_INIT_DELAY
    bl     arb_modify_param
    nop
#endif
#ifndef KEEP_DQ_DLY_FIXED
    //small wrlvl dq delay value temporary
    li.d     t6, 0x6
    li.d     t2, WRLVL_DQ_SMALL_DLY
    bl     arb_modify_param
    nop
#endif

//1. level Write DQS Delay line setting.
    //clear store mem
    li.d     t8, ARB_STORE_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    add.d   t8, t8, a1
    st.d      zero, t8, 0x0
    st.d      zero, t8, 0x8
    st.d      zero, t8, 0x10
    st.d      zero, t8, 0x18
    st.d      zero, t8, 0x20
    st.d      zero, t8, 0x28
    st.d      zero, t8, 0x30
    st.d      zero, t8, 0x38
    st.d      zero, t8, 0x40
    st.d      zero, t8, 0x48
    st.d      zero, t8, 0x50
    st.d      zero, t8, 0x58

    //set test interval
    li.d     t5, 1 << LOG2_STEP
    //set t2 start value
    li.d     t2, WRLVL_MAX_DELAY

    li.d     t0, 0x1
    srli.d    a0, t2, LOG2_STEP
    slli.d    t0, t0, a0

wrlvl_test_one_delay:
    or    t3, zero, zero
    or    t4, zero, zero
    nor     t3, t3, zero
    nor     t4, t4, zero

#ifdef  DEBUG_ARB_LEVEL_WR_TM
    MM_PRINTSTR("\r\n\r\nt2 = 0x")
    or    a0, t2, zero
    bl     mm_hexserial
    nop
#endif
    or    s4, zero, zero
    li.d     t6, 0x5
//write new delay value
    bl     arb_modify_param
    nop
#ifdef  DEBUG_ARB_LEVEL_WR_CFG
    MM_PRINTSTR("\r\nThe wrlvl_delay configuration is:\r\n")
    bl     enable_ddr_confspace
    nop

    li.d     t1, 0x3         //set print num
    li.d     t7, DDR_MC_CONFIG_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    or      t7, t7, a1
    add.d   t7, t7, 0xaf0   //set start offset
1:
    ld.d      t8, t7, 0x0
    srli.d    a0, t8, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("  ")
    or    a0, t8, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")

    addi.d  t1, t1, -1
    addi.d  t7, t7, 16
    bnez    t1, 1b
    nop

    bl     disable_ddr_confspace
    nop
#endif

    //store t2 of current wrlvl_delay value
    or    s5, t2, zero
17:
    or    t2, zero, zero
18:
    li.d     t6, 0x7
#ifdef  DEBUG_ARB_LEVEL_WR_CFG
    MM_PRINTSTR("\r\nModify read gate cfg: = 0x")
    or    a0, t2, zero
    bl     mm_hexserial
    nop
#endif
    bl     arb_modify_param
    nop

//do Test and print test result
#ifdef  DEBUG_ARB_LEVEL_WR_CFG
    MM_PRINTSTR("\r\nThe phy_ctrl_0 configuration is:\r\n")
    bl     enable_ddr_confspace
    nop

    li.d     t1, 0xa         //set print num
    li.d     t7, DDR_MC_CONFIG_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    or      t7, t7, a1
    add.d   t7, t7, 0x2d0   //set start offset
1:
    ld.d      t8, t7, 0x0
    srli.d    a0, t8, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("  ")
    or    a0, t8, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")

    addi.d  t1, t1, -1
    addi.d  t7, t7, 16
    bnez    t1, 1b
    nop

    bl     disable_ddr_confspace
    nop
#endif
    bl     arb_test_mem
    nop
#ifdef  DEBUG_ARB_LEVEL_WR_TM
    or    t7, a4, zero
    or    t8, a5, zero

    MM_PRINTSTR("\r\nRW Diff 0x")
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop

    MM_PRINTSTR("\r\nRD Diff 0x")
    srli.d    a0, t8, 32
    bl     mm_hexserial
    nop
    or    a0, t8, zero
    bl     mm_hexserial
    nop

    or    a4, t7, zero
    or    a5, t8, zero
#endif
    //process test result, only when the entire byte is correct(0x00) clear fail mark in t3.
    //byte 7
    srli.d    a0, a4, 0x38
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x38
    nor     a0, a0, zero
    and     t3, t3, a0
1:
    //byte 6
    srli.d    a0, a4, 0x30
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x30
    nor     a0, a0, zero
    and     t3, t3, a0
1:
    //byte 5
    srli.d    a0, a4, 0x28
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x28
    nor     a0, a0, zero
    and     t3, t3, a0
1:
    //byte 4
    srli.d    a0, a4, 0x20
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x20
    nor     a0, a0, zero
    and     t3, t3, a0
1:
    //byte 3
    srli.d    a0, a4, 0x18
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x18
    nor     a0, a0, zero
    and     t3, t3, a0
1:
    //byte 2
    srli.d    a0, a4, 0x10
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x10
    nor     a0, a0, zero
    and     t3, t3, a0
1:
    //byte 1
    srli.d    a0, a4, 0x08
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x08
    nor     a0, a0, zero
    and     t3, t3, a0
1:
    //byte 0
    srli.d    a0, a4, 0x0
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x0
    nor     a0, a0, zero
    and     t3, t3, a0
1:
#ifdef  DEBUG_ARB_LEVEL_WR_TM
    //record RD history in t4, normally, t4 should.d be 0x0 after all these trying
    //byte 7
    srli.d    a0, a5, 0x38
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x38
    nor     a0, a0, zero
    and     t4, t4, a0
1:
    //byte 6
    srli.d    a0, a5, 0x30
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x30
    nor     a0, a0, zero
    and     t4, t4, a0
1:
    //byte 5
    srli.d    a0, a5, 0x28
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x28
    nor     a0, a0, zero
    and     t4, t4, a0
1:
    //byte 4
    srli.d    a0, a5, 0x20
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x20
    nor     a0, a0, zero
    and     t4, t4, a0
1:
    //byte 3
    srli.d    a0, a5, 0x18
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x18
    nor     a0, a0, zero
    and     t4, t4, a0
1:
    //byte 2
    srli.d    a0, a5, 0x10
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x10
    nor     a0, a0, zero
    and     t4, t4, a0
1:
    //byte 1
    srli.d    a0, a5, 0x08
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x08
    nor     a0, a0, zero
    and     t4, t4, a0
1:
    //byte 0
    srli.d    a0, a5, 0x0
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x0
    nor     a0, a0, zero
    and     t4, t4, a0
1:
#endif

    //tryed all setting(0,1,2)
    li.d     a1, 0x2
    beq     t2, a1, 22f
    nop
    slli.d    t2, t2, 0x1
    bnez    t2, 1f
    nop
    xor     t2, t2, 0x1
1:
    b       18b
    nop
22: //test another rd pop delay cfg
    bnez    s4, 26f
    nop
    add.d   s4, s4, 1
#ifdef  DEBUG_ARB_LEVEL_WR_CFG
    MM_PRINTSTR("\r\nAlter read pop delay.")
#endif
    bl     arb_modify_pop_delay_alter
    nop

    b       17b
    nop

26: //tryed all setting(combination: pop delay and rd gat cfg)
    or    t2, s5, zero

#ifdef  DEBUG_ARB_LEVEL_WR_TM
    MM_PRINTSTR("\r\nAfter tried all the RD setting:\r\nRW Diff 0x")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    or    a0, t3, zero
    bl     mm_hexserial
    nop

    MM_PRINTSTR("\r\nRD Diff 0x")
    srli.d    a0, t4, 32
    bl     mm_hexserial
    nop
    or    a0, t4, zero
    bl     mm_hexserial
    nop
    beqz    t4, 1f
    nop
    MM_PRINTSTR("\r\nWarning!!! some byte slice can't find a correct read setting")
1:
#endif

//process TM result: translate Byte error info into 1 bit info in each BX_TM_RST of every Byte.
//64 bit BX_TM_RST work as a bit map corresponding to every param value(so the min step interval
//is 2, or there will be not enough space to store TM RST info), the 64 bit can be only part valid(
//step interval > 2).
    li.d     t8, ARB_STORE_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    add.d   t8, t8, a1

    srli.d    t7, t3, 56
    and     t7, t7, 0xff
    beqz    t7, 1f
    nop
    //error detected
    ld.d      a0, t8, B7_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, B7_TM_RST
1:
    srli.d    t7, t3, 48
    and     t7, t7, 0xff
    beqz    t7, 1f
    nop
    //error detected
    ld.d      a0, t8, B6_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, B6_TM_RST
1:
    srli.d    t7, t3, 40
    and     t7, t7, 0xff
    beqz    t7, 1f
    nop
    //error detected
    ld.d      a0, t8, B5_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, B5_TM_RST
1:
    srli.d    t7, t3, 32
    and     t7, t7, 0xff
    beqz    t7, 1f
    nop
    //error detected
    ld.d      a0, t8, B4_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, B4_TM_RST
1:
    srli.d    t7, t3, 24
    and     t7, t7, 0xff
    beqz    t7, 1f
    nop
    //error detected
    ld.d      a0, t8, B3_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, B3_TM_RST
1:
    srli.d    t7, t3, 16
    and     t7, t7, 0xff
    beqz    t7, 1f
    nop
    //error detected
    ld.d      a0, t8, B2_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, B2_TM_RST
1:
    srli.d    t7, t3, 8
    and     t7, t7, 0xff
    beqz    t7, 1f
    nop
    //error detected
    ld.d      a0, t8, B1_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, B1_TM_RST
1:
    srli.d    t7, t3, 0
    and     t7, t7, 0xff
    beqz    t7, 1f
    nop
    //error detected
    ld.d      a0, t8, B0_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, B0_TM_RST
1:
    srli.d    t0, t0, 1

    //check wether delay value exceed max value
    sub.d   a2, t2, t5
    bltz    a2, 11f //check the new delay value whether exceed limitation
    nop
    /** not exceed **/
    or    t2, a2, zero
    b       wrlvl_test_one_delay
    nop
11:

#ifdef  DEBUG_ARB_LEVEL_WR
    li.d     t8, ARB_STORE_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    add.d   t8, t8, a1
    MM_PRINTSTR("\r\nlevel result is:\r\n")
    ld.d      t7, t8, B7_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")
    ld.d      t7, t8, B6_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")
    ld.d      t7, t8, B5_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")
    ld.d      t7, t8, B4_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")
    ld.d      t7, t8, B3_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")
    ld.d      t7, t8, B2_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")
    ld.d      t7, t8, B1_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")
    ld.d      t7, t8, B0_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
#endif
//calculate mid value for each byte lane
/***********
boundary sign: contain at least WINDOW_ZERO_NUM consecutive 0(TM success)
    t0: parse pointer
    t1: BYTE OFFSET, and work as loop control
    t2: parse max position
    t3: BYTE_X_LEVEL_RST
    t4: WINDOW_ZERO_NUM
***********/
    //set t2 max value for each level object
    li.d     t2, WRLVL_MAX_DELAY
    srli.d    t2, t2, LOG2_STEP

    or    a6, zero, zero
    li.d     t8, ARB_STORE_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    add.d   t8, t8, a1

    li.d     t1, 0x38    //start from byte 7
    GET_DIMM_WIDTH
    beqz    a1, 1f
    nop
    //for 32 bit data width, add high 32 bits result to low 32 bits
    ld.d      a1, t8, B4_TM_RST
    ld.d      a2, t8, B0_TM_RST
    or      a1, a1, a2
    st.d      a1, t8, B0_TM_RST

    ld.d      a1, t8, B5_TM_RST
    ld.d      a2, t8, B1_TM_RST
    or      a1, a1, a2
    st.d      a1, t8, B1_TM_RST

    ld.d      a1, t8, B6_TM_RST
    ld.d      a2, t8, B2_TM_RST
    or      a1, a1, a2
    st.d      a1, t8, B2_TM_RST

    ld.d      a1, t8, B7_TM_RST
    ld.d      a2, t8, B3_TM_RST
    or      a1, a1, a2
    st.d      a1, t8, B3_TM_RST

    li.d     t1, 0x18    //start from byte 3
1:

11: //loop for all byte lanes
    add.d   t7, t8, t1
    ld.d      t3, t7, B0_TM_RST
#ifdef  DEBUG_ARB_LEVEL_WR
    MM_PRINTSTR("\r\nt3 = 0x")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    or    a0, t3, zero
    bl     mm_hexserial
    nop
#endif
    or    t0, zero, zero
    li.d     t4, WINDOW_ZERO_NUM
12:
    beq  t0, t2, 99f;     bgeu    t0, t2, 3f;99:
    nop
    srli.d    t7, t3, t0
    and     t7, t7, 0x1
    bnez    t7, 1f
    nop
    //find a TM success
    addi.d  t4, t4, -1
    beqz    t4, 2f
    nop
    //continue move
    addi.d  t0, t0, 0x1
    b       12b
    nop
1:  //find a TM fail
    li.d     t4, WINDOW_ZERO_NUM
    //continue move
    addi.d  t0, t0, 0x1
    b       12b
    nop
2:  //window found
    //calculate the MIN boundary
    li.d     a1, WINDOW_ZERO_NUM
    addi.d  a0, t0, 1
    sub.d   a0, a0, a1
    slli.d    a0, a0, LOG2_STEP   //a0 = a0 * 2n
    and     a0, a0, 0xff
    slli.d    a0, a0, t1
    ld.d      a1, t8, GD_MIN
    or      a1, a1, a0
    st.d      a1, t8, GD_MIN
    //move forward to the next Fail to cal the MAX boundary
1:
    addi.d  t0, t0, 0x1
    beq  t0, t2, 99f;     bgeu    t0, t2, 1f;99:
    nop
    srli.d    t7, t3, t0
    and     t7, t7, 0x1
    beqz    t7, 1b  //continue move
    nop
1:
    //find a TM FAIL or reach the max test value
    addi.d  a0, t0, -1
    slli.d    a0, a0, LOG2_STEP   //a0 = a0 * 2n
    and     a0, a0, 0xff
    slli.d    a0, a0, t1
    ld.d      a1, t8, GD_MAX
    or      a1, a1, a0
    st.d      a1, t8, GD_MAX
    b       2f
    nop
3:  //parse to end, CAN NOT find a window
    or      a6, a6, 0x1
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nWrlvl Error: This Byte Window not found.")
    MM_PRINTSTR("\r\nFailed byte is byte: ")
    srli.d    a0, t1, 3
    bl     mm_hexserial
    nop
#endif
2:  //continue for next byte lane
    beqz    t1, 2f
    nop
    add.d   t1, t1, -0x8
    b       11b
    nop
2:  //All byte lane's MIN and MAX value stored or fail to find
    beqz    a6, 1f
    nop
    //some Byte lane can not find a window
#ifdef  MODIFY_PAD_COMP
    MM_PRINTSTR("\r\nTry another pad compensation.\r\n")
    bl     arb_modify_pad_comp
    nop
    beqz    a4, arb_wrlvl_start
    nop
#endif
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nWrite level failed. Write default value.\r\n")
#endif
    //write standard value mandatory
    //wrlvl_delay
    li.d     a0, WRLVL_DEFAULT_VALUE
    st.d      a0, t8, GD_MID
    b       arb_wrlvl_value_caled
    nop
1:
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nMin value: 0x")
    ld.d      t7, t8, GD_MIN
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\nMax value: 0x")
    ld.d      t7, t8, GD_MAX
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
#endif

//calculate final value for each byte lane
#if 1   //def  DDR3_DIMM
    li.d     a0, 0x2
    GET_SDRAM_TYPE
    beq     a0, a1, 2f
    nop
    GET_DIMM_TYPE
    bnez    a1, 4f
    nop
2:
    //DDR3 UDIMM/DDR2 DIMM
    //if we find the lower limit(MIN > 0), then we use (MIN + compensation_value) as the final result.
    //else, if we find the upper limit(MAX < param upper limit), then we use (MAX - compensation_value)
    //as the final result. else(MAX reach param upper limit), we use byte0 as reference, we
    //use (MAX_byte0 - compensation_value + manual_specific_offset).
    or    t4, zero, zero
    li.d     t7, 7   //slice control
arb_level_wrlvl_ddr3_cal_begin:
    slli.d    a0, t7, 3

    ld.d      a1, t8, GD_MIN
    ld.d      a3, t8, GD_MAX
    srli.d    a1, a1, a0
    srli.d    a3, a3, a0
    and     a1, a1, 0x7f
    and     a3, a3, 0x7f

    beqz    a1, 2f
    nop
    //MIN > 0
    li.d     a4, WRLVL_DELAY_LEVEL_UP_LIMIT
#ifndef KEEP_DQ_DLY_FIXED
    li.d     a5, WRLVL_DQ_SMALL_DLY
#else
    ld.d      a5, t8, WRLVL_DQ_VALUE_ADDR
    srli.d    a5, a5, a0
    and     a5, a5, 0x7f
#endif
    sub.d   a4, a4, a5
    bge     a3, a4, 3f
    nop
    //MAX < upper limit, use (MAX + MIN)/2
    add.d   a3, a3, a1
    srli.d    a3, a3, 1
    b       arb_level_ddr3_cal_end
    nop
3:
    //MAX >= upper limit, use min + defined offset
    li.d     a4, WRLVL_DELAY_ADD_VALUE
    add.d   a3, a1, a4
    b       arb_level_ddr3_cal_end
    nop

2:  //MIN == 0
    li.d     a4, WRLVL_DELAY_LEVEL_UP_LIMIT
#ifndef KEEP_DQ_DLY_FIXED
    li.d     a5, WRLVL_DQ_SMALL_DLY
#else
    ld.d      a5, t8, WRLVL_DQ_VALUE_ADDR
    srli.d    a5, a5, a0
    and     a5, a5, 0x7f
#endif
    sub.d   a4, a4, a5
    bge     a3, a4, 3f
    nop
    //MAX < upper limit, use MAX - defined offset
    li.d     a4, WRLVL_DELAY_MINUS_VALUE
    bge     a3, a4, 1f
    nop
    or    a4, a3, zero
1:
    sub.d   a3, a3, a4
    b       arb_level_ddr3_cal_end
    nop
3:
    //MAX >= upper limit
#ifdef  DDR3_DIMM
    //use byte 0 as reference
    ld.d      a1, t8, GD_MAX
    and     a1, a1, 0x7f
    li.d     a4, WRLVL_DELAY_MINUS_VALUE
    bge     a1, a4, 1f
    nop
    or    a4, a1, zero
1:
    sub.d   a1, a1, a4
    li.d     a4, WRLVL_DDR3_UDIMM_DEFAULT_OFFSET
    srli.d    a4, a4, a0
    and     a4, a4, 0x7f
    add.d   a3, a1, a4
#else
    //for DDR2, use default value
    li.d     a4, WRLVL_DEFAULT_VALUE
    srli.d    a4, a4, a0
    and     a3, a4, 0x7f
#endif

arb_level_ddr3_cal_end:
    //check the calculated result whether exceed the max value
    //max value <= min(0x80-DQ_DLY, 0x60)
    li.d     a4, WRLVL_DELAY_PARAM_UP_LIMIT
#ifndef KEEP_DQ_DLY_FIXED
#ifndef USE_SPECIAL_WRLVL_DQ_DELAY
    li.d     a5, WRLVL_DQ_DEFAULT_DLY
#else
    li.d     a5, WRLVL_DQ_SPECIAL_DLY
    srli.d    a5, a5, a0
    and     a5, a5, 0x7f
#endif
#else
    ld.d      a5, t8, WRLVL_DQ_VALUE_ADDR
    srli.d    a5, a5, a0
    and     a5, a5, 0x7f
#endif
    sub.d   a4, a4, a5
    //get min(0x80-DQ_DLY, 0x60)
    li.d     a5, WRLVL_3QUARTER_CLK_VALUE
    ble     a4, a5, 1f
    nop
    or    a4, a5, zero
1:
    //get min(a4, a3)
    ble     a3, a4, 1f
    nop
    or    a3, a4, zero
1:
#if 0
    //check whether the value is near 0x40
    li.d     a4, 0x40
    ble     a3, a4, 1f
    nop
    //a3 > 0x40
    sub.d   a4, a3, a4
    li.d     a5, 0x8
    beq  a4, a5, 99f;     bge     a4, a5, 2f;99:
    nop
    li.d     a3, 0x48
2:  //abs(delta) > 0x8
    b       8f
    nop
1:  //a3 < 0x40
    sub.d   a4, a4, a3
    li.d     a5, 0x8
    beq  a4, a5, 99f;     bge     a4, a5, 2f;99:
    nop
    li.d     a3, 0x38
2:  //abs(delta) > 0x8
    b       8f
    nop
8:
#endif
    slli.d    a3, a3, a0
    or      t4, t4, a3

    add.d   t7, t7, -1
    bge     t7, zero, arb_level_wrlvl_ddr3_cal_begin
    nop

    or    a0, t4, zero
    b       88f
    nop

4:  //DDR3 RDIMM
    ld.d      a1, t8, GD_MIN
    ld.d      a3, t8, GD_MAX
    //select the MIN(byte 3, byte 4, byte 5), normally the byte 4 should.d be the smaller.
    //find the MIN of byte 3 and byte 4
    srli.d    a2, a3, 32
    srli.d    a4, a3, 24
    and     a2, a2, 0xff
    and     a4, a4, 0xff
    ble     a2, a4, 1f
    nop
    or    a2, a4, zero
1:
    //find the MIN of a2 and byte 5
    srli.d    a4, a3, 40
    and     a4, a4, 0xff
    ble     a2, a4, 1f
    nop
    or    a2, a4, zero
1:
    //select the MIN(byte 3,4,5 MIN, WRLVL_DELAY_MINUS_VALUE), normally the byte 4 MIN should.d be closer to 0x40
    li.d     a4, WRLVL_DELAY_MINUS_VALUE
    ble     a2, a4, 1f
    nop
    or    a2, a4, zero
1:
    and     a2, a2, 0x7f
    slli.d    a4, a2, 8
    or      a2, a2, a4  //2
    slli.d    a4, a2, 16
    or      a2, a2, a4  //4
    slli.d    a4, a2, 32
    or      a2, a2, a4  //8

    sub.d   a4, a3, a2
    li.d     a5, 0x8080808080808080
    and     a5, a5, a4
    bnez    a5, 1f
    nop
    or    a0, a4, zero
    b       88f
    nop
1:  //abnormal: some byte is smaller than MIN(byte 3, 4)
    //use mid/2
    srli.d    a0, a0, 1
    li.d     a1, 0x7f7f7f7f7f7f7f7f
    and     a0, a0, a1

88:
#else
#if 0
    //DDR2 DIMM
    ld.d      a1, t8, GD_MIN
    ld.d      a3, t8, GD_MAX
    //Refer to Byte 0
    srli.d    a2, a1, 0
    and     a2, a2, 0x7f
    beqz    a2, 2f
    nop
    //MIN != 0
    srli.d    a2, a3, 0
    and     a2, a2, 0x7f
    li.d     a4, (WRLVL_MAX_DELAY - 0x4)
    blt     a2, a4, 1f
    nop
    //MAX reach boundary
    //MIN not reach boundary, MAX reach boundary, use (MAX+MID)/2
    add.d   a4, a3, a0
    srli.d    a4, a4, 1
    li.d     a5, 0x7f7f7f7f7f7f7f7f
    and     a4, a4, a5

    add.d   a4, a4, a0
    srli.d    a4, a4, 1
    li.d     a5, 0x7f7f7f7f7f7f7f7f
    and     a4, a4, a5

    li.d     a5, 0xffffffffffffffff
    nor     a5, a5, zero
    and     a0, a0, a5
    or      a0, a0, a4

    b       88f
    nop
1:
    //MAX not reach boundary
    //MIN && MAX neither reach boundary, use mid_value
    b       88f
    nop
2:
    //MIN == 0
    srli.d    a2, a3, 0
    and     a2, a2, 0x7f
    li.d     a4, (WRLVL_MAX_DELAY - 0x4)
    blt     a2, a4, 1f
    nop
    //MAX reach boundary
    //MIN && MAX both reach boundary, use mid_value / 2
    b       88f
    nop
1:
    //MIN reach boundary, MAX not reach boundary
#if 0   //mid_value / 2
    srli.d    a4, a0, 1
    li.d     a2, 0x7f7f7f7f7f7f7f7f
    and     a4, a4, a2
    li.d     a2, 0xffffffffffffffff
    nor     a2, a2, zero
    and     a0, a0, a2
    or      a0, a0, a4
#endif
#if 1    //use max_value - offset
    li.d     a2, 0x3030303030303030
    sub.d   a0, a3, a2
    li.d     a2, 0x7f7f7f7f7f7f7f7f
    and     a0, a0, a2
#endif
88:
#endif
#endif
    st.d      a0, t8, GD_MID
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nCal Mid value: 0x")
    ld.d      t7, t8, GD_MID
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
#endif

#ifdef  USE_WRLVL_CLK_OFFSET_VALUE
    b       arb_wrlvl_value_caled
    nop

arb_wrlvl_default_value:
    //get clk_dll value
    ld.d      a2, t8, CLKLVL_DELAY_VALUE
    //shift byte 0 value to 8 bytes of a2
    slli.d    a4, a2, 0x8
    add.d   a2, a2, a4
    slli.d    a4, a2, 0x10
    add.d   a2, a2, a4
    slli.d    a4, a2, 0x20
    add.d   a2, a2, a4
    //load different value under different freq and DIMM number
    //currently, all use the same default value
    li.d     a0, WRLVL_CLK_OFFSET_VALUE
    add.d   a0, a0, a2
    st.d      a0, t8, GD_MID
#endif

arb_wrlvl_value_caled:
    ld.d      t2, t8, GD_MID
#ifdef DEBUG_ARB_LEVEL_WR
    MM_PRINTSTR("\r\nWrite param and value:\r\nt2 = 0x")
    srli.d    a0, t2, 32
    bl     mm_hexserial
    nop
    or    a0, t2, zero
    bl     mm_hexserial
    nop
#endif
    li.d     t6, 0x5
    bl     arb_write_param
    nop

#ifndef KEEP_DQ_DLY_FIXED
    //recover wrlvl dq delay value
    li.d     t6, 0x6
#ifndef USE_SPECIAL_WRLVL_DQ_DELAY
    li.d     t2, WRLVL_DQ_DEFAULT_DLY
    bl     arb_modify_param
    nop
#else
    li.d     t2, WRLVL_DQ_SPECIAL_DLY
    bl     arb_write_param
    nop
#endif
#endif

#ifdef DEBUG_ARB_LEVEL_WR
    MM_PRINTSTR("\r\nAfter write leveling. The MC configuration is:\r\n")

    bl     enable_ddr_confspace
    nop

    li.d     t1, DDR_PARAM_NUM
    li.d     t7, DDR_MC_CONFIG_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    or      t7, t7, a1
1:
    ld.d      t3, t7, 0x0
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("  ")
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")

    addi.d  t1, t1, -1
    addi.d  t7, t7, 16
    bnez    t1, 1b
    nop

    bl     disable_ddr_confspace
    nop
#endif
#endif

//2. read_level read param cfg: include: POP delay(3 or 4), rd_gate_cfg, rd gate delay line and rdlvl_dqsP/N
//use RW result, because we have done wr_dqs leveling, so there should.d not be RW errors.
/*
 * s3: level byte slice--global
 * t8: ARB_STORE_BASE--global
 * s5: slice mask--global
 * s4: slice inner loop control--global
 * t6: lvl sel-- stage global
 * t2: lvl value--stage global
 * a6: gate lvl value control--stage global
 */
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\n\r\nStart read leveling..")
#endif

    //s3---level byte lane
    li.d     s3, 0x7
    GET_DIMM_WIDTH
    beqz    a1, 1f
    nop
    li.d     s3, 0x3
1:
    //set t8
    li.d     t8, ARB_STORE_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    add.d   t8, t8, a1

//loop for 8 slice
rdlvl_one_byte_start:
    //one bye lane level begin
    bltz    s3, rdlvl_end
    nop
    //clear store mem
    st.d      zero, t8, 0x0
    st.d      zero, t8, 0x8
    st.d      zero, t8, 0x10
    st.d      zero, t8, 0x18
    st.d      zero, t8, 0x20
    st.d      zero, t8, 0x28
    st.d      zero, t8, 0x30
    st.d      zero, t8, 0x38
    st.d      zero, t8, 0x40
    st.d      zero, t8, 0x48
    st.d      zero, t8, 0x50
    st.d      zero, t8, 0x58

    //set specified byte lanes Mask
    li.d     a0, 0x8
    dmul    a0, a0, s3
    li.d     a1, 0xff
    slli.d    s5, a1, a0

    GET_DIMM_WIDTH
    beqz    a1, 1f
    nop
    //for reduc setting, set mask to high
    slli.d    a1, s5, 32
    or      s5, s5, a1
1:

#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\n\r\n\r\nLevel slice: 0x")
    or    a0, s3, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\nWait a while...")
#endif
#ifdef  DEBUG_ARB_LEVEL_RD
    MM_PRINTSTR("\r\ns5 = 0x")
    srli.d    a0, s5, 32
    bl     mm_hexserial
    nop
    or    a0, s5, zero
    bl     mm_hexserial
    nop
#endif

    //test the possible two RD pop delay
    //loop twice: for each POP delay cfg(3 or 4), find a best gate cfg(include phy_gate_cfg and rdlvl_gate_delay) first,
    //then calculate the range of rdlvl_delay_P/N, use the larger range as final setting.
    or    s4, zero, zero
rdlvl_pop_delay_start:
    //set rdlvl_delay_P/N to default value
    li.d     t2, RDLVL_DEFAULT_DELAY
    li.d     t6, 0x3
    bl     arb_modify_param
    nop
    li.d     t6, 0x4
    bl     arb_modify_param
    nop

    //leveling phy_1 read gate cfg and rdlvl_gate_delay
    //out loop. Coarse leveling.---adjust phy_1 read gate cfg
    li.d     a6, 0x2
    //decrease from bigger to small because we want to use as bigger as possible.
rdlvl_gate_cfg_start:
    or    t2, a6, zero
#ifdef  DEBUG_ARB_LEVEL_RD_CFG
    MM_PRINTSTR("\r\nModify read gate cfg: t2 = 0x")
    or    a0, t2, zero
    bl     mm_hexserial
    nop
#endif
    li.d     t6, 0x7
    bl     arb_modify_param
    nop
#ifdef  DEBUG_ARB_LEVEL_RD_CFG
    MM_PRINTSTR("\r\nThe MC configuration is:\r\n")
    bl     enable_ddr_confspace
    nop

    //li.d     t1, DDR_PARAM_NUM
    li.d     t1, 0xa         //set print num
    li.d     t7, DDR_MC_CONFIG_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    or      t7, t7, a1
    add.d   t7, t7, 0x2d0   //set start offset
1:
    ld.d      t3, t7, 0x0
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("  ")
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")

    addi.d  t1, t1, -1
    addi.d  t7, t7, 16
    bnez    t1, 1b
    nop

    bl     disable_ddr_confspace
    nop
#endif
    //inner loop. fine leveling.---adjust rdlvl_gate_delay_X

    //clear Store space
    st.d      zero, t8, BYTE_TM_RST
    st.d      zero, t8, GD_MIN
    st.d      zero, t8, GD_MAX
    st.d      zero, t8, GD_MID

    //initialize
    li.d     t6, 0x2
    //set t2 start value
    li.d     t2, RDLVL_GATE_MAX_DELAY

    li.d     t0, 0x1
    srli.d    a0, t2, GATE_LOG2_STEP
    slli.d    t0, t0, a0

    li.d     t5, 1 << GATE_LOG2_STEP
31:
//write new delay value
    bl     arb_modify_param
    nop

//do Test and print test result
    bl     arb_test_mem
    nop
    or    t3, a4, zero
    or    t4, a5, zero
#ifdef  DEBUG_ARB_LEVEL_RD_TM
    MM_PRINTSTR("\r\nt2 = 0x")
    or    a0, t2, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR(":")
    beqz    t3, 1f
    nop
    MM_PRINTSTR("\r\nRW Diff 0x")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\nRD Diff 0x")
    srli.d    a0, t4, 32
    bl     mm_hexserial
    nop
    or    a0, t4, zero
    bl     mm_hexserial
    nop
    b       2f
    nop
1:
    MM_PRINTSTR("\r\nNo Error detected.")
2:
#endif
    //Mask out other byte lanes info
    and     t3, t3, s5
    and     t4, t4, s5
//process TM result: translate Byte error info into 1 bit info in each BX_TM_RST of every Byte.
//64 bit BX_TM_RST work as a bit map corresponding to every param value(so the min step interval
//is 2, or there will be not enough space to store TM RST info), the 64 bit can be only part valid(
//step interval > 2).
    beqz    t3, 1f
    nop
    //error detected
    ld.d      a0, t8, BYTE_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, BYTE_TM_RST
1:
    srli.d    t0, t0, 1

    //check whether delay value reach the boundary
    sub.d   a2, t2, t5
    bltz    a2, 11f //check the new delay value whether exceed limitation
    nop
    /** not exceed **/
    or    t2, a2, zero
    b       31b
    nop
11:

#ifdef  DEBUG_ARB_LEVEL_RD
    MM_PRINTSTR("\r\nlevel result is:\r\n")
    ld.d      t7, t8, BYTE_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
#endif
//calculate mid value for this byte lane
/***********
boundary sign: contain at least RDLVL_WINDOW_ZERO_NUM consecutive 0(TM success)
    t0: parse pointer
    t2: parse max position
    t3: BYTE_X_LEVEL_RST
    t4: RDLVL_WINDOW_ZERO_NUM
***********/
    //set t2 max value for each level object
    li.d     t2, RDLVL_GATE_MAX_DELAY
    srli.d    t2, t2, GATE_LOG2_STEP

    ld.d      t3, t8, BYTE_TM_RST
#ifdef  DEBUG_ARB_LEVEL_RD_TM
    MM_PRINTSTR("\r\nt3 = 0x")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    or    a0, t3, zero
    bl     mm_hexserial
    nop
#endif
    or    t0, zero, zero
    li.d     t4, RDLVL_WINDOW_ZERO_NUM + (GATE_ADJUST)
12:
    beq  t0, t2, 99f;     bgeu    t0, t2, 3f;99:
    nop
    srli.d    t7, t3, t0
    and     t7, t7, 0x1
    bnez    t7, 1f
    nop
    //find a TM success
    addi.d  t4, t4, -1
    beqz    t4, 2f
    nop
    //continue move
    addi.d  t0, t0, 0x1
    b       12b
    nop
1:  //find a TM fail
    li.d     t4, RDLVL_WINDOW_ZERO_NUM + (GATE_ADJUST)
    //continue move
    addi.d  t0, t0, 0x1
    b       12b
    nop
2:  //window found
    //calculate the MIN boundary
    li.d     a1, RDLVL_WINDOW_ZERO_NUM + (GATE_ADJUST)
    addi.d  a0, t0, 1
    sub.d   a0, a0, a1
    slli.d    a0, a0, GATE_LOG2_STEP   //a0 = a0 * 2n
    and     a0, a0, 0xff
    st.d      a0, t8, GD_MIN
    //move forward to the next Fail to cal the MAX boundary
1:
    addi.d  t0, t0, 0x1
    beq  t0, t2, 99f;     bgeu    t0, t2, 1f;99:
    nop
    srli.d    t7, t3, t0
    and     t7, t7, 0x1
    beqz    t7, 1b  //continue move
    nop
1:
    //find a TM FAIL or reach the max test value
    addi.d  a0, t0, -1
    slli.d    a0, a0, GATE_LOG2_STEP   //a0 = a0 * 2n
    and     a0, a0, 0xff
    st.d      a0, t8, GD_MAX
    b       2f
    nop
3:  //parse to end, CAN NOT find a window
#ifdef  DEBUG_ARB_LEVEL_RD
    MM_PRINTSTR("\r\nError: RDLVL Gate delay Window not found.")
    MM_PRINTSTR("\r\nt3 = 0x")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    or    a0, t3, zero
    bl     mm_hexserial
    nop
#endif
    beqz    a6, rdlvl_gate_cfg_fail
    nop
    srli.d    a6, a6, 0x1
    b       rdlvl_gate_cfg_start
    nop

rdlvl_gate_cfg_fail:    //tryed all setting(0,1), can NOT find a right cfg, try another pop delay.
    //write fail mark
    li.d     a1, 0x1
    slli.d    a1, a1, s4
    ld.d      a0, t8, RDLVL_FAIL_MARK
    or      a0, a0, a1
    st.d      a0, t8, RDLVL_FAIL_MARK

    b       rdlvl_pop_delay_end
    nop

2:  //find this byte lane's window
    //Find a right cfg
    //store rd gate cfg
    slli.d    a1, s4, 3
    slli.d    a1, a6, a1
    ld.d      a0, t8, RDLVL_GATE_CFG
    or      a0, a0, a1
    st.d      a0, t8, RDLVL_GATE_CFG

#ifdef  DEBUG_ARB_LEVEL_RD
    MM_PRINTSTR("\r\nMin value: 0x")
    ld.d      t7, t8, GD_MIN
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\nMax value: 0x")
    ld.d      t7, t8, GD_MAX
    or    a0, t7, zero
    bl     mm_hexserial
    nop
#endif
    //store rdlvl_gate_delay min / max
    slli.d    a2, s4, 3

    ld.d      a1, t8, GD_MIN
    slli.d    a1, a1, a2
    ld.d      a0, t8, RDLVL_GATE_GD_MIN
    or      a0, a0, a1
    st.d      a0, t8, RDLVL_GATE_GD_MIN

    ld.d      a1, t8, GD_MAX
    slli.d    a1, a1, a2
    ld.d      a0, t8, RDLVL_GATE_GD_MAX
    or      a0, a0, a1
    st.d      a0, t8, RDLVL_GATE_GD_MAX

//calculate mid value for this byte lane
    ld.d      a0, t8, GD_MIN
    ld.d      a1, t8, GD_MAX
    add.d   a0, a0, a1
    srli.d    a0, a0, 1
#if 1
    //max rdlvl_gate_delay == RDLVL_GATE_MAX_DELAY, use (mid + max) / 2
    //else use max value - 0x10
    li.d     a2, RDLVL_GATE_MAX_DELAY
    blt     a1, a2, 1f
    nop
    add.d   a0, a0, a1
    srli.d    a0, a0, 1
    b       8f
    nop
1:
    li.d     a2, 0x10
    sub.d   a0, a1, a2
    bge     a0, zero, 8f
    nop
    or    a0, zero, zero
8:
#endif
    st.d      a0, t8, GD_MID
    or    t2, a0, zero

#ifdef  DEBUG_ARB_LEVEL_RD
    MM_PRINTSTR("\r\nCal Mid value: 0x")
    ld.d      t7, t8, GD_MID
    or    a0, t7, zero
    bl     mm_hexserial
    nop
#endif
    bl     arb_modify_param
    nop

    //3. find the rdlvl_delay_P/N range.
    //level RD_DQSp/n delay line setting
    //use t6 to control rdlvl_delayP or rdlvl_delayN
    li.d     t6, 0x3
21:
    li.d     a1, 0x4
    beq  t6, a1, 99f;     bge     t6, a1, rdlvl_pop_delay_end;99:
    nop
//one level begin
    //clear Store space
    st.d      zero, t8, BYTE_TM_RST
    st.d      zero, t8, GD_MIN
    st.d      zero, t8, GD_MAX
    st.d      zero, t8, GD_MID

    //set t2 start value
    li.d     t2, RDLVL_MAX_DELAY

    li.d     t0, 0x1
    srli.d    a0, t2, RDLVL_LOG2_STEP
    slli.d    t0, t0, a0

    li.d     t5, 1 << RDLVL_LOG2_STEP
31:
//write new delay value
    bl     arb_modify_param
    nop

//do Test and print test result
    bl     arb_test_mem
    nop
    or    t3, a4, zero
    or    t4, a5, zero
#ifdef  DEBUG_ARB_LEVEL_RD_TM
    MM_PRINTSTR("\r\nt2 = 0x")
    or    a0, t2, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR(":")
    beqz    t3, 1f
    nop
    MM_PRINTSTR("\r\nRW Diff 0x")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\nRD Diff 0x")
    srli.d    a0, t4, 32
    bl     mm_hexserial
    nop
    or    a0, t4, zero
    bl     mm_hexserial
    nop
    b       2f
    nop
1:
    MM_PRINTSTR("\r\nNo Error detected.")
2:
#endif
    //Mask out this byte lane info
    and     t3, t3, s5
    and     t4, t4, s5
//process TM result: translate Byte error info into 1 bit info in each BX_TM_RST of every Byte.
//64 bit BX_TM_RST work as a bit map corresponding to every param value(so the min step interval
//is 2, or there will be not enough space to store TM RST info), the 64 bit can be only part valid(
//step interval > 2).
    beqz    t3, 1f
    nop
    //error detected
    ld.d      a0, t8, BYTE_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, BYTE_TM_RST
1:
    srli.d    t0, t0, 1

    //check whether delay value reach the boundary
    sub.d   a2, t2, t5
    bltz    a2, 11f //check the new delay value whether exceed limitation
    nop
    /** not exceed **/
    or    t2, a2, zero
    b       31b
    nop
11:

#ifdef  DEBUG_ARB_LEVEL_RD_TM
    MM_PRINTSTR("\r\nlevel result is:\r\n")
    ld.d      t7, t8, BYTE_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
#endif
//calculate mid value for this byte lane
/***********
boundary sign: contain at least RDLVL_WINDOW_ZERO_NUM consecutive 0(TM success)
    t0: parse pointer
    t2: parse max position
    t3: BYTE_X_LEVEL_RST
    t4: RDLVL_WINDOW_ZERO_NUM
***********/
    //set t2 max value for each level object
    li.d     t2, RDLVL_MAX_DELAY
    srli.d    t2, t2, RDLVL_LOG2_STEP

    ld.d      t3, t8, BYTE_TM_RST
#ifdef  DEBUG_ARB_LEVEL_RD_TM
    MM_PRINTSTR("\r\nt3 = 0x")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    or    a0, t3, zero
    bl     mm_hexserial
    nop
#endif
    or    t0, zero, zero
    li.d     t4, RDLVL_WINDOW_ZERO_NUM
12:
    beq  t0, t2, 99f;     bgeu    t0, t2, 3f;99:
    nop
    srli.d    t7, t3, t0
    and     t7, t7, 0x1
    bnez    t7, 1f
    nop
    //find a TM success
    addi.d  t4, t4, -1
    beqz    t4, 2f
    nop
    //continue move
    addi.d  t0, t0, 0x1
    b       12b
    nop
1:  //find a TM fail
    li.d     t4, RDLVL_WINDOW_ZERO_NUM
    //continue move
    addi.d  t0, t0, 0x1
    b       12b
    nop
2:  //window found
    //calculate the MIN boundary
    li.d     a1, RDLVL_WINDOW_ZERO_NUM
    addi.d  a0, t0, 1
    sub.d   a0, a0, a1
    slli.d    a0, a0, RDLVL_LOG2_STEP   //a0 = a0 * 2n
    and     a0, a0, 0xff
    st.d      a0, t8, GD_MIN
    //move forward to the next Fail to cal the MAX boundary
1:
    addi.d  t0, t0, 0x1
    beq  t0, t2, 99f;     bgeu    t0, t2, 1f;99:
    nop
    srli.d    t7, t3, t0
    and     t7, t7, 0x1
    beqz    t7, 1b  //continue move
    nop
1:
    //find a TM FAIL or reach the max test value
    addi.d  a0, t0, -1
    slli.d    a0, a0, RDLVL_LOG2_STEP   //a0 = a0 * 2n
    and     a0, a0, 0xff
    st.d      a0, t8, GD_MAX
    b       2f
    nop
3:  //parse to end, CAN NOT find a window
#ifdef  DEBUG_ARB_LEVEL_RD
    MM_PRINTSTR("\r\nError: rdlvl_delay Byte Window not found.")
    MM_PRINTSTR("\r\nt3 = 0x")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    or    a0, t3, zero
    bl     mm_hexserial
    nop
#endif
    li.d     a1, 0x1
    slli.d    a1, a1, s4
    ld.d      a0, t8, RDLVL_FAIL_MARK
    or      a0, a0, a1
    st.d      a0, t8, RDLVL_FAIL_MARK

    b       rdlvl_pop_delay_end
    nop
2:  //this byte lane's MIN and MAX value stored
#ifdef  DEBUG_ARB_LEVEL_RD
    MM_PRINTSTR("\r\nMin value: 0x")
    ld.d      t7, t8, GD_MIN
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\nMax value: 0x")
    ld.d      t7, t8, GD_MAX
    or    a0, t7, zero
    bl     mm_hexserial
    nop
#endif

    //store rdlvl_delay_p/n min / max
    slli.d    a2, s4, 3

    li.d     a1, 0x3
    bne     t6, a1, 1f
    nop
    ld.d      a1, t8, GD_MIN
    slli.d    a1, a1, a2
    ld.d      a0, t8, RDLVL_DELAYP_GD_MIN
    or      a0, a0, a1
    st.d      a0, t8, RDLVL_DELAYP_GD_MIN

    ld.d      a1, t8, GD_MAX
    slli.d    a1, a1, a2
    ld.d      a0, t8, RDLVL_DELAYP_GD_MAX
    or      a0, a0, a1
    st.d      a0, t8, RDLVL_DELAYP_GD_MAX
    b       2f
    nop
1:
    ld.d      a1, t8, GD_MIN
    slli.d    a1, a1, a2
    ld.d      a0, t8, RDLVL_DELAYN_GD_MIN
    or      a0, a0, a1
    st.d      a0, t8, RDLVL_DELAYN_GD_MIN

    ld.d      a1, t8, GD_MAX
    slli.d    a1, a1, a2
    ld.d      a0, t8, RDLVL_DELAYN_GD_MAX
    or      a0, a0, a1
    st.d      a0, t8, RDLVL_DELAYN_GD_MAX
2:
    //write default value to this rdlvl_delayP/N for next loop
    li.d     t2, RDLVL_DEFAULT_DELAY
    bl     arb_modify_param
    nop

    //move to next level
    addi.d  t6, t6, 0x1
    b       21b
    nop

rdlvl_pop_delay_end:
#ifdef  DEBUG_ARB_LEVEL_RD_CFG
    MM_PRINTSTR("\r\nThe MC configuration is:\r\n")
    bl     enable_ddr_confspace
    nop

    //li.d     t1, DDR_PARAM_NUM
    li.d     t1, 0xa         //set print num
    li.d     t7, DDR_MC_CONFIG_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    or      t7, t7, a1
    add.d   t7, t7, 0x2d0   //set start offset
1:
    ld.d      t3, t7, 0x0
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("  ")
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")

    addi.d  t1, t1, -1
    addi.d  t7, t7, 16
    bnez    t1, 1b
    nop

    bl     disable_ddr_confspace
    nop
#endif

    bnez    s4, 26f
    nop
    add.d   s4, s4, 1
#ifdef  DEBUG_ARB_LEVEL_RD
    MM_PRINTSTR("\r\nalter pop delay setting.\r\n")
#endif
    bl     arb_modify_pop_delay_alter
    nop
    b       rdlvl_pop_delay_start
    nop

26: //two pop delay value has been tested.
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nRDLVL_FAIL_MARK: 0x")
    ld.d      t7, t8, RDLVL_FAIL_MARK
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\nRDLVL_GATE_CFG: 0x")
    ld.d      t7, t8, RDLVL_GATE_CFG
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\nRDLVL_GATE_GD_MIN: 0x")
    ld.d      t7, t8, RDLVL_GATE_GD_MIN
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\nRDLVL_GATE_GD_MAX: 0x")
    ld.d      t7, t8, RDLVL_GATE_GD_MAX
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\nRDLVL_DELAYP_GD_MIN: 0x")
    ld.d      t7, t8, RDLVL_DELAYP_GD_MIN
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\nRDLVL_DELAYP_GD_MAX: 0x")
    ld.d      t7, t8, RDLVL_DELAYP_GD_MAX
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\nRDLVL_DELAYN_GD_MIN: 0x")
    ld.d      t7, t8, RDLVL_DELAYN_GD_MIN
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\nRDLVL_DELAYN_GD_MAX: 0x")
    ld.d      t7, t8, RDLVL_DELAYN_GD_MAX
    or    a0, t7, zero
    bl     mm_hexserial
    nop
#endif
    ld.d      a0, t8, RDLVL_FAIL_MARK
    beqz    a0, both_pop_delay_ok
    nop
    //at least 1 pop delay failed
    li.d     a1, 0x3
    beq     a0, a1, both_pop_delay_fail
    nop
    li.d     a1, 0x2
    //a0 == 2'b10
    beq     a0, a1, first_pop_delay_ok
    nop
    //a0 == 2'b01
    b       second_pop_delay_ok
    nop

both_pop_delay_fail:
#ifdef  MODIFY_PAD_COMP
    MM_PRINTSTR("\r\nTry another pad compensation.\r\n")
    bl     arb_modify_pad_comp
    nop
    beqz    a4, rdlvl_one_byte_start
    nop
#endif
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nERROR: This Slice level failed, write default value.")
#endif
//write standard value
    //write the phy_1_gate_cfg
    li.d     t6, 0x7
    li.d     t2, 0x1
    bl     arb_modify_param
    nop
    //write the rdlvl_gate_delay
    li.d     t6, 0x2
    li.d     t2, 0x19
    bl     arb_modify_param
    nop
    //write rdlvl_delay_p/n
    li.d     t2, RDLVL_DEFAULT_DELAY
    li.d     t6, 0x3
    bl     arb_modify_param
    nop
    add.d   t6, t6, 0x1
    bl     arb_modify_param
    nop
    b       rdlvl_one_byte_end
    nop

both_pop_delay_ok:
    //use test result stored in RDLVL_DELAYP/N_MIN and RDLVL_DELAYP/N_MAX to
    //decide use which pop delay and relative phy_1_gate_cfg
    //t1, t3--first pop delay result
    //t2, t4--second pop delay result
    ld.d      a0, t8, RDLVL_DELAYP_GD_MIN
    ld.d      a1, t8, RDLVL_DELAYP_GD_MAX
    sub.d   a2, a1, a0
    srli.d    t1, a2, 0
    srli.d    t2, a2, 8
    ld.d      a0, t8, RDLVL_DELAYN_GD_MIN
    ld.d      a1, t8, RDLVL_DELAYN_GD_MAX
    sub.d   a2, a1, a0
    srli.d    t3, a2, 0
    srli.d    t4, a2, 8
    and     t1, t1, 0xff
    and     t2, t2, 0xff
    and     t3, t3, 0xff
    and     t4, t4, 0xff

    //find the min of first pop delay and second pop delay
    //t1=MIN(RDLVL_DELAYP/N) first
    //t2=MIN(RDLVL_DELAYP/N) second

    ble     t1, t3, 1f
    nop
    or    t1, t3, zero
1:
    ble     t2, t4, 1f
    nop
    or    t2, t4, zero
1:
#ifdef  DDR3_DIMM
    //for slice 4~7
    //li.d     a0, 0x4
    //blt     s3, a0, 1f
    //nop

    //give the second cfg(4) priority, if the difference <= 8, use second_pop_delay
    sub.d   t1, t1, 0x8
1:
#endif
    ble     t1, t2, second_pop_delay_ok
    nop
    //the first cfg is better
first_pop_delay_ok:
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nThis Slice level success, use first value.")
#endif
    bl     arb_modify_pop_delay_alter
    nop
    //write the phy_1_gate_cfg
    li.d     t6, 0x7
    ld.d      a1, t8, RDLVL_GATE_CFG
    and     t2, a1, 0xff
    bl     arb_modify_param
    nop
    //write the rdlvl_gate_delay
    ld.d      a0, t8, RDLVL_GATE_GD_MIN
    ld.d      a1, t8, RDLVL_GATE_GD_MAX
    and     a0, a0, 0xff
    and     a1, a1, 0xff
    add.d   a0, a0, a1
    srli.d    a0, a0, 1
#if 1
    //max rdlvl_gate_delay == RDLVL_GATE_MAX_DELAY, use (mid + max) / 2
    //else use max value - 0x10
    li.d     a2, RDLVL_GATE_MAX_DELAY
    blt     a1, a2, 1f
    nop
    add.d   a0, a0, a1
    srli.d    a0, a0, 1
    b       8f
    nop
1:
    li.d     a2, 0x10
    sub.d   a0, a1, a2
    bge     a0, zero, 8f
    nop
    or    a0, zero, zero
8:
#endif
    st.d      a0, t8, GD_MID
    or    t2, a0, zero

    li.d     t6, 0x2
    bl     arb_modify_param
    nop

    //write rdlvl_delay_p/n
    li.d     t2, RDLVL_DEFAULT_DELAY
#ifndef USE_DEFAULT_RDLVL_DELAY
    ld.d      a0, t8, RDLVL_DELAYP_GD_MIN
    ld.d      a1, t8, RDLVL_DELAYP_GD_MAX
    and     a0, a0, 0xff
    and     a1, a1, 0xff
    add.d   a0, a0, a1
    srli.d    a0, a0, 1
    or    t2, a0, zero
#endif
    li.d     t6, 0x3
    bl     arb_modify_param
    nop
    add.d   t6, t6, 0x1
#ifndef USE_DEFAULT_RDLVL_DELAY
    ld.d      a0, t8, RDLVL_DELAYN_GD_MIN
    ld.d      a1, t8, RDLVL_DELAYN_GD_MAX
    and     a0, a0, 0xff
    and     a1, a1, 0xff
    add.d   a0, a0, a1
    srli.d    a0, a0, 1
    or    t2, a0, zero
#endif
    bl     arb_modify_param
    nop

    b       rdlvl_one_byte_end
    nop

second_pop_delay_ok:
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nThis Slice level success, use second value.")
#endif
#ifndef USE_DEFAULT_RDLVL_DELAY
    //write rdlvl_delay_p/n
    ld.d      a0, t8, RDLVL_DELAYP_GD_MIN
    ld.d      a1, t8, RDLVL_DELAYP_GD_MAX
    srli.d    a0, a0, 0x8
    srli.d    a1, a1, 0x8
    and     a0, a0, 0xff
    and     a1, a1, 0xff
    add.d   a0, a0, a1
    srli.d    a0, a0, 1
    or    t2, a0, zero

    li.d     t6, 0x3
    bl     arb_modify_param
    nop
    add.d   t6, t6, 0x1

    ld.d      a0, t8, RDLVL_DELAYN_GD_MIN
    ld.d      a1, t8, RDLVL_DELAYN_GD_MAX
    srli.d    a0, a0, 0x8
    srli.d    a1, a1, 0x8
    and     a0, a0, 0xff
    and     a1, a1, 0xff
    add.d   a0, a0, a1
    srli.d    a0, a0, 1
    or    t2, a0, zero

    bl     arb_modify_param
    nop
#endif
#if 0
    //need to do nothing as all the correct cfg has been written.
    li.d     t2, RDLVL_DEFAULT_DELAY
    li.d     t6, 0x3
    bl     arb_modify_param
    nop
    add.d   t6, t6, 0x1
    bl     arb_modify_param
    nop
#endif

rdlvl_one_byte_end:

#ifdef  DEBUG_ARB_LEVEL_RD_CFG
    MM_PRINTSTR("\r\nAfter rdlvl_one_byte test. The MC configuration is:\r\n")
    bl     enable_ddr_confspace
    nop

    li.d     t1, DDR_PARAM_NUM
    li.d     t7, DDR_MC_CONFIG_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    or      t7, t7, a1
1:
    ld.d      t3, t7, 0x0
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("  ")
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")

    addi.d  t1, t1, -1
    addi.d  t7, t7, 16
    bnez    t1, 1b
    nop

    bl     disable_ddr_confspace
    nop
#endif
//level next byte slice
    add.d   s3, s3, -1
    b       rdlvl_one_byte_start
    nop

//rdlvl finished
rdlvl_end:
#ifdef  DEBUG_ARB_LEVEL_RD_CFG
    MM_PRINTSTR("\r\nAfter read level. The MC configuration is:\r\n")
    bl     enable_ddr_confspace
    nop

    li.d     t1, DDR_PARAM_NUM
    li.d     t7, DDR_MC_CONFIG_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    or      t7, t7, a1
1:
    ld.d      t3, t7, 0x0
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("  ")
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")

    addi.d  t1, t1, -1
    addi.d  t7, t7, 16
    bnez    t1, 1b
    nop

    bl     disable_ddr_confspace
    nop
#endif

#ifdef  CLOCK_LEVEL   //don't enable it
//clk level---cannot be used under DDR3 mode!!!

//#define DEBUG_ARB_LEVEL_CLK
//#define DEBUG_ARB_LEVEL_CLK_TM
//#define DEBUG_ARB_LEVEL_CLK_CFG

#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\n\r\nStart Clock Leveling. Wait a while...")
#endif

arb_clklvl_start:
#ifdef  DEBUG_ARB_LEVEL_CLK_CFG
    MM_PRINTSTR("\r\nThe MC configuration is:\r\n")
    bl     enable_ddr_confspace
    nop

    li.d     t1, DDR_PARAM_NUM
    li.d     t7, DDR_MC_CONFIG_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    or      t7, t7, a1
1:
    ld.d      t8, t7, 0x0
    srli.d    a0, t8, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("  ")
    or    a0, t8, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")

    addi.d  t1, t1, -1
    addi.d  t7, t7, 16
    bnez    t1, 1b
    nop

    bl     disable_ddr_confspace
    nop
#endif
    li.d     s3, 0xf //change all 8 byte slices

//1. level Write DQS Delay line setting.
    //clear store mem
    li.d     t8, ARB_STORE_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    add.d   t8, t8, a1
    st.d      zero, t8, 0x0
    st.d      zero, t8, 0x8
    st.d      zero, t8, 0x10
    st.d      zero, t8, 0x18
    st.d      zero, t8, 0x20
    st.d      zero, t8, 0x28
    st.d      zero, t8, 0x30
    st.d      zero, t8, 0x38
    st.d      zero, t8, 0x40
    st.d      zero, t8, 0x48
    st.d      zero, t8, 0x50
    st.d      zero, t8, 0x58

    //set test interval
    li.d     t5, 1 << LOG2_STEP
    //set t2 start value
    or    t2, zero, zero
    li.d     s4, CLKLVL_MAX_DELAY
#if 0
    MM_PRINTSTR("\r\nplease input clklvl max value: ")
    bl     inputaddress
    nop
    or    s4, a4, zero
#endif

    li.d     t0, 0x1
    srli.d    a0, t2, LOG2_STEP
    slli.d    t0, t0, a0

clklvl_test_one_delay:
    or    t3, zero, zero
    or    t4, zero, zero
    nor     t3, t3, zero
    nor     t4, t4, zero

#ifdef  DEBUG_ARB_LEVEL_CLK_TM
    MM_PRINTSTR("\r\n\r\nt2 = 0x")
    or    a0, t2, zero
    bl     mm_hexserial
    nop
#endif
    li.d     t6, 0x1
//write new delay value
    bl     arb_modify_param
    nop

//do Test and print test result
#ifdef  DEBUG_ARB_LEVEL_CLK_CFG
    MM_PRINTSTR("\r\nThe clk dll configuration is:\r\n")
    bl     enable_ddr_confspace
    nop

    li.d     t1, 0x1         //set print num
    li.d     t7, DDR_MC_CONFIG_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    or      t7, t7, a1
    add.d   t7, t7, 0x8f0   //set start offset
1:
    ld.d      t8, t7, 0x0
    srli.d    a0, t8, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("  ")
    or    a0, t8, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")

    addi.d  t1, t1, -1
    addi.d  t7, t7, 16
    bnez    t1, 1b
    nop

    bl     disable_ddr_confspace
    nop
#endif
    bl     arb_test_mem
    nop
#ifdef  DEBUG_ARB_LEVEL_CLK_TM
    or    t7, a4, zero
    or    t8, a5, zero

    MM_PRINTSTR("\r\nRW Diff 0x")
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop

    MM_PRINTSTR("\r\nRD Diff 0x")
    srli.d    a0, t8, 32
    bl     mm_hexserial
    nop
    or    a0, t8, zero
    bl     mm_hexserial
    nop

    or    a4, t7, zero
    or    a5, t8, zero
#endif
    //process test result, only when the entire byte is correct(0x00) clear fail mark in t3.
    //byte 7
    srli.d    a0, a4, 0x38
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x38
    nor     a0, a0, zero
    and     t3, t3, a0
1:
    //byte 6
    srli.d    a0, a4, 0x30
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x30
    nor     a0, a0, zero
    and     t3, t3, a0
1:
    //byte 5
    srli.d    a0, a4, 0x28
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x28
    nor     a0, a0, zero
    and     t3, t3, a0
1:
    //byte 4
    srli.d    a0, a4, 0x20
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x20
    nor     a0, a0, zero
    and     t3, t3, a0
1:
    //byte 3
    srli.d    a0, a4, 0x18
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x18
    nor     a0, a0, zero
    and     t3, t3, a0
1:
    //byte 2
    srli.d    a0, a4, 0x10
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x10
    nor     a0, a0, zero
    and     t3, t3, a0
1:
    //byte 1
    srli.d    a0, a4, 0x08
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x08
    nor     a0, a0, zero
    and     t3, t3, a0
1:
    //byte 0
    srli.d    a0, a4, 0x0
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x0
    nor     a0, a0, zero
    and     t3, t3, a0
1:
#ifdef  DEBUG_ARB_LEVEL_CLK_TM
    //record RD history in t4, normally, t4 should.d be 0x0 after all these trying
    //byte 7
    srli.d    a0, a5, 0x38
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x38
    nor     a0, a0, zero
    and     t4, t4, a0
1:
    //byte 6
    srli.d    a0, a5, 0x30
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x30
    nor     a0, a0, zero
    and     t4, t4, a0
1:
    //byte 5
    srli.d    a0, a5, 0x28
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x28
    nor     a0, a0, zero
    and     t4, t4, a0
1:
    //byte 4
    srli.d    a0, a5, 0x20
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x20
    nor     a0, a0, zero
    and     t4, t4, a0
1:
    //byte 3
    srli.d    a0, a5, 0x18
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x18
    nor     a0, a0, zero
    and     t4, t4, a0
1:
    //byte 2
    srli.d    a0, a5, 0x10
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x10
    nor     a0, a0, zero
    and     t4, t4, a0
1:
    //byte 1
    srli.d    a0, a5, 0x08
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x08
    nor     a0, a0, zero
    and     t4, t4, a0
1:
    //byte 0
    srli.d    a0, a5, 0x0
    and     a0, a0, 0xff
    bnez    a0, 1f
    nop
    //find a pass
    li.d     a0, 0xff
    slli.d    a0, a0, 0x0
    nor     a0, a0, zero
    and     t4, t4, a0
1:
#endif

//process TM result: translate Byte error info into 1 bit info in each BX_TM_RST of every Byte.
//64 bit BX_TM_RST work as a bit map corresponding to every param value(so the min step interval
//is 2, or there will be not enough space to store TM RST info), the 64 bit can be only part valid(
//step interval > 2).
    li.d     t8, ARB_STORE_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    add.d   t8, t8, a1

    srli.d    t7, t3, 56
    and     t7, t7, 0xff
    beqz    t7, 1f
    nop
    //error detected
    ld.d      a0, t8, B7_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, B7_TM_RST
1:
    srli.d    t7, t3, 48
    and     t7, t7, 0xff
    beqz    t7, 1f
    nop
    //error detected
    ld.d      a0, t8, B6_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, B6_TM_RST
1:
    srli.d    t7, t3, 40
    and     t7, t7, 0xff
    beqz    t7, 1f
    nop
    //error detected
    ld.d      a0, t8, B5_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, B5_TM_RST
1:
    srli.d    t7, t3, 32
    and     t7, t7, 0xff
    beqz    t7, 1f
    nop
    //error detected
    ld.d      a0, t8, B4_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, B4_TM_RST
1:
    srli.d    t7, t3, 24
    and     t7, t7, 0xff
    beqz    t7, 1f
    nop
    //error detected
    ld.d      a0, t8, B3_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, B3_TM_RST
1:
    srli.d    t7, t3, 16
    and     t7, t7, 0xff
    beqz    t7, 1f
    nop
    //error detected
    ld.d      a0, t8, B2_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, B2_TM_RST
1:
    srli.d    t7, t3, 8
    and     t7, t7, 0xff
    beqz    t7, 1f
    nop
    //error detected
    ld.d      a0, t8, B1_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, B1_TM_RST
1:
    srli.d    t7, t3, 0
    and     t7, t7, 0xff
    beqz    t7, 1f
    nop
    //error detected
    ld.d      a0, t8, B0_TM_RST
    or      a0, a0, t0
    st.d      a0, t8, B0_TM_RST
1:
    slli.d    t0, t0, 1

    //check wether delay value exceed max value
    or    a1, s4, zero
    add.d   a2, t2, t5
    beq  a2, a1, 99f;     bge     a2, a1, 11f;99: //check the new delay value whether exceed limitation
    nop
    /** not exceed **/
    or    t2, a2, zero
    b       clklvl_test_one_delay
    nop
11:

#ifdef  DEBUG_ARB_LEVEL_CLK
    li.d     t8, ARB_STORE_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    add.d   t8, t8, a1
    MM_PRINTSTR("\r\nlevel result is:\r\n")
    ld.d      t7, t8, B7_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")
    ld.d      t7, t8, B6_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")
    ld.d      t7, t8, B5_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")
    ld.d      t7, t8, B4_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")
    ld.d      t7, t8, B3_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")
    ld.d      t7, t8, B2_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")
    ld.d      t7, t8, B1_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")
    ld.d      t7, t8, B0_TM_RST
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
#endif
//calculate mid value for each byte lane
/***********
boundary sign: contain at least WINDOW_ZERO_NUM consecutive 0(TM success)
    t0: parse pointer
    t1: BYTE OFFSET, and work as loop control
    t2: parse max position
    t3: BYTE_X_LEVEL_RST
    t4: WINDOW_ZERO_NUM
***********/
    //set t2 max value for each level object
    or    t2, s4, zero
    srli.d    t2, t2, LOG2_STEP

    or    a6, zero, zero
    li.d     t8, ARB_STORE_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    add.d   t8, t8, a1

    li.d     t1, 0x38    //start from byte 7

11: //loop for all byte lanes
    add.d   t7, t8, t1
    ld.d      t3, t7, B0_TM_RST
#ifdef  DEBUG_ARB_LEVEL_CLK
    MM_PRINTSTR("\r\nt3 = 0x")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    or    a0, t3, zero
    bl     mm_hexserial
    nop
#endif
    or    t0, zero, zero
    li.d     t4, WINDOW_ZERO_NUM
12:
    beq  t0, t2, 99f;     bgeu    t0, t2, 3f;99:
    nop
    srli.d    t7, t3, t0
    and     t7, t7, 0x1
    bnez    t7, 1f
    nop
    //find a TM success
    addi.d  t4, t4, -1
    beqz    t4, 2f
    nop
    //continue move
    addi.d  t0, t0, 0x1
    b       12b
    nop
1:  //find a TM fail
    li.d     t4, WINDOW_ZERO_NUM
    //continue move
    addi.d  t0, t0, 0x1
    b       12b
    nop
2:  //window found
    //calculate the MIN boundary
    li.d     a1, WINDOW_ZERO_NUM
    addi.d  a0, t0, 1
    sub.d   a0, a0, a1
    slli.d    a0, a0, LOG2_STEP   //a0 = a0 * 2n
    and     a0, a0, 0xff
    slli.d    a0, a0, t1
    ld.d      a1, t8, GD_MIN
    or      a1, a1, a0
    st.d      a1, t8, GD_MIN
    //move forward to the next Fail to cal the MAX boundary
1:
    addi.d  t0, t0, 0x1
    beq  t0, t2, 99f;     bgeu    t0, t2, 1f;99:
    nop
    srli.d    t7, t3, t0
    and     t7, t7, 0x1
    beqz    t7, 1b  //continue move
    nop
1:
    //find a TM FAIL or reach the max test value
    addi.d  a0, t0, -1
    slli.d    a0, a0, LOG2_STEP   //a0 = a0 * 2n
    and     a0, a0, 0xff
    slli.d    a0, a0, t1
    ld.d      a1, t8, GD_MAX
    or      a1, a1, a0
    st.d      a1, t8, GD_MAX
    b       2f
    nop
3:  //parse to end, CAN NOT find a window
    or      a6, a6, 0x1
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nWrlvl Error: This Byte Window not found.")
    MM_PRINTSTR("\r\nFailed byte is byte: ")
    srli.d    a0, t1, 3
    bl     mm_hexserial
    nop
#endif
2:  //continue for next byte lane
    beqz    t1, 2f
    nop
    add.d   t1, t1, -0x8
    b       11b
    nop
2:  //All byte lane's MIN and MAX value stored or fail to find
    beqz    a6, 1f
    nop
    //some Byte lane can not find a window
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nWrite level failed. Write default value.\r\n")
#endif
    //write standard value mandatory
    //clklvl_delay
    li.d     a0, CLKLVL_DEFAULT_VALUE
    st.d      a0, t8, GD_MID
    b       arb_clklvl_value_caled
    nop
1:
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nMin value: 0x")
    ld.d      t7, t8, GD_MIN
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\nMax value: 0x")
    ld.d      t7, t8, GD_MAX
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
#endif

//calculate mid value for each byte lane
    ld.d      a0, t8, GD_MIN
    ld.d      a1, t8, GD_MAX
    add.d   a0, a0, a1
    //divide a0 by 2 every byte
    srli.d    a0, a0, 1
    li.d     a1, 0x7f7f7f7f7f7f7f7f
    and     a0, a0, a1
    st.d      a0, t8, GD_MID
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nCal Mid value: 0x")
    ld.d      t7, t8, GD_MID
    srli.d    a0, t7, 32
    bl     mm_hexserial
    nop
    or    a0, t7, zero
    bl     mm_hexserial
    nop
#endif

arb_clklvl_value_caled:
    ld.d      t2, t8, GD_MID
#ifdef DEBUG_ARB_LEVEL_CLK
    MM_PRINTSTR("\r\nWrite param and value:\r\nt2 = 0x")
    srli.d    a0, t2, 32
    bl     mm_hexserial
    nop
    or    a0, t2, zero
    bl     mm_hexserial
    nop
#endif
    li.d     t2, 0x2020202020202020
    li.d     t6, 0x1
    bl     arb_write_param
    nop

#ifdef DEBUG_ARB_LEVEL_CLK
    MM_PRINTSTR("\r\nAfter clock leveling. The MC configuration is:\r\n")

    bl     enable_ddr_confspace
    nop

    li.d     t1, DDR_PARAM_NUM
    li.d     t7, DDR_MC_CONFIG_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    or      t7, t7, a1
1:
    ld.d      t3, t7, 0x0
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("  ")
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")

    addi.d  t1, t1, -1
    addi.d  t7, t7, 16
    bnez    t1, 1b
    nop

    bl     disable_ddr_confspace
    nop
#endif
#endif

#include    "ARB_Write_Slice_8_param.S"

    //print final level result
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nAfter ARB level. The MC configuration is:\r\n")
    bl     enable_ddr_confspace
    nop

    li.d     t1, DDR_PARAM_NUM
    li.d     t7, DDR_MC_CONFIG_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    or      t7, t7, a1
1:
    ld.d      t3, t7, 0x0
    and     a0, t7, 0xfff
    bl     mm_hexserial
    nop
    MM_PRINTSTR(":  ")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    MM_PRINTSTR("  ")
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\n")

    addi.d  t1, t1, -1
    addi.d  t7, t7, 16
    bnez    t1, 1b
    nop

    bl     disable_ddr_confspace
    nop
#endif

ARB_level_end:
    bl     arb_test_mem
    nop
    beqz    a4, 2f
    nop
    or    t3, a4, zero
    or    t4, a5, zero
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\n\r\nERROR!!!: ARB Leveling Failed.\r\n")
    MM_PRINTSTR("\r\nRW Diff 0x")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    MM_PRINTSTR("\r\nRD Diff 0x")
    srli.d    a0, t4, 32
    bl     mm_hexserial
    nop
    or    a0, t4, zero
    bl     mm_hexserial
    nop
#endif
#if 0   //seems can not help
    //level fail, delay some time and level again
    li.d     a0, 0x4000000
1:
    addi.d  a0, a0, -1
    bnez    a0, 1b
    nop
    b       ARB_level_begin
    nop
#endif
    //not     t7, zero
    b       arb_level_fail
    nop
2:
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\n\r\nARB Leveling Finished.\r\n")
#endif

    //or    t7, zero, zero

arb_level_fail:

//recover t0~a6,s1~s7
    li.d     a2, ARB_STACK_BASE
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    add.d   a2, a2, a1
    ld.d      s0, a2, 0x0
    ld.d      s1, a2, 0x8
    ld.d      s2, a2, 0x10
    ld.d      s3, a2, 0x18
    ld.d      s4, a2, 0x20
    ld.d      s5, a2, 0x28
    ld.d      s6, a2, 0x30
    ld.d      s7, a2, 0x38
    ld.d      t0, a2, 0x40
    ld.d      t1, a2, 0x48
    ld.d      t2, a2, 0x50
    ld.d      t3, a2, 0x58
    ld.d      t4, a2, 0x60
    ld.d      t5, a2, 0x68
    ld.d      t6, a2, 0x70
    ld.d      t7, a2, 0x78
    ld.d      t8, a2, 0x80
    ld.d      a6, a2, 0x88

/*
 *Unlock Scache 9800?01000000000 ~ 9800?01000001000(4K)
 */
#ifdef  PRINT_MSG
    MM_PRINTSTR("\r\nUnlock Scache Node x--9800?01000000000~4K...\r\n")
#endif
    li.d     a2, LOCK_SCACHE_CONFIG_BASE_ADDR
#ifdef LS3B
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 14
    add.d   a2, a2, a1
#endif
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    or      a2, a2, a1
    st.d      zero, a2, 0x0
    st.d      zero, a2, 0x40
    sync

    //Hit Invalidate the locked address
    li.d     a0, 0x9000001000000000
    GET_ARB_LEVEL_NODE_ID
    slli.d    a1, a1, 44
    or      a0, a0, a1
    li.d     a1, 0x1000
    add.d   a2, a0, a1
1:
    cache   0x11, 0x0(a0)
    cache   0x13, 0x0(a0)

    add.d   a0, a0, 0x20
    blt     a0, a2, 1b
    nop

#ifdef  PRINT_MSG
    MM_PRINTSTR("Unlock Scache Done.\r\n")
#endif

    or    ra, a6, zero
    jirl    zero, ra, 0
    nop

//<<<<<<<<<<<<<<<<<<<<<<<
//child.d function defination

enable_ddr_confspace:
/*
 * enable DDR MC register config space
 * use register: t7
 */
#if 0
    li.d     t7, CHIP_CONFIG_BASE_ADDR
    GET_ARB_LEVEL_NODE_ID
#ifdef LS3B
    and     a1, a1, 0xe
#endif
    slli.d    a1, a1, 44
    or      t7, t7, a1
    li.w      a2, 0x1
    sll     a2, a2, DDR_CONFIG_DISABLE_OFFSET
#ifdef LS3B
    //ODD NODE sll 5
    GET_ARB_LEVEL_NODE_ID
    and     a1, a1, 0x1
    beqz    a1, 1f
    nop
    sll     a2, a2, 5
1:
#endif
    nor     a2, a2, zero
    ld.w      a1, t7, 0x0
    and     a1, a1, a2
    st.w      a1, t7, 0x0
    sync
#endif
	li.d t7, PHYS_TO_UNCACHED(0x1fe00420)
    	li.w a2, 0x100
	nor a2,a2, zero
	ld.w a1, t7, 0x4
    	and     a1, a1, a2
   	st.w      a1, t7, 0x0
    	sync
    jirl    zero, ra, 0
    nop

disable_ddr_confspace:
/*
 * disable DDR MC config reg space
 * use register: t7
 */
#if 0
    li.d     t7, CHIP_CONFIG_BASE_ADDR
    GET_ARB_LEVEL_NODE_ID
#ifdef LS3B
    and     a1, a1, 0xe
#endif
    slli.d    a1, a1, 44
    or      t7, t7, a1
    li.w      a2, 0x1
    sll     a2, a2, DDR_CONFIG_DISABLE_OFFSET
#ifdef LS3B
    //ODD NODE sll 5
    GET_ARB_LEVEL_NODE_ID
    and     a1, a1, 0x1
    beqz    a1, 1f
    nop
    sll     a2, a2, 5
1:
#endif
    ld.w      a1, t7, 0x0
    or      a1, a1, a2
    st.w      a1, t7, 0x0
    sync
#endif
	li.d t7, PHYS_TO_UNCACHED(0x1fe00420)
    	li.w a2, 0x100
	ld.w a1, t7, 0x4
    	or     a1, a1, a2
   	st.w      a1, t7, 0x0
    	sync

    jirl    zero, ra, 0
    nop

#include "ARB_Modify_param_func.S"
#include "ARB_Write_param_func.S"
#include "ARB_TM.S"
//>>>>>>>>>>>>>>>>>>>>>
