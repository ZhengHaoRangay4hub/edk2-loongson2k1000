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
v2.4    Modify code for better user interface and flexible use.
********************/
/***************
use register: s1, s4, t8, a0~a3, a4~a5
note: don't change s0, s1, s2(msize)
 s1:
    [63:62]: NODE_ID
    [61:60]: CORE_ID
    [47: 0]: START_ADDR(offset on 0x9000000000000000)
t0: test pattern content
t1: current address
t2: address interval
t3: max address
t4,t5: volatile
t6: test pattern base
t7: by subroutine--hexserial64_1
t8: error counter---used to control the max detected error number
a6: loop control
s4: input param--t1
    bit[ 0]: 1: read level; 0: write level;
    bit[ 8]: 0: macro tune; 1: micro tune;
s5: store level byte mask
s6: error bits record
s7: RD error bits record
a4: output result
**************/
#include    "Test_Mem.h"

#define TM_DBG
#ifdef  TM_DBG
#define	TM_PRINTSTR(x) \
	.section .rodata;98: .asciz x; .text; GET_DISPRINT_BIT; bnez a1, 97f; nop; la a0, 98b; bl mm_stringserial; nop; 97:
#else
#define	TM_PRINTSTR(x) ;
#endif

#if 0
//call example
#if 1
    TM_PRINTSTR("\r\nPlease input TM param(0xf: skip): ")
    bl     inputaddress
    nop
    or    t1, a4, zero
    and     a4, a4, 0xf
    li.d     a1, 0x1
    beq  a4, a1, 99f;     bge     a4, a1, 1f;99:
    nop
#else
    li.d     t1, 0x01
#endif
    li.d     s1, 0x0000000080000000  //NODE 0, start from 0x80000000
    bl     test_mem
    nop
    beqz    a4, 1f
    nop
    TM_PRINTSTR("\r\n Error found!! \r\n")
#if 1
2:
    b       2b
    nop
#endif
1:
#endif

    b       RL_end
    nop

/********************************
 * test_mem
 * input:   s1, t1
 s1:
    [63:62]: NODE_ID
    [61:60]: CORE_ID
    [55:48]: Test addr size(x128M)
    [43: 0]: START_ADDR(offset on 0x9000000000000000)
 t1:
   bit[ 0]: 1: read level; 0: write level;
   bit[ 4]: 0: macro tune; 1: micro tune;
   bit[11: 8]: byte to be leveled
   bit[12]: 1: don't print; 0: print message;
 * output:  a4
    0: no error
    1: error
********************************/
test_mem:
    or    t8, ra, zero
    or    s4, t1, zero

TM_start:
#ifdef  TM_DBG
    GET_DISPRINT_BIT
    bnez    a1, 88f
    nop
    TM_PRINTSTR("\r\nNODE ID:")
    GET_TM_NODE_ID_a1
    or    a0, a1, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("    CORE ID:")
    GET_TM_CORE_ID_a1
    or    a0, a1, zero
    bl     mm_hexserial
    nop
88:
#endif
/*
 *Lock Scache 9800?00?00000000 ~ 9800?00?00001000(4K)
 *4 core use corresponding lock window
 */
    TM_PRINTSTR("\r\nLock Scache Node x--9800?00?00000000~4K...\r\n")
    li.d     a2, LOCK_SCACHE_CONFIG_BASE_ADDR
    GET_TM_CORE_ID_a1
    slli.d    a1, a1, 3
    add.d   a2, a2, a1
#ifdef LS3B
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 14
    add.d   a2, a2, a1
#endif
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    or      a2, a2, a1
    li.d     a3, 0x0000fffffffff000
    st.d      a3, a2, 0x40
    li.d     a3, 0x8000000000000000
    or      a3, a3, a1
    GET_TM_START_ADDR
    add.d   a3, a3, a1
    st.d      a3, a2, 0x0
#if 0
    or    a0, a2, zero
    bl     mm_hexserial
    nop
#endif
    TM_PRINTSTR("Lock Scache Done.\r\n")
//save t0~a6,s1~s7
    li.d     a2, MT_STACK_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   a2, a2, a1
    GET_TM_START_ADDR
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

#ifdef  LEVEL_SPECIFIED_BYTE_LANES
#ifdef  LEVEL_ONE_BYTE
    li.d     a2, 0x700
    and     a2, t1, a2
    srli.d    a2, a2, 5   //a2>>8,and<<3(*8)
    li.d     a1, 0xff
    slli.d    s5, a1, a2
#else
    //give the specified byte lanes directly.
    li.d     s5, LEVEL_BYTES_MASK
#endif
#endif
    li.d     s6, 0x0
    li.d     s7, 0x0

	TM_PRINTSTR("\r\nStart Testing Memory...\r\n")

#if 0
    //Test whether the addr_pins,column_size,bank,rank param right.
	TM_PRINTSTR("\r\nAddress Stuck Testing all space...\r\n")
    //set t1 to Test Base
    li.d     t1, MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
    //set test limit t3
    GET_TM_MSIZE
    add.d   t3, t1, a1
    li.d     a1, 0x100000    //t3-=1M  because Test Base start from Base Window + 1M
    sub.d   t3, t3, a1
#ifdef   PRINT_LESS_ERROR
    li.d     t8, TM_MAX_RPT_ERRORS
