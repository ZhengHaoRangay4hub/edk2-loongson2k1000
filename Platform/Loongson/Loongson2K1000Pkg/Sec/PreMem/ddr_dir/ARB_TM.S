/********************
Author: Chen Xinke
Function: Test memory read and write errors
note :  Memory size >= 1G
Usage:  include this file in the start.S, after initialize cache and before copy Pmon Text to the memory;
a5.2    Test address range is auto-configured by msize(use the default window)
        precondition:
        1. default L2-Xbar window(fullmsize ~ fullmsize * 2) must be configured.
v2.0    Support Multi-chip mode memory test and new msize map, Node ID is given by user input.
v2.2    Modify the structure of the program to reduce its size and make it more scalable.
v2.4    Modify code for ARB level use, remove some no use code.
********************/
/***************
note: don't change s0, s2(msize)
use register from caller view: a0~a3, a4,a5

register usage:
t0: test pattern content
t1: current address
t2: address interval
t3: max address
t4,t5: volatile
t6: test pattern base
t7: by subroutine--arb_hexserial64
t8: control print error num(debug use).
a6: loop control
s5: store level byte mask
s6: error bits record
s7: RD error bits record
a4: output result(s6)
a5: output result(s7)
**************/
#include    "ARB_TM.h"

//#define ARB_TM_DBG
#ifdef  ARB_TM_DBG
#define ARB_TM_PRINTSTR(x) \
    .rdata;98: .asciz x; .text; la a0, 98b; bl mm_stringserial; nop
#else
#define ARB_TM_PRINTSTR(x) ;
#endif

#define  ARB_TM_FLUSH_CACHE

/********************************
 * test_mem
 * output:  a4, a5
********************************/
arb_test_mem:

ARB_TM_start:
//save t0~a6,s1~s7
    li.d     a2, MT_STACK_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    or      a2, a2, a1
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
    st.d      ra, a2, 0x90

#ifdef  LEVEL_SPECIFIED_BYTE_LANES
    //give the specified byte lanes directly.
    li.d     s5, LEVEL_BYTES_MASK
#endif
    li.d     s6, 0x0
    li.d     s7, 0x0

    //set TM start addr
    //row + col pin num
    GET_ROW_SIZE
    or    t1, a1, zero
    GET_COL_SIZE
    add.d   t1, t1, a1
    li.d     a0, ROW_COL_UPPER_LIMIT
    sub.d   t1, a0, t1
    //bank addr pin num
    li.d     a0, 0x2
    GET_EIGHT_BANK
    add.d   a0, a0, a1
    add.d   t1, t1, a0
    //data width
    li.d     a0, 0x3
    GET_DIMM_WIDTH
    sub.d   a0, a0, a1
    add.d   t1, t1, a0
    //set 1 rank memsize
    li.d     a0, 0x1
    slli.d    s4, a0, t1
    //for loop control
    srli.d    s4, s4, 0x1

    GET_MC_CS_MAP
    or    s3, a1, zero

ARB_TM_begin:
    beqz    s3, ARB_TM_end
    nop
1:
    and     a1, s3, 0x1
    bnez    a1, 1f
    nop
    srli.d    s3, s3, 1
    b       1b
    nop
1:
    srli.d    s3, s3, 1

    slli.d    s4, s4, 0x1

#ifdef ARB_TM_DBG
    ARB_TM_PRINTSTR("\r\ns4= 0x")
    srli.d    a0, s4, 32
    bl     mm_hexserial
    nop
    or    a0, s4, zero
    bl     mm_hexserial
    nop
    ARB_TM_PRINTSTR("\r\n")
#endif

    ARB_TM_PRINTSTR("\r\nStart Testing Memory...\r\n")