#endif
#ifdef  TM_DBG
    GET_DISPRINT_BIT
    bnez    a1, 88f
    nop
    TM_PRINTSTR("Test address range: 0x")
    srli.d    a0, t1, 32
    bl     mm_hexserial
    nop
    or    a0, t1, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("~0x")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("\r\n")
88:
#endif
    //write memory
1:
    addi.d  a0, t1, 0x8
    addi.d  a1, t1, 0x10
    addi.d  a2, t1, 0x18
    st.d      t1, t1, 0x0
    st.d      a0, a0, 0x0
    st.d      a1, a1, 0x0
    st.d      a2, a2, 0x0
    addi.d  t1, t1, 0x200
    bltu 	t1, t3, 1b
	nop
    dbar 0
	TM_PRINTSTR("write done...\r\n")
//read memory and compare
    li.d     t1, MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
1:
    ld.d	    t4, t1, 0x0
    or    t0, t1, zero
    beq     t4, t0, 2f
    nop
    //error detected!!! print address, expected data and read data
    bl     hexserial64_1
    nop
#ifdef   PRINT_LESS_ERROR
    bltz    t8, 3f  //detect enough errors, go to next test
    nop
#endif
2:
    addi.d  t1, t1, 0x200
    bltu 	t1, t3, 1b
	nop
	TM_PRINTSTR("Stuck Testing done!\r\n")
3:
#endif
#if 0
	TM_PRINTSTR("Uncached Address Stuck Testing...\r\n")
//debug fatal errors
//write memory
    //set t1 to Test Base
    //use uncached address space here
	li.d 	t1, UNCACHED_MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
#ifdef   PRINT_LESS_ERROR
    li.d     t8, TM_MAX_RPT_ERRORS
#endif
    li.d     t3, 128  //loop counter
1:
    st.d      t1, t1, 0x0
    nop
    addi.d  t1, t1, 0x8
    addi.d  t3, t3, -1
    bnez 	t3, 1b
	nop
    dbar 0
	TM_PRINTSTR("write done...\r\n")
//read memory and compare
	li.d 	t1, UNCACHED_MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
    li.d     t3, 128  //loop counter
1:
    ld.d	    t4, t1, 0x0
    or    t0, t1, zero
    beq     t4, t0, 2f
    nop
    //error detected!!! print address, expected data and read data
    bl     hexserial64_1
    nop
#ifdef   PRINT_LESS_ERROR
    bltz    t8, 20f  //detect enough errors, go to next test
    nop
#endif
2:
    addi.d  t1, t1, 0x8
    addi.d  t3, t3, -1
    bnez 	t3, 1b
	nop
	TM_PRINTSTR("Stuck Testing done!\r\n")
20:
#endif
//-------------------
//pattern Diff Burst Test
#if 0
    //initialization
    li.d     a6, 0
    //set Test Pattern Base t6
    li.d     t6, MT_PATTERN_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t6, t6, a1
    GET_TM_START_ADDR
    add.d   t6, t6, a1
/*****************
* loop control
* a6:
* 1~16: Just0,Just1 set
* 17~32%16  Justb5, Just4a
* 33~48%32  JustA, Just5
*******************/
10:
    addi.d  a6, a6, 0x1
1:
    li.d     t4, 16
#ifndef REDUCED_MEM_TEST
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:  //normal code
#else
    beq  a6, t4, 99f;     bgeu    a6, t4, 3f;99:  //reduced test
#endif
    nop
    TM_PRINTSTR("\r\nPattern DB_0 Test-----\r\n")
    //address interval
    li.d     t2, 0x100
    //set Test Base t1 and Test Limit t3
    li.d     t1, MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
    GET_TM_MSIZE
    //reduce TM size for this test
    srli.d    a1, a1, 2
    GET_MICRO_TUNE
    bnez    a2, 21f
    nop
    srli.d    a1, a1, MACRO_SCALE
21:
    add.d   t3, t1, a1
    li.d     a1, 0x100000    //t3-=1M  because Test Base start from Base Window + 1M
    sub.d   t3, t3, a1
    li.d     t4, 0
    li.d     t0, PATTERN_DB_0_0
    nor     t5, t0, zero
    b       2f
    nop
1:
    li.d     t4, 32
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    TM_PRINTSTR("\r\nPattern DB_1 Test-----\r\n")
    //address interval
    li.d     t2, 0x20
    //set Test Base t1 and Test Limit t3
    li.d     t1, MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
    GET_TM_MSIZE
    srli.d    a1, a1, 3
    GET_MICRO_TUNE
    bnez    a2, 21f
    nop
    srli.d    a1, a1, MACRO_SCALE
21:
    add.d   t3, t1, a1  //t3 = t1 + fullmsize/8
    li.d     a1, 0x100000    //t3-=1M  because Test Base start from Base Window + 1M
    sub.d   t3, t3, a1
    li.d     t4, 16
    li.d     t0, PATTERN_DB_1_0
    nor     t5, t0, zero
    b       2f
    nop
1:
    li.d     t4, 48
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    TM_PRINTSTR("\r\nPattern DB_2 Test-----\r\n")
    //address interval
    li.d     t2, 0x20
    //set Test Base t1 and Test Limit t3
    li.d     t1, MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
    GET_TM_MSIZE
    srli.d    a1, a1, 3
    GET_MICRO_TUNE
    bnez    a2, 21f
    nop
    srli.d    a1, a1, MACRO_SCALE
21:
    add.d   t3, t1, a1  //t3 = t1 + fullmsize/8
    li.d     a1, 0x100000    //t3-=1M  because Test Base start from Base Window + 1M
    sub.d   t3, t3, a1
    li.d     t4, 32
    li.d     t0, PATTERN_DB_2_0
    nor     t5, t0, zero
    b       2f
    nop
1:
    li.d     t4, 64
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    TM_PRINTSTR("\r\nPattern DB_3 Test-----\r\n")
    //address interval
    li.d     t2, 0x20
    //set Test Base t1 and Test Limit t3
    li.d     t1, MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
    GET_TM_MSIZE
    srli.d    a1, a1, 3
    GET_MICRO_TUNE
    bnez    a2, 21f
    nop
    srli.d    a1, a1, MACRO_SCALE
21:
    add.d   t3, t1, a1  //t3 = t1 + fullmsize/8
    li.d     a1, 0x100000    //t3-=1M  because Test Base start from Base Window + 1M
    sub.d   t3, t3, a1
    li.d     t4, 48
    li.d     t0, PATTERN_DB_3_0
    nor     t5, t0, zero
    b       2f
    nop
1:
    // a6 > 64 (all the burst inverse Pattern test done)
    b       3f  //go to the end of diff burst test
    nop
2:
    addi.d  t4, t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6%16 == 1
#ifdef  TM_DBG
    GET_DISPRINT_BIT
    bnez    a1, 88f
    nop
    TM_PRINTSTR("Test address range: 0x")
    srli.d    a0, t1, 32
    bl     mm_hexserial
    nop
    or    a0, t1, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("~0x")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("  @@  address interval: 0x")
    or    a0, t2, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("\r\n")
88:
#endif
    TM_PRINTSTR("Pattern 0000 ....\r\n")
    st.d      t0, t6, 0x0
    st.d      t0, t6, 0x8
    st.d      t0, t6, 0x10
    st.d      t0, t6, 0x18
    b       2f
    nop
1:
    addi.d  t4, t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6%16 == 2
    TM_PRINTSTR("Pattern 0001 ....\r\n")
    st.d      t0, t6, 0x0
    st.d      t0, t6, 0x8
    st.d      t0, t6, 0x10
    st.d      t5, t6, 0x18
    b       2f
    nop
1:
    addi.d t4, t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6%16 == 3
    TM_PRINTSTR("Pattern 0010 ....\r\n")
    st.d      t0, t6, 0x0
    st.d      t0, t6, 0x8
    st.d      t5, t6, 0x10
    st.d      t0, t6, 0x18
    b       2f
    nop
1:
    addi.d t4, t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6%16 == 4
    TM_PRINTSTR("Pattern 0011 ....\r\n")
    st.d      t0, t6, 0x0
    st.d      t0, t6, 0x8
    st.d      t5, t6, 0x10
    st.d      t5, t6, 0x18
    b       2f
    nop
1:
    addi.d  t4, t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6%16 == 5
    TM_PRINTSTR("Pattern 0100 ....\r\n")
    st.d      t0, t6, 0x0
    st.d      t5, t6, 0x8
    st.d      t0, t6, 0x10
    st.d      t0, t6, 0x18
    b       2f
    nop
1:
    addi.d  t4, t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6%16 == 6
    TM_PRINTSTR("Pattern 0101 ....\r\n")
    st.d      t0, t6, 0x0
    st.d      t5, t6, 0x8
    st.d      t0, t6, 0x10
    st.d      t5, t6, 0x18
    b       2f
    nop
1:
    addi.d  t4, t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6%16 == 7
    TM_PRINTSTR("Pattern 0110 ....\r\n")
    st.d      t0, t6, 0x0
    st.d      t5, t6, 0x8
    st.d      t5, t6, 0x10
    st.d      t0, t6, 0x18
    b       2f
    nop
1:
    addi.d  t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6%16 == 8
    TM_PRINTSTR("Pattern 0111 ....\r\n")
    st.d      t0, t6, 0x0
    st.d      t5, t6, 0x8
    st.d      t5, t6, 0x10
    st.d      t5, t6, 0x18
    b       2f
    nop
1:
    addi.d  t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6%16 == 9
    TM_PRINTSTR("Pattern 1000 ....\r\n")
    st.d      t5, t6, 0x0
    st.d      t0, t6, 0x8
    st.d      t0, t6, 0x10
    st.d      t0, t6, 0x18
    b       2f
    nop
1:
    addi.d  t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6%16 == 10
    TM_PRINTSTR("Pattern 1001 ....\r\n")
    st.d      t5, t6, 0x0
    st.d      t0, t6, 0x8
    st.d      t0, t6, 0x10
    st.d      t5, t6, 0x18
    b       2f
    nop
1:
    addi.d  t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6%16 == 11
    TM_PRINTSTR("Pattern 1010 ....\r\n")
    st.d      t5, t6, 0x0
    st.d      t0, t6, 0x8
    st.d      t5, t6, 0x10
    st.d      t0, t6, 0x18
    b       2f
    nop
1:
    addi.d  t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6%16 == 12
    TM_PRINTSTR("Pattern 1011 ....\r\n")
    st.d      t5, t6, 0x0
    st.d      t0, t6, 0x8
    st.d      t5, t6, 0x10
    st.d      t5, t6, 0x18
    b       2f
    nop