#if 1
    //initialization
    li.d     a6, 0
    //set Test Pattern Base t6 and write content
    li.d     t6, MT_PATTERN_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    or      t6, t6, a1

    li.d     t4, PATTERN_D8_0_0
    st.d      t4, t6, 0x0
    li.d     t4, PATTERN_D8_0_1
    st.d      t4, t6, 0x8
    li.d     t4, PATTERN_D8_0_2
    st.d      t4, t6, 0x10
    li.d     t4, PATTERN_D8_0_3
    st.d      t4, t6, 0x18
    li.d     t4, PATTERN_D8_0_4
    st.d      t4, t6, 0x20
    li.d     t4, PATTERN_D8_0_5
    st.d      t4, t6, 0x28
    li.d     t4, PATTERN_D8_0_6
    st.d      t4, t6, 0x30
    li.d     t4, PATTERN_D8_0_7
    st.d      t4, t6, 0x38

    add.d   t6, t6, 0x40
    li.d     t4, PATTERN_D8_1_0
    st.d      t4, t6, 0x0
    li.d     t4, PATTERN_D8_1_1
    st.d      t4, t6, 0x8
    li.d     t4, PATTERN_D8_1_2
    st.d      t4, t6, 0x10
    li.d     t4, PATTERN_D8_1_3
    st.d      t4, t6, 0x18
    li.d     t4, PATTERN_D8_1_4
    st.d      t4, t6, 0x20
    li.d     t4, PATTERN_D8_1_5
    st.d      t4, t6, 0x28
    li.d     t4, PATTERN_D8_1_6
    st.d      t4, t6, 0x30
    li.d     t4, PATTERN_D8_1_7
    st.d      t4, t6, 0x38

    add.d   t6, t6, 0x40
    li.d     t4, PATTERN_D8_2_0
    st.d      t4, t6, 0x0
    li.d     t4, PATTERN_D8_2_1
    st.d      t4, t6, 0x8
    li.d     t4, PATTERN_D8_2_2
    st.d      t4, t6, 0x10
    li.d     t4, PATTERN_D8_2_3
    st.d      t4, t6, 0x18
    li.d     t4, PATTERN_D8_2_4
    st.d      t4, t6, 0x20
    li.d     t4, PATTERN_D8_2_5
    st.d      t4, t6, 0x28
    li.d     t4, PATTERN_D8_2_6
    st.d      t4, t6, 0x30
    li.d     t4, PATTERN_D8_2_7
    st.d      t4, t6, 0x38

    add.d   t6, t6, 0x40
    li.d     t4, PATTERN_D8_3_0
    st.d      t4, t6, 0x0
    li.d     t4, PATTERN_D8_3_1
    st.d      t4, t6, 0x8
    li.d     t4, PATTERN_D8_3_2
    st.d      t4, t6, 0x10
    li.d     t4, PATTERN_D8_3_3
    st.d      t4, t6, 0x18
    li.d     t4, PATTERN_D8_3_4
    st.d      t4, t6, 0x20
    li.d     t4, PATTERN_D8_3_5
    st.d      t4, t6, 0x28
    li.d     t4, PATTERN_D8_3_6
    st.d      t4, t6, 0x30
    li.d     t4, PATTERN_D8_3_7
    st.d      t4, t6, 0x38

    add.d   t6, t6, 0x40
    li.d     t4, PATTERN_D8_4_0
    st.d      t4, t6, 0x0
    li.d     t4, PATTERN_D8_4_1
    st.d      t4, t6, 0x8
    li.d     t4, PATTERN_D8_4_2
    st.d      t4, t6, 0x10
    li.d     t4, PATTERN_D8_4_3
    st.d      t4, t6, 0x18
    li.d     t4, PATTERN_D8_4_4
    st.d      t4, t6, 0x20
    li.d     t4, PATTERN_D8_4_5
    st.d      t4, t6, 0x28
    li.d     t4, PATTERN_D8_4_6
    st.d      t4, t6, 0x30
    li.d     t4, PATTERN_D8_4_7
    st.d      t4, t6, 0x38

    add.d   t6, t6, 0x40
    li.d     t4, PATTERN_D8_5_0
    st.d      t4, t6, 0x0
    li.d     t4, PATTERN_D8_5_1
    st.d      t4, t6, 0x8
    li.d     t4, PATTERN_D8_5_2
    st.d      t4, t6, 0x10
    li.d     t4, PATTERN_D8_5_3
    st.d      t4, t6, 0x18
    li.d     t4, PATTERN_D8_5_4
    st.d      t4, t6, 0x20
    li.d     t4, PATTERN_D8_5_5
    st.d      t4, t6, 0x28
    li.d     t4, PATTERN_D8_5_6
    st.d      t4, t6, 0x30
    li.d     t4, PATTERN_D8_5_7
    st.d      t4, t6, 0x38