1:
    addi.d  t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6%16 == 13
    TM_PRINTSTR("Pattern 1100 ....\r\n")
    st.d      t5, t6, 0x0
    st.d      t5, t6, 0x8
    st.d      t0, t6, 0x10
    st.d      t0, t6, 0x18
    b       2f
    nop
1:
    addi.d  t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6%16 == 14
    TM_PRINTSTR("Pattern 1101 ....\r\n")
    st.d      t5, t6, 0x0
    st.d      t5, t6, 0x8
    st.d      t0, t6, 0x10
    st.d      t5, t6, 0x18
    b       2f
    nop
1:
    addi.d  t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6%16 == 15
    TM_PRINTSTR("Pattern 1110 ....\r\n")
    st.d      t5, t6, 0x0
    st.d      t5, t6, 0x8
    st.d      t5, t6, 0x10
    st.d      t0, t6, 0x18
    b       2f
    nop
1:
    addi.d  t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6%16 == 16
    TM_PRINTSTR("Pattern 1111 ....\r\n")
    st.d      t5, t6, 0x0
    st.d      t5, t6, 0x8
    st.d      t5, t6, 0x10
    st.d      t5, t6, 0x18
    b       2f
    nop
2:
    li.d     t8, TM_MAX_RPT_ERRORS
//write memory
    ld.d      a0, t6, 0x0
    ld.d      a1, t6, 0x8
    ld.d      a2, t6, 0x10
    ld.d      a3, t6, 0x18
1:
    st.d      a0, t1, 0x0
    st.d      a1, t1, 0x8
    st.d      a2, t1, 0x10
    st.d      a3, t1, 0x18
    add.d   t1, t1, t2
    bltu    t1, t3, 1b
    nop
    dbar 0
	TM_PRINTSTR("write done. begin to read and compare...\r\n")
//read memory and compare
    //set Test Base t1
    li.d     t1, MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
1:
    ld.d      t0, t6, 0x0
    ld.d      t4, t1, 0x0
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    bl     hexserial64_1
    nop
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    ld.d      t0, t6, 0x8
    ld.d      t4, t1, 0x8
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x8 //the hexserial64_1 will use t1 directly
    bl     hexserial64_1
    nop
    addi.d  t1, t1, -0x8
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    ld.d      t0, t6, 0x10
    ld.d      t4, t1, 0x10
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x10 //the hexserial64_1 will use t1 directly
    bl     hexserial64_1
    nop
    addi.d  t1, t1, -0x10
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    ld.d      t0, t6, 0x18
    ld.d      t4, t1, 0x18
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x18 //the hexserial64_1 will use t1 directly
    bl     hexserial64_1
    nop
    addi.d  t1, t1, -0x18
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    add.d   t1, t1, t2
    //check address range
    bltu    t1, t3, 1b
    nop
    TM_PRINTSTR("Pattern Testing done.\r\n")
    b       10b
    nop
3:
#endif
#if 1
    //initialization
    li.d     a6, 0
    //set Test Pattern Base t6
    li.d     t6, MT_PATTERN_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t6, t6, a1
    GET_TM_START_ADDR
    add.d   t6, t6, a1
/*****************
* loop control
* a6:
*******************/
10:
    addi.d  a6, a6, 0x1
1:
    li.d     t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:  //normal code
    nop
    TM_PRINTSTR("\r\nPattern WalkOnes Test...\r\n")
    //address interval
    li.d     t2, 0x40
    //set Test Base t1 and Test Limit t3
    li.d     t1, MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
    GET_TM_MSIZE
    srli.d    a1, a1, 0
    GET_MICRO_TUNE
    bnez    a2, 21f
    nop
    srli.d    a1, a1, MACRO_SCALE
21:
    add.d   t3, t1, a1
    li.d     a1, 0x100000    //t3-=1M  because Test Base start from Base Window + 1M
    sub.d   t3, t3, a1

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
    b       2f
    nop
1:
    li.d     t4, 2
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    TM_PRINTSTR("\r\nPattern WalkInvOnes Test...\r\n")
    //address interval
    li.d     t2, 0x40
    //set Test Base t1 and Test Limit t3
    li.d     t1, MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
    GET_TM_MSIZE
    srli.d    a1, a1, 0
    GET_MICRO_TUNE
    bnez    a2, 21f
    nop
    srli.d    a1, a1, MACRO_SCALE
21:
    add.d   t3, t1, a1
    li.d     a1, 0x100000    //t3-=1M  because Test Base start from Base Window + 1M
    sub.d   t3, t3, a1

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
    b       2f
    nop
1:
    li.d     t4, 3
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    TM_PRINTSTR("\r\nPattern WalkZeros Test...\r\n")
    //address interval
    li.d     t2, 0x40
    //set Test Base t1 and Test Limit t3
    li.d     t1, MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
    GET_TM_MSIZE
    srli.d    a1, a1, 0
    GET_MICRO_TUNE
    bnez    a2, 21f
    nop
    srli.d    a1, a1, MACRO_SCALE
21:
    add.d   t3, t1, a1
    li.d     a1, 0x100000    //t3-=1M  because Test Base start from Base Window + 1M
    sub.d   t3, t3, a1

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
    b       2f
    nop
1:
    li.d     t4, 4
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    TM_PRINTSTR("\r\nPattern WalkSingleOnes Test...\r\n")
    //address interval
    li.d     t2, 0x40
    //set Test Base t1 and Test Limit t3
    li.d     t1, MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
    GET_TM_MSIZE
    srli.d    a1, a1, 0
    GET_MICRO_TUNE
    bnez    a2, 21f
    nop
    srli.d    a1, a1, MACRO_SCALE
21:
    add.d   t3, t1, a1
    li.d     a1, 0x100000    //t3-=1M  because Test Base start from Base Window + 1M
    sub.d   t3, t3, a1

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
    b       2f
    nop
1:
    // a6 > 4 (all the burst inverse Pattern test done)
    b       3f  //go to the end of diff burst test
    nop
2:
    li.d     t8, TM_MAX_RPT_ERRORS
#ifdef  TM_DBG
    GET_DISPRINT_BIT
    bnez    a1, 88f
    nop
    TM_PRINTSTR("Test address range: 0x")
    srli.d    a0, t1, 32
    bl     mm_hexserial
    nop
    or    a0, t1, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("~0x")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("  @@  address interval: 0x")
    or    a0, t2, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("\r\n")
88:
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

    add.d   t1, t1, t2
    bltu    t1, t3, 1b
    nop
    dbar 0
	TM_PRINTSTR("write done. begin to read and compare...\r\n")
//read memory and compare
    //set Test Base t1
    li.d     t1, MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
1:
    ld.d      t0, t6, 0x0
    ld.d      t4, t1, 0x0
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    bl     hexserial64_1
    nop
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    ld.d      t0, t6, 0x8
    ld.d      t4, t1, 0x8
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x8 //the hexserial64_1 will use t1 directly
    bl     hexserial64_1
    nop
    addi.d  t1, t1, -0x8
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    ld.d      t0, t6, 0x10
    ld.d      t4, t1, 0x10
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x10 //the hexserial64_1 will use t1 directly
    bl     hexserial64_1
    nop
    addi.d  t1, t1, -0x10
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    ld.d      t0, t6, 0x18
    ld.d      t4, t1, 0x18
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x18 //the hexserial64_1 will use t1 directly
    bl     hexserial64_1
    nop
    addi.d  t1, t1, -0x18
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    ld.d      t0, t6, 0x20
    ld.d      t4, t1, 0x20
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x20 //the hexserial64_1 will use t1 directly
    bl     hexserial64_1
    nop
    addi.d  t1, t1, -0x20
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    ld.d      t0, t6, 0x28
    ld.d      t4, t1, 0x28
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x28 //the hexserial64_1 will use t1 directly
    bl     hexserial64_1
    nop
    addi.d  t1, t1, -0x28
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    ld.d      t0, t6, 0x30
    ld.d      t4, t1, 0x30
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x30 //the hexserial64_1 will use t1 directly
    bl     hexserial64_1
    nop
    addi.d  t1, t1, -0x30
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    ld.d      t0, t6, 0x38
    ld.d      t4, t1, 0x38
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x38 //the hexserial64_1 will use t1 directly
    bl     hexserial64_1
    nop
    addi.d  t1, t1, -0x38
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    add.d   t1, t1, t2
    //check address range
    bltu    t1, t3, 1b
    nop
    TM_PRINTSTR("Pattern Testing done.\r\n")
    b       10b
    nop
3:
#endif
//pattern JustX Test
#ifndef REDUCED_MEM_TEST
    //initialization
    li.d     a6, 0
    //address interval
    li.d     t2, 0x10
    //set Test Base t1 and Test Limit t3
    li.d     t1, MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
    GET_TM_MSIZE
    srli.d    a1, a1, 2
    GET_MICRO_TUNE
    bnez    a2, 21f
    nop
    srli.d    a1, a1, MACRO_SCALE
21:
    add.d   t3, t1, a1
    li.d     a1, 0x100000    //t3-=1M  because Test Base start from Base Window + 1M
    sub.d   t3, t3, a1
10:
    //loop control
    addi.d  a6, a6, 0x1
1:
    li.d     t4, 1
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6 == 1
    TM_PRINTSTR("\r\nPattern JustA Test...\r\n")
    li.d     t0, PATTERN_JUSTA
    b       2f
    nop
1:
    li.d     t4, 2
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6 == 2
    TM_PRINTSTR("\r\nPattern Just5 Test...\r\n")
    li.d     t0, PATTERN_JUST5
    b       2f
    nop
1:
    li.d     t4, 3
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6 == 3
    TM_PRINTSTR("\r\nPattern JustFiveA Test...\r\n")
    li.d     t0, PATTERN_FiveA
    b       2f
    nop
1:
    li.d     t4, 4
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6 == 4
    TM_PRINTSTR("\r\nPattern JustZeroOne Test...\r\n")
    li.d     t0, PATTERN_ZEROONE
    b       2f
    nop
1:
    li.d     t4, 5
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6 == 5
    TM_PRINTSTR("\r\nPattern JustL8b10b-16 Test...\r\n")
    li.d     t0, PATTERN_L8b10b
    b       2f
    nop
1:
    li.d     t4, 6
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6 == 6
    TM_PRINTSTR("\r\nPattern JustS8b10b-b5 Test...\r\n")
    li.d     t0, PATTERN_S8b10b
    b       2f
    nop
1:
    li.d     t4, 7
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6 == 7
    TM_PRINTSTR("\r\nPattern JustFive7 Test...\r\n")
    li.d     t0, PATTERN_Five7
    b       2f
    nop