10:
    addi.d  a6, a6, 0x1

    li.d     t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:  //normal code
    nop
    ARB_TM_PRINTSTR("\r\nPattern WalkOnes Test...\r\n")
    //set load content t6 start addr
    li.d     t6, MT_PATTERN_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    or      t6, t6, a1
    //address interval
    li.d     t2, ADDR_INTERVAL
    //set Test Base t1 and Test Limit t3
    GET_TM_UP_ADDR
    GET_TM_MSIZE
    sub.d   t1, t3, a1

    b       2f
    nop
1:
    li.d     t4, 2
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    ARB_TM_PRINTSTR("\r\nPattern WalkInvOnes Test...\r\n")
    //set load content t6 start addr
    li.d     t6, MT_PATTERN_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    or      t6, t6, a1
    add.d   t6, t6, 0x40
    //address interval
    li.d     t2, ADDR_INTERVAL
    //set Test Base t1 and Test Limit t3
    GET_TM_UP_ADDR
    GET_TM_MSIZE
    sub.d   t1, t3, a1
    b       2f
    nop
1:
    li.d     t4, 3
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    ARB_TM_PRINTSTR("\r\nPattern WalkZeros Test...\r\n")
    //set load content t6 start addr
    li.d     t6, MT_PATTERN_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    or      t6, t6, a1
    add.d   t6, t6, 0x80
    //address interval
    li.d     t2, ADDR_INTERVAL
    //set Test Base t1 and Test Limit t3
    GET_TM_UP_ADDR
    GET_TM_MSIZE
    sub.d   t1, t3, a1
    b       2f
    nop
1:
    li.d     t4, 4
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    ARB_TM_PRINTSTR("\r\nPattern WalkSingleOnes Test...\r\n")
    //set load content t6 start addr
    li.d     t6, MT_PATTERN_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    or      t6, t6, a1
    add.d   t6, t6, 0xc0
    //address interval
    li.d     t2, ADDR_INTERVAL
    //set Test Base t1 and Test Limit t3
    GET_TM_UP_ADDR
    GET_TM_MSIZE
    sub.d   t1, t3, a1
    b       2f
    nop
1:
    li.d     t4, 5
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    ARB_TM_PRINTSTR("\r\nPattern Inverse Test...\r\n")
    //set load content t6 start addr
    li.d     t6, MT_PATTERN_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    or      t6, t6, a1
    add.d   t6, t6, 0x100
    //address interval
    li.d     t2, ADDR_INTERVAL
    //set Test Base t1 and Test Limit t3
    GET_TM_UP_ADDR
    GET_TM_MSIZE
    sub.d   t1, t3, a1
    b       2f
    nop
1:
    li.d     t4, 6
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    ARB_TM_PRINTSTR("\r\nPattern Random Test...\r\n")
    //set load content t6 start addr
    li.d     t6, MT_PATTERN_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    or      t6, t6, a1
    add.d   t6, t6, 0x140
    //address interval
    li.d     t2, ADDR_INTERVAL
    //set Test Base t1 and Test Limit t3
    GET_TM_UP_ADDR
    GET_TM_MSIZE
    sub.d   t1, t3, a1
    b       2f
    nop