1:
    li.d     t4, 8
    beq  a6, t4, 99f;     bgeu    a6, t4, 1f;99:
    nop
    //a6 == 8
    TM_PRINTSTR("\r\nPattern JustZero2fd Test...\r\n")
    li.d     t0, PATTERN_Zero2fd
    b       2f
    nop
1:
    // a6 > 8 (all the JustX Pattern test done)
    b       3f  //go to the end of this loop
    nop
2:
    li.d     t8, TM_MAX_RPT_ERRORS
    //set Test Base t1
    li.d     t1, MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
#ifdef  TM_DBG
    GET_DISPRINT_BIT
    bnez    a1, 88f
    nop
    TM_PRINTSTR("Test address range: 0x")
    srli.d    a0, t1, 32
    bl     mm_hexserial
    nop
    or    a0, t1, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("~0x")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("  @@  address interval: 0x")
    or    a0, t2, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("\r\n")
88:
#endif
//write memory
1:
    st.d      t0, t1, 0x0
    st.d      t0, t1, 0x8
    add.d   t1, t1, t2
    bltu    t1, t3, 1b
    nop
    dbar 0
	TM_PRINTSTR("write done. begin to read and compare...\r\n")
//read memory and compare
    //set Test Base t1
    li.d     t1, MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
1:
    ld.d      t4, t1, 0x0
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    bl     hexserial64_1
    nop
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    ld.d      t4, t1, 0x8
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x8 //the hexserial64_1 will use t1 directly
    bl     hexserial64_1
    nop
    addi.d  t1, t1, -0x8
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    add.d   t1, t1, t2
    //check address range
    bltu    t1, t3, 1b
    nop
    TM_PRINTSTR("Pattern Testing done.\r\n")
    b       10b
    nop
3:
#endif

TM_end:
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
    li.d     a2, MT_STACK_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   a2, a2, a1
    GET_TM_START_ADDR
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

    or    t7, a4, zero
    or    t6, a5, zero
/*
 *Unlock Scache 9800?00000000000 ~ 9800?00000001000(4K)
 */
    TM_PRINTSTR("\r\nUnlock Scache Node x--9800?00000000000~4K...\r\n")

    li.d     a2, LOCK_SCACHE_CONFIG_BASE_ADDR
    GET_TM_CORE_ID_a1
    slli.d    a1, a1, 3
    add.d   a2, a2, a1
#ifdef LS3B
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 14
    add.d   a2, a2, a1
#endif
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    or      a2, a2, a1
    st.d      zero, a2, 0x0
    st.d      zero, a2, 0x40
    dbar 0

    //Hit Invalidate the locked address
    li.d     a0, 0x9000000000000000
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    or      a0, a0, a1
    GET_TM_START_ADDR
    add.d   a0, a0, a1
    li.d     a1, 0x1000
    add.d   a2, a0, a1
1:
    cacop   0x13, a0, 0
//    cache   0x11, 0x0(a0)
//    cache   0x13, 0x0(a0)

    addi.d   a0, a0, 0x20
    blt     a0, a2, 1b
    nop
    TM_PRINTSTR("Unlock Scache Done.\r\n")

    or    a4, t7, zero
    or    a5, t6, zero
    jirl    zero, t8, 0
    nop
//===================================

/**********************
* input:
    s1: NODE ID, Test mem size, Test start addr
    t0: write content
    t1:
**********************/

simple_test_mem:
    or    t8, ra, zero
    or    s4, t1, zero

	TM_PRINTSTR("\r\nStart simple test mem...\r\n")
    //set Test Base t1 and Test Limit t3
    li.d     t1, SIMPLE_TM_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
    GET_TM_MSIZE
    add.d   t3, t1, a1

	//TM_PRINTSTR("\r\nStart write data to Memory...\r\n")
    //address interval
    li.d     t2, 0x20
    //set loop times
    li.d     a6, TMF_PWRLOOP
2:
    addi.d  a6, a6, -1
    or    t6, t1, zero
1:
    st.d      t0, t6, 0x0
    nor     t0, t0, zero
    st.d      t0, t6, 0x8
    nor     t0, t0, zero
    st.d      t0, t6, 0x10
    nor     t0, t0, zero
    st.d      t0, t6, 0x18
    nor     t0, t0, zero

    add.d   t6, t6, t2
    bltu    t6, t3, 1b
    nop
    bnez    a6, 2b
    nop
	//TM_PRINTSTR("Data write done...\r\n")

    //TM_PRINTSTR("\r\nStart Read Memory...\r\n")
    //address interval
    li.d     t2, 0x20
    //set loop times
    li.d     a6, TMF_PRDLOOP
20:
    addi.d  a6, a6, -1
    //set Test Base t1
    li.d     t1, SIMPLE_TM_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
10:
    ld.d      t4, t1, 0x0
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    bl     hexserial64_1
    nop
2:
    nor     t0, t0, zero
    ld.d      t4, t1, 0x8
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x8 //the hexserial64_1 will use t1 directly
    bl     hexserial64_1
    nop
    addi.d  t1, t1, -0x8
2:
    nor     t0, t0, zero
    ld.d      t4, t1, 0x10
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x10 //the hexserial64_1 will use t1 directly
    bl     hexserial64_1
    nop
    addi.d  t1, t1, -0x10
2:
    nor     t0, t0, zero
    ld.d      t4, t1, 0x18
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x18 //the hexserial64_1 will use t1 directly
    bl     hexserial64_1
    nop
    addi.d  t1, t1, -0x18