1:
    //(all the burst inverse Pattern test done)
    b       3f  //go to the end of diff burst test
    nop
2:
    li.d     t8, TM_MAX_ERRORS
#ifdef  ARB_TM_DBG
    ARB_TM_PRINTSTR("Test address range: 0x")
    srli.d    a0, t1, 32
    bl     mm_hexserial
    nop
    or    a0, t1, zero
    bl     mm_hexserial
    nop
    ARB_TM_PRINTSTR("~0x")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    ARB_TM_PRINTSTR("  @@  address interval: 0x")
    or    a0, t2, zero
    bl     mm_hexserial
    nop
    ARB_TM_PRINTSTR("\r\n")
#endif
//write memory
    ld.d      a0, t6, 0x0
    ld.d      a1, t6, 0x8
    ld.d      a2, t6, 0x10
    ld.d      a3, t6, 0x18
    ld.d      a4, t6, 0x20
    ld.d      a5, t6, 0x28
    ld.d      t4, t6, 0x30
    ld.d      t5, t6, 0x38
1:
    st.d      a0, t1, 0x0
    st.d      a1, t1, 0x8
    st.d      a2, t1, 0x10
    st.d      a3, t1, 0x18
    st.d      a4, t1, 0x20
    st.d      a5, t1, 0x28
    st.d      t4, t1, 0x30
    st.d      t5, t1, 0x38
#ifdef  ARB_TM_FLUSH_CACHE
    //hit write back invalidate(D-/S-cache) to memory
    cache   0x15, 0x0(t1)
    cache   0x15, 0x20(t1)
    cache   0x17, 0x0(t1)
    cache   0x17, 0x20(t1)
#endif
#if 0
//note: if we use hit write back + hit invalidate, then rd error occur. why???
    //hit write back(D-/S-cache) to memory
    cache   0x19, 0x0(t1)
    cache   0x19, 0x20(t1)
    cache   0x1b, 0x0(t1)
    cache   0x1b, 0x20(t1)
    //hit invalidate(D-/S-cache)
    cache   0x11, 0x0(t1)
    cache   0x11, 0x20(t1)
    cache   0x13, 0x0(t1)
    cache   0x13, 0x20(t1)
    sync
#endif
    add.d   t1, t1, t2
    bltu    t1, t3, 1b
    nop
    sync
    ARB_TM_PRINTSTR("write done. begin to read and compare...\r\n")
//read memory and compare
    //set Test Base t1
    GET_TM_UP_ADDR
    GET_TM_MSIZE
    sub.d   t1, t3, a1
1:
    ld.d      t0, t6, 0x0
    ld.d      t4, t1, 0x0
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    bl     arb_hexserial64
    nop
#ifdef  ARB_TM_DBG
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
#endif
2:
    ld.d      t0, t6, 0x8
    ld.d      t4, t1, 0x8
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x8 //the arb_hexserial64 will use t1 directly
    bl     arb_hexserial64
    nop
    addi.d  t1, t1, -0x8
#ifdef  ARB_TM_DBG
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
#endif
2:
    ld.d      t0, t6, 0x10
    ld.d      t4, t1, 0x10
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x10 //the arb_hexserial64 will use t1 directly
    bl     arb_hexserial64
    nop
    addi.d  t1, t1, -0x10
#ifdef  ARB_TM_DBG
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
#endif
2:
    ld.d      t0, t6, 0x18
    ld.d      t4, t1, 0x18
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x18 //the arb_hexserial64 will use t1 directly
    bl     arb_hexserial64
    nop
    addi.d  t1, t1, -0x18
#ifdef  ARB_TM_DBG
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
#endif
2:
    ld.d      t0, t6, 0x20
    ld.d      t4, t1, 0x20
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x20 //the arb_hexserial64 will use t1 directly
    bl     arb_hexserial64
    nop
    addi.d  t1, t1, -0x20
#ifdef  ARB_TM_DBG
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
#endif
2:
    ld.d      t0, t6, 0x28
    ld.d      t4, t1, 0x28
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x28 //the arb_hexserial64 will use t1 directly
    bl     arb_hexserial64
    nop
    addi.d  t1, t1, -0x28
#ifdef  ARB_TM_DBG
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
#endif
2:
    ld.d      t0, t6, 0x30
    ld.d      t4, t1, 0x30
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x30 //the arb_hexserial64 will use t1 directly
    bl     arb_hexserial64
    nop
    addi.d  t1, t1, -0x30
#ifdef  ARB_TM_DBG
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
#endif
2:
    ld.d      t0, t6, 0x38
    ld.d      t4, t1, 0x38
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x38 //the arb_hexserial64 will use t1 directly
    bl     arb_hexserial64
    nop
    addi.d  t1, t1, -0x38
#ifdef  ARB_TM_DBG
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
#endif
2:
    add.d   t1, t1, t2
    //check address range
    bltu    t1, t3, 1b
    nop
    ARB_TM_PRINTSTR("Pattern Testing done.\r\n")
    b       10b
    nop
3:
#endif

    b       ARB_TM_begin
    nop

arb_hexserial64:  //pseudo subroutine
/**********************
input:  t1: read address(read only)
        t0: expected data(read only)
        t4: read data
use reg:t5, t7
***********************/
    or    t7, ra, zero
    xor     a0, t0, t4
    or      s6, s6, a0
#ifdef  ARB_TM_DBG
    addi.d  t8, t8, -0x1
#endif
    /* reread the wrong bytes */
#if 1
#ifdef  ARB_TM_FLUSH_CACHE
    //Hit Invalidate the Primary D-cache and Second cache.
    //ARB_TM_PRINTSTR("\r\nInvalidate Primary D-cache and S-cache.\r\n")
    cache   0x11, 0x0(t1)
    cache   0x13, 0x0(t1)
    sync
    or    t5, t1, zero
#else
    li.d     t5, 0xf7ffffffffffffff
    and     t5, t1, t5
#endif
#else
    or    t5, t1, zero
#endif
    ld.d      t5, t5, 0
    nop
#ifdef  ARB_TM_DBG
    ARB_TM_PRINTSTR("addr 0x")
    srli.d    a0, t1, 32
    bl     mm_hexserial
    nop
    or    a0, t1, zero
    bl     mm_hexserial
    nop
    ARB_TM_PRINTSTR(" expected: ")
    srli.d    a0, t0, 32
    bl     mm_hexserial
    nop
    or    a0, t0, zero
    bl     mm_hexserial
    nop
    ARB_TM_PRINTSTR(" read: ")
    srli.d    a0, t4, 32
    bl     mm_hexserial
    nop
    or    a0, t4, zero
    bl     mm_hexserial
    nop
    ARB_TM_PRINTSTR(" reread: ")
    srli.d    a0, t5, 32
    bl     mm_hexserial
    nop
    or    a0, t5, zero
    bl     mm_hexserial
    nop
#endif
    /* if the reread value differs the first read, print mark */
    xor     a0, t4, t5
    beqz    a0, 2f
    nop
    //Mark Read diff detected
    or      s7, s7, a0
    ARB_TM_PRINTSTR("  DDD")
    //---------------------
2:
    ARB_TM_PRINTSTR("\r\n")
    jirl    zero, t7, 0
    nop

ARB_TM_end:
#ifdef  LEVEL_SPECIFIED_BYTE_LANES
    and     s6, s6, s5
    and     s7, s7, s5
#endif
#if 0
//old.d code
    li.d     a4, 0x0
    beqz    s6, 1f
    nop
    //s6 != 0, set error mark
    li.d     a4, 0x1
1:
#else
    or    a4, s6, zero
    or    a5, s7, zero
#endif
//resume s1~s7, t1~a6
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    li.d     a2, MT_STACK_BASE
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
    ld.d      ra, a2, 0x90

    jirl    zero, ra, 0
    nop