2:
    nor     t0, t0, zero

    add.d   t1, t1, t2
    bltu    t1, t3, 10b
    nop
    bnez    a6, 20b
    nop
    //TM_PRINTSTR("Reading done.\r\n")

    jirl    zero, t8, 0
    nop
//===================================
//================================
test_mem_1:
    or    a6, ra, zero
    or    s4, t1, zero

    li.d     s6, 0x0
    li.d     s7, 0x0

	TM_PRINTSTR("\r\nStart Testing Memory...\r\n")

    TM_PRINTSTR("\r\nPattern DB_0 Test-----\r\n")
    //address interval
    li.d     t2, 0x200
    //set Test Base t1 and Test Limit t3
    li.d     t1, SIMPLE_TM_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
    GET_TM_MSIZE
    add.d   t3, t1, a1

#ifdef  TM_DBG
    GET_DISPRINT_BIT
    bnez    a1, 88f
    nop
    TM_PRINTSTR("Test address range: 0x")
    srli.d    a0, t1, 32
    bl     mm_hexserial
    nop
    or    a0, t1, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("~0x")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("  @@  address interval: 0x")
    or    a0, t2, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("\r\n")
88:
#endif
    TM_PRINTSTR("Pattern 0110 ....\r\n")
    li.d     t6, 0x4000000

10:
    li.d    tp, 1
    sub.d   t6, t6, tp
    //set Test Base t1 and Test Limit t3
    li.d     t1, SIMPLE_TM_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
    GET_TM_MSIZE
    add.d   t3, t1, a1

    li.d     t8, TM_MAX_RPT_ERRORS
    li.d     t0, PATTERN_DB_0_0
//write memory
    or    a0, t0, zero
    nor     a1, t0, zero
    nor     a2, t0, zero
    or    a3, t0, zero
1:
    st.d      a0, t1, 0x0
    st.d      a1, t1, 0x8
    st.d      a2, t1, 0x10
    st.d      a3, t1, 0x18
    add.d   t1, t1, t2
    bltu    t1, t3, 1b
    nop
    dbar 0
	TM_PRINTSTR("write done. begin to read and compare...\r\n")
//read memory and compare
    //set Test Base t1
    li.d     t1, MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
1:
    ld.d      t4, t1, 0x0
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    bl     hexserial64_1
    nop
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    nor     t0, t0, zero
    ld.d      t4, t1, 0x8
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x8 //the hexserial64_1 will use t1 directly
    bl     hexserial64_1
    nop
    addi.d  t1, t1, -0x8
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    ld.d      t4, t1, 0x10
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x10 //the hexserial64_1 will use t1 directly
    bl     hexserial64_1
    nop
    addi.d  t1, t1, -0x10
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    nor     t0, t0, zero
    ld.d      t4, t1, 0x18
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x18 //the hexserial64_1 will use t1 directly
    bl     hexserial64_1
    nop
    addi.d  t1, t1, -0x18
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    add.d   t1, t1, t2
    //check address range
    bltu    t1, t3, 1b
    nop

    bnez    t6, 10b
    nop
    TM_PRINTSTR("Pattern Testing done.\r\n")

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

    jirl    zero, a6, 0
    nop
//===================================
//================================
test_mem_1_silence:
    or    a6, ra, zero
    or    s4, t1, zero

    li.d     s6, 0x0
    li.d     s7, 0x0

	//TM_PRINTSTR("\r\nStart Testing Memory...\r\n")

//pattern Diff Burst Test
#if 1
    //TM_PRINTSTR("\r\nPattern DB_0 Test-----\r\n")
    //address interval
    li.d     t2, 0x40
    //set Test Base t1 and Test Limit t3
    li.d     t1, SIMPLE_TM_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
    GET_TM_MSIZE
    add.d   t3, t1, a1

#if 0
    GET_DISPRINT_BIT
    bnez    a1, 88f
    nop
    TM_PRINTSTR("Test address range: 0x")
    srli.d    a0, t1, 32
    bl     mm_hexserial
    nop
    or    a0, t1, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("~0x")
    srli.d    a0, t3, 32
    bl     mm_hexserial
    nop
    or    a0, t3, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("  @@  address interval: 0x")
    or    a0, t2, zero
    bl     mm_hexserial
    nop
    TM_PRINTSTR("\r\n")
88:
#endif
    //TM_PRINTSTR("Pattern 0110 ....\r\n")
    li.d     t6, 0x40000000

10:
    li.d    tp, 1
    sub.d   t6, t6, tp
    //set Test Base t1 and Test Limit t3
    li.d     t1, SIMPLE_TM_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
    GET_TM_MSIZE
    add.d   t3, t1, a1

    li.d     t8, TM_MAX_RPT_ERRORS
    li.d     t0, PATTERN_DB_0_0
//write memory
    or    a0, t0, zero
    nor     a1, t0, zero
    nor     a2, t0, zero
    or    a3, t0, zero
1:
    st.d      a0, t1, 0x0
    st.d      a1, t1, 0x8
    st.d      a2, t1, 0x10
    st.d      a3, t1, 0x18
    add.d   t1, t1, t2
    bltu    t1, t3, 1b
    nop
    dbar 0
	//TM_PRINTSTR("write done. begin to read and compare...\r\n")
//read memory and compare
    //set Test Base t1
    li.d     t1, MEM_TEST_BASE
    GET_TM_NODE_ID_a1
    slli.d    a1, a1, 44
    add.d   t1, t1, a1
    GET_TM_START_ADDR
    add.d   t1, t1, a1
1:
    ld.d      t4, t1, 0x0
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    bl     hexserial64_1_silence
    nop
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    nor     t0, t0, zero
    ld.d      t4, t1, 0x8
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x8 //the hexserial64_1_silence will use t1 directly
    bl     hexserial64_1_silence
    nop
    addi.d  t1, t1, -0x8
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    ld.d      t4, t1, 0x10
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x10 //the hexserial64_1_silence will use t1 directly
    bl     hexserial64_1_silence
    nop
    addi.d  t1, t1, -0x10
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    nor     t0, t0, zero
    ld.d      t4, t1, 0x18
    beq     t4, t0, 2f
    nop
    //error detected!!! print address,expected data,read data and reread data
    addi.d  t1, t1, 0x18 //the hexserial64_1_silence will use t1 directly
    bl     hexserial64_1_silence
    nop
    addi.d  t1, t1, -0x18
    bltz    t8, 10b  //detect enough errors, go to next test
    nop
2:
    add.d   t1, t1, t2
    //check address range
    bltu    t1, t3, 1b
    nop

    bnez    t6, 10b
    nop
    //TM_PRINTSTR("Pattern Testing done.\r\n")
#endif

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

    jirl    zero, a6, 0
    nop
//===================================

hexserial64_1:  //pseudo subroutine
/**********************
input:  t1: read address(read only)
        t0: expected data(read only)
        t4: read data
use reg:t5, t7
***********************/
    or    t7, ra, zero
    xor     a0, t0, t4
    or      s6, s6, a0
#ifdef  PRINT_LESS_ERROR
    addi.d  t8, t8, -0x1
#endif
    /* reread the wrong bytes */
#if 1
#if 1
    //Hit Invalidate the Primary D-cache and Second cache.
    //TM_PRINTSTR("\r\nInvalidate Primary D-cache and S-cache.\r\n")
    cacop   0x13, t1, 0
  //  cache   0x11, 0x0(t1)
  //  cache   0x13, 0x0(t1)
    dbar 0
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
#ifdef  TM_DBG
    GET_DISPRINT_BIT
    bnez    a1, 88f
    nop
	TM_PRINTSTR("addr 0x")
	srli.d	a0, t1, 32
	bl	    mm_hexserial
	nop
	or	a0, t1, zero
	bl	    mm_hexserial
	nop
    TM_PRINTSTR(" expected: ")
	srli.d	a0, t0, 32
	bl	    mm_hexserial
	nop
	or	a0, t0, zero
	bl	    mm_hexserial
	nop
    TM_PRINTSTR(" read: ")
	srli.d	a0, t4, 32
	bl	    mm_hexserial
	nop
	or	a0, t4, zero
	bl	    mm_hexserial
	nop
    TM_PRINTSTR(" reread: ")
	srli.d	a0, t5, 32
	bl	    mm_hexserial
	nop
	or	a0, t5, zero
	bl	    mm_hexserial
	nop
88:
#endif
    /* if the reread value differs the first read, print mark */
    xor     a0, t4, t5
    beqz    a0, 2f
    nop
    //Mark Read diff detected
    or      s7, s7, a0
    TM_PRINTSTR("  DDD")
    //---------------------
2:
    TM_PRINTSTR("\r\n")
    jirl    zero, t7, 0
    nop

//===================================
hexserial64_1_silence:  //pseudo subroutine
/**********************
input:  t1: read address(read only)
        t0: expected data(read only)
        t4: read data
use reg:t5, t7
***********************/
    or    t7, ra, zero
    xor     a0, t0, t4
    or      s6, s6, a0
#ifdef  PRINT_LESS_ERROR
    addi.d  t8, t8, -0x1
#endif
    /* reread the wrong bytes */
#if 1
#if 1
    //Hit Invalidate the Primary D-cache and Second cache.
    //TM_PRINTSTR("\r\nInvalidate Primary D-cache and S-cache.\r\n")
    cacop   0x13, t1, 0
   // cache   0x11, 0x0(t1)
   // cache   0x13, 0x0(t1)
    dbar 0
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
#if 0
    GET_DISPRINT_BIT
    bnez    a1, 88f
    nop
	TM_PRINTSTR("addr 0x")
	srli.d	a0, t1, 32
	bl	    mm_hexserial
	nop
	or	a0, t1, zero
	bl	    mm_hexserial
	nop
    TM_PRINTSTR(" expected: ")
	srli.d	a0, t0, 32
	bl	    mm_hexserial
	nop
	or	a0, t0, zero
	bl	    mm_hexserial
	nop
    TM_PRINTSTR(" read: ")
	srli.d	a0, t4, 32
	bl	    mm_hexserial
	nop
	or	a0, t4, zero
	bl	    mm_hexserial
	nop
    TM_PRINTSTR(" reread: ")
	srli.d	a0, t5, 32
	bl	    mm_hexserial
	nop
	or	a0, t5, zero
	bl	    mm_hexserial
	nop
88:
#endif
    /* if the reread value differs the first read, print mark */
    xor     a0, t4, t5
    beqz    a0, 2f
    nop
    //Mark Read diff detected
    or      s7, s7, a0
    //TM_PRINTSTR("  DDD")
    //---------------------
2:
    //TM_PRINTSTR("\r\n")
    jirl    zero, t7, 0
    nop

RL_end:
