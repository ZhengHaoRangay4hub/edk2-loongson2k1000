/* whd: loongson3C_ddr3_leveling.S
	2012.9.1
	first written by Leping from pfunc.s
	USE t8 to pass the CONFIG address
	ECC slice in not included yet
	2012.9.25 add ECC slice
*/
	b    lvl_req_set0
/* t1(0x20,0x40,...), t2(0x180,0x181,...), is used for loop, t0 is the loop count */
/* a0, a1 is used for load and store */
/* a2, a3 is used for set some parameters/judge some edges */
/* t4 is the tmp varible always used */

/* in MM_PRINTSTR: a0, a1, a2, a4, a5 will be changed */
/* in GET_NUMBER_OF_SLICES: t0, t1 will be changed and t0 is the output*/
/* in RDOE_SUB_TRDDATA_ADD: a0, a1, t4 will be changed*/
/* in mm_hexserial: ra, a0, a1, a2, a3 will be changed*/

#include "ddr_leveling_define.h"
//#define	PRINT_PREAMBLE_CHECK
//#define PRINT_DDR_LEVELING
#if defined(CONFIG_DDR_32BIT) || defined(CONFIG_DDR_16BIT)
#define NO_EDGE_CHECK
#else
#define	PREAMBLE_CHECK_DEBUG
#define PRINT_DDR_LEVELING
#endif
//#define SIGNAL_DEPICT_DEBUG
//#define LVL_DEBUG
#define CHANGE_DQ_WITH_DQS

#define ORDER_OF_UDIMM	0x876543210
#define ORDER_OF_RDIMM	0x765401238
#define WRDQS_LTHF_STD 	0x40
#define WRDQ_LTHF_STD 	0x40 //less then STD1 and less then STD2 will be set1
#define	RDDQS_LTHF_STD1	0x40 //greater then STD1 and less then STD2 will be set1
#define	RDDQS_LTHF_STD2	0x0
#define DLL_WRDQ_SUB	0x20
#define DLL_GATE_SUB	0x20
#define	WR_FILTER_LENGTH 	0x6
#define GATE_FILTER_LENGTH	0x6
#define PREAMBLE_LENGTH_3A9 0x60
#define PREAMBLE_LENGTH_3A8 0x60
#define MDL_CNT 0x500
#define GCL_CNT 9

#define	OFFSET_DLL_WRDQ 	0x19  // from 0x20/40/....
#define OFFSET_DLL_WRDQS 	0x1a
#define OFFSET_DLL_GATE 	0x18
#define OFFSET_WRDQ_LTHF 	0x0
#define	OFFSET_WRDQS_LTHF 	0x1
#define OFFSET_RDDQS_LTHF 	0x2
#define OFFSET_RDOE_BEGIN	0xe
#define OFFSET_RDOE_END	0xf
#define OFFSET_ODTOE_BEGIN 	0x14
#define OFFSET_ODTOE_END	0x15

	.globl ddr3_leveling
ddr3_leveling:

	or s5,ra, zero

//#define PM_DPD_FRE// change parameters depend on frequency
#ifdef PM_DPD_FRE

#for 3a8, different frequency will use different rd_oe_start/stop
#frequency 500M, rd_oe_begin/end 0x03030202
#frequency 600M, rd_oe_begin/end 0x03030000
	li.d      t1, PHYS_TO_UNCACHED(0x1fe201c0)
	ld.w      a1, t1, 0x0
	srli.d    t1, a1, 14 //DDR_LOOPC
	andi     t1, t1, 0x3ff
	srli.d    a1, a1, 24 //DDR_DIV
	andi     a1, a1, 0x3f

	//DDR_DIV: 4 or 8
	li.d     t4, 0x4
	beq     a1, t4, 1f
	nop
	srli.d    t1, t1, 1
1:
	srli.d    t1, t1, 2

	li.d     t4, 15
	beq  t1, t4, 99f; 	bge     t1, t4, 3f; 99:
	nop

	//<= 500M, for udimm, add rd_oe_start/stop by 0x2 and sub tPHY_RDDATA by 0x1
	//         for rdimm, only sub tPHY_RDDATA by 0x1
	GET_DIMM_TYPE
	bnez    a1, 4f //RDIMM
	nop

	//temp code for Kinston 2G UDIMM, at 400MHz, only sub tPHY_RDDATA by 0x1
	li.d     t4, 12
	beq     t1, t4, 4f
	nop


/* identify wheather there is ecc slice */
	li.w      t0, 0x8
	li.d     t1, 0x250
	or      t1, t1, t8
	ld.b      a0, t1, 0x2
	li.d     t1, 0x1
	and     a0, a0, t1
	bne     a0, t1, 1f //when rd_after_write enabled, the 9th device may don't need leveling
	nop
	addi.d   t0, t0, 0x1

1:

	li.d     t1, 0x28
	or      t1, t1, t8

2:
	ld.d      a0, t1, 0x0
	li.d     t4, 0x020200000000
	add.d   a0, a0, t4
	st.d      a0, t1, 0x0
	addi.d   t1, t1, 0x20
	li.d  tp, 0x1;  sub.d   t0, t0, tp
	bnez    t0, 2b
	nop

4: //FOR RDIMM
	ld.d      a0, t8, 0x1c0
	li.d  tp, 0x1;  sub.d   a0, a0, tp
	st.d      a0, t8, 0x1c0

	//> 500M
3:


#endif
#only the gate dll is bypassed at the beginning of leveling
#while other dlls' bypass is set at the end of leveling
#ifdef DDR_DLL_BYPASS
	li.d     t1, 0x0
	or      t1, t1, t8
	ld.d      a1, t1, 0x0
	li.d     t4, 0x0000ffff00000000
	and     a1, a1, t4
	srli.d    a1, a1, 32 // dll_value store in a1
//	add.d   a1, a1, 2

	//set dll_ck0
	li.d     t1, 0x18
	or      t1, t1, t8
	ld.b      a0, t1, 0x4
	mul.d  a0, a1, a0
	srli.d    a0, a0, 0x7
	ori     a0, a0, 0x80
	st.b      a0, t1, 0x4

	//set dll_ck1
	li.d     t1, 0x18
	or      t1, t1, t8
	ld.b      a0, t1, 0x5
	mul.d  a0, a1, a0
	srli.d    a0, a0, 0x7
	ori     a0, a0, 0x80
	st.b      a0, t1, 0x5

	//set dll_ck2
	li.d     t1, 0x18
	or      t1, t1, t8
	ld.b      a0, t1, 0x6
	mul.d  a0, a1, a0
	srli.d    a0, a0, 0x7
	ori     a0, a0, 0x80
	st.b      a0, t1, 0x6

	//set dll_ck3
	li.d     t1, 0x18
	or      t1, t1, t8
	ld.b      a0, t1, 0x7
	mul.d  a0, a1, a0
	srli.d    a0, a0, 0x7
	ori     a0, a0, 0x80
	st.b      a0, t1, 0x7

#endif
/* 1. wait until init done */
	li.d     t1, 0x160
	or      t1, t1, t8
wait_dram_init_done:
	ld.d      a0, t1, 0x0
	li.d     t4, 0x00000000ff000000
	and     a0, a0, t4
	beqz    a0, wait_dram_init_done
	nop

write_leveling:
	MM_PRINTSTR("\r\nwrite leveling begin\r\n")

/* 2. set all dll to be 0 */
	GET_NUMBER_OF_SLICES
	li.d     t1, 0x0
	or      t1, t1, t8
dll_wrdqs_set0:
	addi.d   t1, t1, 0x20
	li.w	a0, 0x0
	st.b      a0, t1, OFFSET_DLL_WRDQS
	li.d  tp, 0x1;  sub.d    t0, t0, tp
	bnez    t0, dll_wrdqs_set0
	nop

	MM_PRINTSTR("\r\nall dll_wrdqs set 0\r\n")

/* 3. set leveling mode to be WRITE LEVELING */
lvl_mode_set01:
	li.d	a0, 0x1
	st.b	a0, t8, 0x180

	MM_PRINTSTR("\r\nset leveling mode to be WRITE LEVELING\r\n")

/* 4. check whether to start leveling */
lvl_ready_sampling:
	ld.b      a0, t8, 0x185
	beqz    a0, lvl_ready_sampling
	nop

	MM_PRINTSTR("\r\nwrite leveling ready\r\n")

/* 5. Set leveling req */

	GET_NUMBER_OF_SLICES
	li.d	t1, 0x20
	or	t1, t1, t8
	li.d	t2, 0x180
	or	t2, t2, t8
	li.d	s7, WR_FILTER_LENGTH
	li.d	t6, 0
lvl_req_set0:
	li.d	a0, 0x1
	st.b	a0, t8, 0x181
	li.d	a0, 0x0
	st.b	a0, t8, 0x181

#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\nwrite leveling req set0\r\n")
#endif

lvl_done_sampling0:
	ld.b	a0, t8, 0x186
	beqz	a0, lvl_done_sampling0
	nop

#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\nwrite leveling done\r\n")
#endif

lvl_resp_set0:
	ld.b	a0, t2, 0x7
	//li.d	t4, 0x1
	li.d	t4, LEVELING_CHECK_BITS
	and 	a0, a0, t4
	beqz	a0, resp_set0_done
	nop

	li.d	s7, WR_FILTER_LENGTH
dll_wrdqs_add0:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\nslice ")
	li.d	a0, 0x8
	sub.d	a0, a0, t0
	bl 	mm_hexserial
	nop
	MM_PRINTSTR(" add to get 0\r\n")
#endif
	ld.b	a0, t1, OFFSET_DLL_WRDQS
	addi.d	a0, a0, 0x1
	li.d	t4, 0x7f
	and	a0, a0, t4
	st.b	a0, t1, OFFSET_DLL_WRDQS

#ifdef CHANGE_DQ_WITH_DQS
	ld.b	a0, t1, OFFSET_DLL_WRDQS // get dll_wrdqs
	li.d    tp, WRDQS_LTHF_STD;  blt	a0, tp, 1f
	nop
	li.w	t4, 0x0
	st.b	t4, t1, OFFSET_WRDQS_LTHF //set wrdqs_lt_half
	b	2f
	nop
1:
	li.w	t4, 0x1
	st.b	t4, t1, OFFSET_WRDQS_LTHF //set wrdqs_lt_half
2:
	li.d  tp, 0x20;  sub.d	a0, a0, tp
	li.d	t4, 0x7f
	and	a0, a0, t4
	st.b	a0, t1, OFFSET_DLL_WRDQ // set dll_wrdata

	li.d    tp, WRDQ_LTHF_STD;  blt	a0, tp, 1f
	nop
	li.w	t4, 0x0
	st.b	t4, t1, OFFSET_WRDQ_LTHF //set wrdq_lt_half
	b	2f
	nop
1:
	li.w	t4, 0x1
	st.b	t4, t1, OFFSET_WRDQ_LTHF //set wrdq_lt_half
2:
#endif
	li.d    tp, MDL_CNT;  beq  t6, tp, 99f; 	li.d    tp, MDL_CNT;  bge     t6, tp, leveling_failed; 99:
	nop
	addi.d   t6, t6, 0x1
	b 	lvl_req_set0
	nop

resp_set0_done:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\n 1 is found @ slice")
	li.d	a0, 0x8
	sub.d	a0, a0, t0
	bl 	mm_hexserial
	nop
#endif
#if 1
	li.d  tp, 0x1;  sub.d	s7, s7, tp
	bnez	s7, dll_wrdqs_add0
	nop
	li.d	s7, WR_FILTER_LENGTH

//  return the more add
	ld.b	a0, t1, OFFSET_DLL_WRDQS
	li.d  tp, WR_FILTER_LENGTH;  sub.d	a0, a0, tp
	addi.d	a0, a0, 0x1
	li.d	t4, 0x7f
	and	a0, a0, t4
	st.b	a0, t1, OFFSET_DLL_WRDQS
#ifdef CHANGE_DQ_WITH_DQS
	ld.b	a0, t1, OFFSET_DLL_WRDQS // get dll_wrdqs
	li.d    tp, WRDQS_LTHF_STD;  blt	a0, tp, 1f
	nop
	li.w	t4, 0x0
	st.b	t4, t1, OFFSET_WRDQS_LTHF //set wrdqs_lt_half
	b	2f
	nop
1:
	li.w	t4, 0x1
	st.b	t4, t1, OFFSET_WRDQS_LTHF //set wrdqs_lt_half
2:
	li.d  tp, 0x20;  sub.d	a0, a0, tp
	li.d	t4, 0x7f
	and	a0, a0, t4
	st.b	a0, t1, OFFSET_DLL_WRDQ // set dll_wrdata

	li.d    tp, WRDQ_LTHF_STD;  blt	a0, tp, 1f
	nop
	li.w	t4, 0x0
	st.b	t4, t1, OFFSET_WRDQ_LTHF //set wrdq_lt_half
	b	2f
	nop
1:
	li.w	t4, 0x1
	st.b	t4, t1, OFFSET_WRDQ_LTHF //set wrdq_lt_half
2:
#endif
#endif
	li.d  tp, 0x1;  sub.d	t0, t0, tp
	addi.d	t1, t1, 0x20
	addi.d	t2, t2, 0x1
	li.d	    t6, 0x0
	bnez	t0, lvl_req_set0
	nop


/* 0 to 1 */
	GET_NUMBER_OF_SLICES
	li.d	t1, 0x20
	or	t1, t1, t8
	li.d	t2, 0x180
	or	t2, t2, t8
	li.d	s7, WR_FILTER_LENGTH
lvl_req_set1:
	li.d	a0, 0x1
	st.b	a0, t8, 0x181
	li.d	a0, 0x0
	st.b	a0, t8, 0x181

#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\nwrite leveling req set1\r\n")
#endif

lvl_done_sampling1:
	ld.b	a0, t8, 0x186
	beqz	a0, lvl_done_sampling1
	nop

#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\nwrite leveling done\r\n")
#endif

lvl_resp_set1:
	ld.b	a0, t2, 0x7
	//li.d	t4, 0x1
	li.d	t4, LEVELING_CHECK_BITS
	and 	a0, a0, t4
	bnez	a0, resp_set1_done
	nop

	li.d	s7, WR_FILTER_LENGTH
dll_wrdqs_add1:
	ld.b	a0, t1, OFFSET_DLL_WRDQS
	addi.d	a0, a0, 0x1
	li.d	t4, 0x7f
	and	a0, a0, t4
	st.b	a0, t1, OFFSET_DLL_WRDQS

#ifdef CHANGE_DQ_WITH_DQS
	ld.b	a0, t1, OFFSET_DLL_WRDQS // get dll_wrdqs
	li.d    tp, WRDQS_LTHF_STD;  blt	a0, tp, 1f
	nop
	li.w	t4, 0x0
	st.b	t4, t1, OFFSET_WRDQS_LTHF //set wrdqs_lt_half
	b	2f
	nop
1:
	li.w	t4, 0x1
	st.b	t4, t1, OFFSET_WRDQS_LTHF //set wrdqs_lt_half
2:
	li.d  tp, 0x20;  sub.d	a0, a0, tp
	li.d	t4, 0x7f
	and	a0, a0, t4
	st.b	a0, t1, OFFSET_DLL_WRDQ // set dll_wrdata

	li.d    tp, WRDQ_LTHF_STD;  blt	a0, tp, 1f
	nop
	li.w	t4, 0x0
	st.b	t4, t1, OFFSET_WRDQ_LTHF //set wrdq_lt_half
	b	2f
	nop
1:
	li.w	t4, 0x1
	st.b	t4, t1, OFFSET_WRDQ_LTHF //set wrdq_lt_half
2:
#endif
	li.d    tp, MDL_CNT;  beq  t6, tp, 99f; 	li.d    tp, MDL_CNT;  bge     t6, tp, leveling_failed; 99:
	nop
	addi.d   t6, t6, 0x1
	b 	lvl_req_set1
	nop

resp_set1_done:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\n 1 is found @ slice")
	li.d	a0, 0x8
	sub.d	a0, a0, t0
	bl 	mm_hexserial
	nop
#endif
	li.d  tp, 0x1;  sub.d	s7, s7, tp
	bnez	s7, dll_wrdqs_add1
	nop
	li.d	s7, WR_FILTER_LENGTH

//  return the more add
	ld.b	a0, t1, OFFSET_DLL_WRDQS
	li.d  tp, WR_FILTER_LENGTH;  sub.d	a0, a0, tp
	addi.d	a0, a0, 0x1
	li.d	t4, 0x7f
	and	a0, a0, t4
	st.b	a0, t1, OFFSET_DLL_WRDQS

#ifdef CHANGE_DQ_WITH_DQS
	ld.b	a0, t1, OFFSET_DLL_WRDQS // get dll_wrdqs
	li.d    tp, WRDQS_LTHF_STD;  blt	a0, tp, 1f
	nop
	li.w	t4, 0x0
	st.b	t4, t1, OFFSET_WRDQS_LTHF //set wrdqs_lt_half
	b	2f
	nop
1:
	li.w	t4, 0x1
	st.b	t4, t1, OFFSET_WRDQS_LTHF //set wrdqs_lt_half
2:
	li.d  tp, 0x20;  sub.d	a0, a0, tp
	li.d	t4, 0x7f
	and	a0, a0, t4
	st.b	a0, t1, OFFSET_DLL_WRDQ // set dll_wrdata

	li.d    tp, WRDQ_LTHF_STD;  blt	a0, tp, 1f
	nop
	li.w	t4, 0x0
	st.b	t4, t1, OFFSET_WRDQ_LTHF //set wrdq_lt_half
	b	2f
	nop
1:
	li.w	t4, 0x1
	st.b	t4, t1, OFFSET_WRDQ_LTHF //set wrdq_lt_half
2:
#endif
	li.d  tp, 0x1;  sub.d	t0, t0, tp
	addi.d	t1, t1, 0x20
	addi.d	t2, t2, 0x1
	li.d	    t6, 0x0
	bnez	t0, lvl_req_set1
	nop

write_leveling_done:
#ifdef PRINT_DDR_LEVELING
	MM_PRINTSTR("\r\n The MC param after write leveling 0 to 1 is:\r\n")
	PRINT_THE_MC_PARAM
#endif

/* 8. All 1 found, set params according to wrdqs */

//	GET_DIMM_TYPE
//	beqz    a1, 81f
//	nop

/* adjust wrdqs carefully */
#if 0   //def  DEBUG_DDR_PARAM   //print registers
	MM_PRINTSTR("\r\nThe MC param before carefully adjust is:\r\n")
	PRINT_THE_MC_PARAM
#endif
wrdqs_adjust:
#if 1
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\nwrdqs around 0x00 carefully adjust begin\r\n")
#endif
	GET_NUMBER_OF_SLICES
	addi.d	t0, t0, 0x1
	li.d     a2, 0x08
	li.d     a3, 0x78
	li.d     t1, 0x00
	or      t1, t1, t8
	WRDQS_ADJUST_LOOP

	GET_NUMBER_OF_SLICES
	addi.d	t0, t0, 0x1
	li.d     a2, 0x28
	li.d     a3, 0x18
	li.d     t1, 0x00
	or      t1, t1, t8
	WRDQS_ADJUST_LOOP

	GET_NUMBER_OF_SLICES
	addi.d	t0, t0, 0x1
	li.d     a2, 0x48
	li.d     a3, 0x38
	li.d     t1, 0x00
	or      t1, t1, t8
	WRDQS_ADJUST_LOOP

	GET_NUMBER_OF_SLICES
	addi.d	t0, t0, 0x1
	li.d     a2, 0x68
	li.d     a3, 0x58
	li.d     t1, 0x00
	or      t1, t1, t8
	WRDQS_ADJUST_LOOP


#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\nwrdqs around 0x00 carefully adjust end\r\n")
#endif
#endif

#if 0   //def  DEBUG_DDR_PARAM   //print registers
	MM_PRINTSTR("\r\nThe MC param after carefully adjust is:\r\n")
	PRINT_THE_MC_PARAM
#endif
81:

#if 1
/* 8.1 adjust wrdata */

/* t0 is used to indicate 8 slices */
	GET_NUMBER_OF_SLICES
	li.d     t1, 0x20
	or      t1, t1, t8
dll_wrdata_set:
	ld.b	a0, t1, OFFSET_DLL_WRDQS // get dll_wrdqs
	li.d    tp, WRDQS_LTHF_STD;  blt	a0, tp, 1f
	nop
	li.w	t4, 0x0
	st.b	t4, t1, OFFSET_WRDQS_LTHF //set wrdqs_lt_half
	b	2f
	nop
1:
	li.w	t4, 0x1
	st.b	t4, t1, OFFSET_WRDQS_LTHF //set wrdqs_lt_half
2:
	li.d  tp, DLL_WRDQ_SUB;  sub.d	a0, a0, tp
	li.d	t4, 0x7f
	and	a0, a0, t4
	st.b	a0, t1, OFFSET_DLL_WRDQ // set dll_wrdata

	li.d    tp, WRDQ_LTHF_STD;  blt	a0, tp, 1f
	nop
	li.w	t4, 0x0
	st.b	t4, t1, OFFSET_WRDQ_LTHF //set wrdq_lt_half
	b	2f
	nop
1:
	li.w	t4, 0x1
	st.b	t4, t1, OFFSET_WRDQ_LTHF //set wrdq_lt_half
2:
	addi.d	t1, t1, 0x20
	li.d  tp, 0x1;  sub.d	t0, t0, tp
	bnez	t0, dll_wrdata_set
	nop
#endif


wrdq_lt_half_test:
	li.d	s7, 0x0 // s7 represent whether find 1 to 0 or not
	GET_DIMM_TYPE
	bnez    a1, rdimm_wrdq_lt_half_test
	nop
	li.w      t0, 0x7 //only loop 7 times
	li.d     t1, 0x250
	or      t1, t1, t8
	ld.b      a0, t1, 0x2
	li.d     t1, 0x1
	and     a0, a0, t1
	bne     a0, t1, 1f //when rd_after_write enabled, the 9th device may don't need leveling
	nop
	addi.d   t0, t0, 0x1
1:
	li.d     t2, 0x0
wrdq_lt_half_test_loop:
	li.d	a0, ORDER_OF_UDIMM
	li.d	t4, 0x4
	mul.d	a1,	t2, t4
	srl.d	a0, a0, a1
	andi	a0, a0, 0xf
	addi.d	a0, a0, 0x1
	li.d	t4, 0x20
	mul.d	t1, a0, t4
	or	t1, t1, t8
#if 1
	bl	mm_hexserial
	nop
#endif

	addi.d   t2, t2, 0x1
	beq  t2, t0, 99f; 	bge     t2, t0, record_slice_num; 99:
	nop
	ld.b      a0, t1, 0x0
	beqz    a0, wrdq_lt_half_test_loop
	nop

	li.d	a0, ORDER_OF_UDIMM
	li.d	t4, 0x4
	mul.d	a1,	t2, t4
	sll.d	a0, a0, a1
	andi	a0, a0, 0xf
	addi.d	a0, a0, 0x1
	li.d	t4, 0x20
	mul.d	t1, a0, t4
	or	t1, t1, t8
#if 1
	bl	mm_hexserial
	nop
#endif

	ld.b	a0, t1, 0x0
	beqz    a0, record_slice_num
	nop
	b       wrdq_lt_half_test_loop
	nop

record_slice_num:
	or    t3, t2, zero //the slice number save in t3
	or    a0, t3, zero
	bl	mm_hexserial
	nop
	li.d    tp, 0x8;  beq     t3, tp, first_slice_wrdq_lt_half_test
	nop

wrdq_clkdelay_set:
//	li.w      t0, 0x7 //only loop 7 times
	li.d     t2, 0x0
wrdq_clkdelay_set_loop:
	addi.d   t2, t2, 0x1
	beq  t2, t0, 99f; 	bge     t2, t0, first_slice_wrdq_lt_half_test; 99:
	nop

	li.d	a0, ORDER_OF_UDIMM
	li.d	t4, 0x4
	mul.d	a1,	t2, t4
	sll.d	a0, a0, a1
	andi	a0, a0, 0xf
	addi.d	a0, a0, 0x1
	li.d	t4, 0x20
	mul.d	t1, a0, t4
	or	t1, t1, t8
	addi.d	t1, t1, 0x10

	ld.d      a0, t1, 0x0
	blt     t2, t3, wrdq_clkdelay_set0
	nop
	b       wrdq_clkdelay_set1
	nop

wrdq_clkdelay_set0:
	li.d     t4, 0xffffff00ffffffff
	and     a0, a0, t4
	st.d      a0, t1, 0x0
	b       wrdq_clkdelay_set_loop
	nop

wrdq_clkdelay_set1:
	li.d 	s7, 0x1
	li.d     t4, 0xffffff00ffffffff
	and     a0, a0, t4
	li.d     t4, 0x0000000100000000
	or      a0, a0, t4
	st.d      a0, t1, 0x0
	b       wrdq_clkdelay_set_loop
	nop

first_slice_wrdq_lt_half_test:
	li.d    tp, 0x1;  beq	s7, tp, trddata_tphywrdata_sub
	nop
	li.d	a0, ORDER_OF_UDIMM
	andi	a0, a0, 0xf
	addi.d	a0, a0, 0x1
	li.d	t4, 0x20
	mul.d	t1, a0, t4
	or	t1, t1, t8

	ld.d      a0, t1, 0x0
	li.d     t4, 0x00000000000000ff
	and     a0, a0, t4
	beqz    a0, write_leveling_exit
	nop


trddata_tphywrdata_sub:
	/* tRDDATA sub one */
	li.d     t2, 0x1c0
	or      t2, t2, t8
	ld.d      a0, t2, 0x0
	li.d     t4, 0x01
	sub.d   a0, a0, t4
	st.d      a0, t2, 0x0
	/* tPHY_WRDATA sub one */
	li.d     t2, 0x1d0
	or      t2, t2, t8
	ld.d      a0, t2, 0x0
	li.d     t4, 0x100000000
	sub.d   a0, a0, t4
	st.d      a0, t2, 0x0
	b       write_leveling_exit
	nop

rdimm_wrdq_lt_half_test:
/* identify wheather there is ecc slice */
	li.d     t1, 0x250
	or      t1, t1, t8
	ld.b      a0, t1, 0x2
	li.d     t1, 0x1
	and     a0, a0, t1
//	li.d     t2, 0x0
	bne     a0, t1, rdimm_wrdq_lt_half_test_3210
	nop

rdimm_wrdq_lt_half_test_83:
	li.w      t0, 0x4
	li.d     t2, 0x0
	li.d	a0, ORDER_OF_RDIMM
	li.d	t4, 0x4
	mul.d	a1,	t2, t4
	sll.d	a0, a0, a1
	andi	a0, a0, 0xf
	addi.d	a0, a0, 0x1
	li.d	t4, 0x20
	mul.d	t1, a0, t4
	or	t1, t1, t8
	ld.b      a0, t1, 0x0
	addi.d   t2, t2, 0x1
	beqz    a0, rdimm_wrdq_lt_half_test_loop_3210
	nop
	li.d	a0, ORDER_OF_RDIMM
	li.d	t4, 0x4
	mul.d	a1,	t2, t4
	sll.d	a0, a0, a1
	andi	a0, a0, 0xf
	addi.d	a0, a0, 0x1
	li.d	t4, 0x20
	mul.d	t1, a0, t4
	or	t1, t1, t8
	ld.b      a0, t1, 0x0
	beqz    a0, rdimm_record_slice_num_83210
	nop
	b       rdimm_wrdq_lt_half_test_loop_3210
	nop


rdimm_wrdq_lt_half_test_3210:
	li.w      t0, 0x4
	li.d     t2, 0x1
	li.d	a0, ORDER_OF_RDIMM
	li.d	t4, 0x4
	mul.d	a1,	t2, t4
	sll.d	a0, a0, a1
	andi	a0, a0, 0xf
	addi.d	a0, a0, 0x1
	li.d	t4, 0x20
	mul.d	t1, a0, t4
	or	t1, t1, t8

rdimm_wrdq_lt_half_test_loop_3210:
	li.d	a0, ORDER_OF_RDIMM
	li.d	t4, 0x4
	mul.d	a1,	t2, t4
	sll.d	a0, a0, a1
	andi	a0, a0, 0xf
	addi.d	a0, a0, 0x1
	li.d	t4, 0x20
	mul.d	t1, a0, t4
	or	t1, t1, t8
	addi.d   t2, t2, 0x1
	beq  t2, t0, 99f; 	bge     t2, t0, rdimm_wrdq_lt_half_test_4567; 99:
	nop
#ifdef LVL_DEBUG
	or	a0, t1, zero
	bl	mm_hexserial
	nop
#endif
	ld.b      a0, t1, 0x0
	beqz    a0, rdimm_wrdq_lt_half_test_loop_3210
	nop
	li.d	a0, ORDER_OF_RDIMM
	li.d	t4, 0x4
	mul.d	a1,	t2, t4
	sll.d	a0, a0, a1
	andi	a0, a0, 0xf
	addi.d	a0, a0, 0x1
	li.d	t4, 0x20
	mul.d	t1, a0, t4
	or	t1, t1, t8
	ld.b      a0, t1, 0x0
	beqz    a0, rdimm_record_slice_num_3210
	nop
	b       rdimm_wrdq_lt_half_test_loop_3210
	nop

rdimm_record_slice_num_3210:
rdimm_record_slice_num_83210:
	or    t3, t2, zero
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\nt3=")
	or 	a0, t3, zero
	bl	mm_hexserial
	nop
#endif

/* identify wheather there is ecc slice */
	li.d     t1, 0x250
	or      t1, t1, t8
	ld.b      a0, t1, 0x2
	li.d     t1, 0x1
	and     a0, a0, t1
	bne     a0, t1, rdimm_wrdq_clkdelay_set_3210
	nop
rdimm_wrdq_clkdelay_set_8:
	li.w      t0, 0x4
	li.d     t2, 0x0
	li.d	a0, ORDER_OF_RDIMM
	li.d	t4, 0x4
	mul.d	a1,	t2, t4
	sll.d	a0, a0, a1
	andi	a0, a0, 0xf
	addi.d	a0, a0, 0x1
	li.d	t4, 0x20
	mul.d	t1, a0, t4
	addi.d	t1, t1, 0x10
	or	t1, t1, t8
//	add.d   t2, t2, 0x1
	ld.d      a0, t1, 0x0
	blt     t2, t3, rdimm_wrdq_clkdelay_set0_8
	nop
	b       rdimm_wrdq_clkdelay_set1_8
	nop

rdimm_wrdq_clkdelay_set0_8:
	li.d     t4, 0xffffff00ffffffff
	and     a0, a0, t4
	st.d      a0, t1, 0x0
	li.d     t1, 0xb0 //here set 0xb0 because it will sub 0x20 later
	or      t1, t1, t8
	b       rdimm_wrdq_clkdelay_set_loop_3210
	nop

rdimm_wrdq_clkdelay_set1_8:
	li.d 	s7, 0x1
	li.d     t4, 0xffffff00ffffffff
	and     a0, a0, t4
	li.d     t4, 0x0000000100000000
	or      a0, a0, t4
	st.d      a0, t1, 0x0
	li.d     t1, 0xb0 //here set 0xb0 because it will sub 0x20 later
	or      t1, t1, t8
	b       rdimm_wrdq_clkdelay_set_loop_3210
	nop

rdimm_wrdq_clkdelay_set_3210:
	li.w      t0, 0x4
	li.d     t2, 0x1
rdimm_wrdq_clkdelay_set_loop_3210:
1:
	addi.d   t2, t2, 0x1
	beq  t2, t0, 99f; 	bge     t2, t0, rdimm_wrdq_lt_half_test_4567; 99:
	nop
	li.d	a0, ORDER_OF_RDIMM
	li.d	t4, 0x4
	mul.d	a1,	t2, t4
	sll.d	a0, a0, a1
	andi	a0, a0, 0xf
	addi.d	a0, a0, 0x1
	li.d	t4, 0x20
	mul.d	t1, a0, t4
	addi.d	t1, t1, 0x10
	or	t1, t1, t8
	ld.d      a0, t1, 0x0
	blt     t2, t3, rdimm_wrdq_clkdelay_set0_3210
	nop
	b       rdimm_wrdq_clkdelay_set1_3210
	nop

rdimm_wrdq_clkdelay_set0_3210:
	li.d     t4, 0xffffff00ffffffff
	and     a0, a0, t4
	st.d      a0, t1, 0x0
	b       1b
	nop

rdimm_wrdq_clkdelay_set1_3210:
	li.d 	s7, 0x1
	li.d     t4, 0xffffff00ffffffff
	and     a0, a0, t4
	li.d     t4, 0x0000000100000000
	or      a0, a0, t4
	st.d      a0, t1, 0x0
	b       1b
	nop


rdimm_wrdq_lt_half_test_4567:
	li.w      t0, 0x8
	li.d     t2, 0x5

rdimm_wrdq_lt_half_test_loop_4567:
	li.d	a0, ORDER_OF_RDIMM
	li.d	t4, 0x4
	mul.d	a1,	t2, t4
	sll.d	a0, a0, a1
	andi	a0, a0, 0xf
	addi.d	a0, a0, 0x1
	li.d	t4, 0x20
	mul.d	t1, a0, t4
	or	t1, t1, t8
	addi.d   t2, t2, 0x1
	beq  t2, t0, 99f; 	bge     t2, t0, slice_8_wrdq_lt_half_test; 99:
	nop
	ld.b      a0, t1, 0x0
	beqz    a0, rdimm_wrdq_lt_half_test_loop_4567
	nop
	li.d	a0, ORDER_OF_RDIMM
	li.d	t4, 0x4
	mul.d	a1,	t2, t4
	sll.d	a0, a0, a1
	andi	a0, a0, 0xf
	addi.d	a0, a0, 0x1
	li.d	t4, 0x20
	mul.d	t1, a0, t4
	or	t1, t1, t8
	ld.b      a0, t1, 0x0
	beqz    a0, rdimm_record_slice_num_4567
	nop
	b       rdimm_wrdq_lt_half_test_loop_4567
	nop

rdimm_record_slice_num_4567:
	or    t3, t2, zero //the slice number save in t3
	li.d     t5, 0x0

rdimm_wrdq_clkdelay_set_4567:
	li.w      t0, 0x8 //only loop 7 times
	li.d     t2, 0x5
rdimm_wrdq_clkdelay_set_loop_4567:
	addi.d   t2, t2, 0x1
	beq  t2, t0, 99f; 	bge     t2, t0, slice_8_wrdq_lt_half_test; 99:
	nop
	li.d     a0, ORDER_OF_RDIMM
	li.d     t4, 0x4
	mul.d   a1,	t2, t4
	sll.d    a0, a0, a1
	andi     a0, a0, 0xf
	addi.d   a0, a0, 0x1
	li.d     t4, 0x20
	mul.d   t1, a0, t4
	addi.d   t1, t1, 0x10
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	blt     t2, t3, rdimm_wrdq_clkdelay_set0_4567
	nop
	b       rdimm_wrdq_clkdelay_set1_4567
	nop

rdimm_wrdq_clkdelay_set0_4567:
	li.d     t4, 0xffffff00ffffffff
	and     a0, a0, t4
	st.d      a0, t1, 0x0
	b       rdimm_wrdq_clkdelay_set_loop_4567
	nop

rdimm_wrdq_clkdelay_set1_4567:
	li.d     s7, 0x1
	li.d     t4, 0xffffff00ffffffff
	and     a0, a0, t4
	li.d     t4, 0x0000000100000000
	or      a0, a0, t4
	st.d      a0, t1, 0x0

	bnez    t5, 1f
	nop
/* identify wheather there is ecc slice */
	li.d     t1, 0x250
	or      t1, t1, t8
	ld.b      a0, t1, 0x2
	li.d     t1, 0x1
	and     a0, a0, t1
//	li.d     t2, 0x0
	bne     a0, t1, noecc
	nop

	li.d     t4, 0x20
	li.d     a0, 0x9
	mul.d   t1, a0, t4
	or      t1, t1, t8
	ld.b      a0, t1, 0x0
	bnez    a0, 1f
	nop
noecc:
	li.d     t4, 0x20
	li.d     a0, 0x4
	mul.d   t1, a0, t4
	or      t1, t1, t8
	ld.b      a0, t1, 0x0
	bnez    a0, 1f
	nop

	li.d     a0, 0x3
	mul.d   t1, a0, t4
	or      t1, t1, t8
	ld.b      a0, t1, 0x0
	bnez    a0, 1f
	nop

	li.d	    a0, 0x2
	mul.d   t1, a0, t4
	or      t1, t1, t8
	ld.b      a0, t1, 0x0
	bnez    a0, 1f
	nop

	li.d     a0, 0x1
	mul.d   t1, a0, t4
	or      t1, t1, t8
	ld.b      a0, t1, 0x0
	bnez    a0, 1f
	nop

	ld.d      a0, t8, 0x30
	li.d     t4, 0xffffff00ffffffff
	and     a0, a0, t4
	li.d     t4, 0x0000000100000000
	or      a0, a0, t4
	st.d      a0, t8, 0x30

	ld.d      a0, t8, 0x50
	li.d     t4, 0xffffff00ffffffff
	and     a0, a0, t4
	li.d     t4, 0x0000000100000000
	or      a0, a0, t4
	st.d      a0, t8, 0x50

	ld.d      a0, t8, 0x70
	li.d     t4, 0xffffff00ffffffff
	and     a0, a0, t4
	li.d     t4, 0x0000000100000000
	or      a0, a0, t4
	st.d      a0, t8, 0x70

	ld.d      a0, t8, 0x90
	li.d     t4, 0xffffff00ffffffff
	and     a0, a0, t4
	li.d     t4, 0x0000000100000000
	or      a0, a0, t4
	st.d      a0, t8, 0x90

	li.d     t1, 0x250
	or      t1, t1, t8
	ld.b      a0, t1, 0x2
	li.d     t1, 0x1
	and     a0, a0, t1
//	li.d     t2, 0x0
	bne     a0, t1, 1f
	nop
	ld.d      a0, t8, 0x130
	li.d     t4, 0xffffff00ffffffff
	and     a0, a0, t4
	li.d     t4, 0x0000000100000000
	or      a0, a0, t4
	st.d      a0, t8, 0x130
1:
	addi.d   t5, t5, 0x1
	b       rdimm_wrdq_clkdelay_set_loop_4567
	nop

slice_8_wrdq_lt_half_test:
	li.d    tp, 0x1;  beq	s7, tp, rdimm_trddata_tphywrdata_sub
	nop
	li.d     t1, 0x250
	or      t1, t1, t8
	ld.b      a0, t1, 0x2
	li.d     t1, 0x1
	and     a0, a0, t1
	bne     a0, t1, slice_3_wrdq_lt_half_test
	nop
	li.d	a0, ORDER_OF_RDIMM
	li.d	t2, 0x0
	li.d	t4, 0x4
	mul.d	a1,	t2, t4
	sll.d	a0, a0, a1
	andi	a0, a0, 0xf
	addi.d	a0, a0, 0x1
	li.d	t4, 0x20
	mul.d	t1, a0, t4
	or	t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t4, 0x00000000000000ff
	and     a0, a0, t4
	bnez    a0, rdimm_trddata_tphywrdata_sub
	nop
	b       slice_4_wrdq_lt_half_test
	nop

slice_3_wrdq_lt_half_test:
	li.d    tp, 0x1;  beq	s7, tp, rdimm_trddata_tphywrdata_sub
	nop
	li.d	a0, ORDER_OF_RDIMM
	li.d	t2, 0x1
	li.d	t4, 0x4
	mul.d	a1,	t2, t4
	sll.d	a0, a0, a1
	andi	a0, a0, 0xf
	addi.d	a0, a0, 0x1
	li.d	t4, 0x20
	mul.d	t1, a0, t4
	or	t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t4, 0x00000000000000ff
	and     a0, a0, t4
	bnez    a0, rdimm_trddata_tphywrdata_sub
	nop

slice_4_wrdq_lt_half_test:
	li.d    tp, 0x1;  beq	s7, tp, rdimm_trddata_tphywrdata_sub
	nop
	li.d	a0, ORDER_OF_RDIMM
	li.d	t2, 0x5
	li.d	t4, 0x4
	mul.d	a1,	t2, t4
	sll.d	a0, a0, a1
	andi	a0, a0, 0xf
	addi.d	a0, a0, 0x1
	li.d	t4, 0x20
	mul.d	t1, a0, t4
	or	t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t4, 0x00000000000000ff
	and     a0, a0, t4
	beqz    a0, write_leveling_exit
	nop

rdimm_trddata_tphywrdata_sub:
	/* tRDDATA sub one */
	li.d     t2, 0x1c0
	or      t2, t2, t8
	ld.d      a0, t2, 0x0
	li.d     t4, 0x01
	sub.d   a0, a0, t4
	st.d      a0, t2, 0x0
	/* tPHY_WRDATA sub one */
	li.d     t2, 0x1d0
	or      t2, t2, t8
	ld.d      a0, t2, 0x0
	li.d     t4, 0x100000000
	sub.d   a0, a0, t4
	st.d      a0, t2, 0x0

write_leveling_exit:
	li.d     t1, 0x180
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t4, 0xffffffffffffff00
	and     a0, a0, t4
	st.d      a0, t1, 0x0

	b       gate_leveling
//	b       100f
	nop

gate_leveling:
#if 1 //3a3000 new
//	MM_PRINTSTR("\r\nset cs_zq to be same with cs_enable\r\n")
	ld.b      a0, t8, 0x169
	st.b      a0, t8, 0x16a

reset_init_start_new:
	li.d     t1, 0x18
	or      t1, t1, t8
	li.d	a0, 0x0
	st.b      a0, t1, 0x0

	li.d     a0, 0x1
	st.b      a0, t1, 0x0

wait_init_done_new:
	li.d     t1, 0x160
	or      t1, t1, t8
	ld.b      a0, t1, 0x3
	beqz    a0, wait_init_done_new
	nop

reset_init_start_new2:
	li.d     t1, 0x18
	or      t1, t1, t8
	li.d	a0, 0x0
	st.b      a0, t1, 0x0

	li.d     a0, 0x1
	st.b      a0, t1, 0x0

wait_init_done_new2:
	li.d     t1, 0x160
	or      t1, t1, t8
	ld.b      a0, t1, 0x3
	beqz    a0, wait_init_done_new2
	nop
#endif

	MM_PRINTSTR("\r\nwrite leveling finist.h and gate leveling begin\r\n")
#ifdef  PRINT_DDR_LEVELING   //print registers
	MM_PRINTSTR("\r\nThe MC param after write leveling is:\r\n")
	PRINT_THE_MC_PARAM
#endif

/* identify wheather there is ecc slice */
	GET_NUMBER_OF_SLICES
	li.d     t1, 0x20
	or      t1, t1, t8
dll_gate_set0:
	li.d	a0, 0x0
#ifdef DDR_DLL_BYPASS
	li.d	a0, 0x80
#endif
	st.b      a0, t1, OFFSET_DLL_GATE
	li.d  tp, 0x1;  sub.d    t0, t0, tp
	addi.d	t1, t1, 0x20
	bnez    t0, dll_gate_set0
	nop

glvl_mode_set10:
	li.d     t1, 0x180
	or      t1, t1, t8
	li.d	a0, 0x2
	st.b      a0, t1, 0x0

	li.d     a1, 0x1
glvl_ready_sampling:
	li.d     t1, 0x180
	or      t1, t1, t8
	ld.b      a0, t1, 0x5
	bne     a0, a1, glvl_ready_sampling
	nop

#ifdef SIGNAL_DEPICT_DEBUG
	MM_PRINTSTR("\r\nthe signal depict begin:\r\n")
	li.d	t1, 0x28     // save the init para before signal depict
	or 	t1, t1, t8
	ld.b	a0, t1, 0x7
	li.d	t1, 0x350
	or	t1, t1, t8
	st.b	a0, t1, 0x7
	li.d	t1, 0x1c0
	or	t1, t1, t8
	ld.b	a0, t1, 0x0
	li.d	t1, 0x350
	or	t1, t1, t8
	st.b	a0, t1, 0x6

	li.d	t1, 0x28
	or	t1, t1, t8
	li.d	t5, 0x180
	or	t5, t5, t8
	li.d	t0, 0x8
	li.d	t2, 0x0
	li.d	s6, 0x0
	li.d	s7, 0x0
t_glvl_req_set:
	li.d    tp, 0x15;  bne	s6, tp, 1f
	nop
	li.d	s6, 0x0		//reset trddata
	ld.b	a0, t8, 0x356
	st.b	a0, t8, 0x1c0
	li.d  tp, 0x1;  sub.d	t0, t0, tp
	beqz	t0, signal_depict_end
	nop
	addi.d	t1, t1, 0x20
	addi.d	t5, t5, 0x1
	MM_PRINTSTR("\r\nthe above is slice ")
	li.d	t4, 0x8
	sub.d 	a0, t4, t0
	bl	mm_hexserial
	nop
	MM_PRINTSTR("\r\n")
1:
	li.d     t4, 0x180
	or      t4, t4, t8
	li.d     a0, 0x1
	st.b      a0, t4, 0x1
	li.d	a0, 0x0
	st.b      a0, t4, 0x1

1:			//glvl_done_sampling
	li.d     t4, 0x180
	or      t4, t4, t8
	ld.b      a0, t4, 0x6
	li.d    tp, 0x1;  bne     a0, tp, 1b
	nop

	ld.b	a0, t5, 0x7
	li.d	t4, 0x1
	and	a0, a0, t4
	or	a1, a0, zero
#if 1
	li.d     t4, 0x180
	or      t4, t4, t8
	li.d     a0, 0x1
	st.b      a0, t4, 0x1
	li.d	a0, 0x0
	st.b      a0, t4, 0x1

1:			//glvl_done_sampling
	li.d     t4, 0x180
	or      t4, t4, t8
	ld.b      a0, t4, 0x6
	li.d    tp, 0x1;  bne     a0, tp, 1b
	nop

	ld.b	a0, t5, 0x7
	li.d	t4, 0x1
	and	a0, a0, t4
	or	a0, a0, a1
	or	a1, a0, zero
#endif
#if 1
	li.d     t4, 0x180
	or      t4, t4, t8
	li.d     a0, 0x1
	st.b      a0, t4, 0x1
	li.d	a0, 0x0
	st.b      a0, t4, 0x1

1:			//glvl_done_sampling
	li.d     t4, 0x180
	or      t4, t4, t8
	ld.b      a0, t4, 0x6
	li.d    tp, 0x1;  bne     a0, tp, 1b
	nop

	ld.b	a0, t5, 0x7
	li.d	t4, 0x1
	and	a0, a0, t4
	or	a0, a0, a1
#endif

	sll	a0, a0, 0x1f
	srl	a0, a0, s7
	or	t2, t2, a0
	addi.d	s7, s7, 0x1
	li.d    tp, 0x20;  blt	s7, tp, 1f // every 0x20 print the status
	nop
	or 	a0, t2, zero
	bl	mm_hexserial
	nop
	MM_PRINTSTR(" ")
	li.d	t2, 0x0
	li.d	s7, 0x0
	addi.d	s6, s6, 0x1
1:

#if 1
	ld.b	a0, t1, 0x10
	addi.d	a0, a0, 0x1
	li.d	t4, 0x7f
	and	a0, a0, t4
	st.b	a0, t1, 0x10
	bnez	a0, 1f
	nop
	ld.b	a0, t8, 0x1c0
	addi.d	a0, a0, 0x1
	st.b	a0, t8, 0x1c0
1:
#else
	ld.b	a0, t1, 0x10
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	li.d	t4, 0x7f
	and	a0, a0, t4
	st.b	a0, t1, 0x10
	li.d    tp, 0x7f;  bne	a0, tp,1f
	nop
	ld.b	a0, t8, 0x1c0
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	st.b	a0, t8, 0x1c0
1:
#endif
	b	t_glvl_req_set
	nop

signal_depict_end:
//identify wheather there is ecc slice
	GET_NUMBER_OF_SLICES
	li.d	t1, 0x28
	or	t1, t1, t8
reset_rd_oe:
	li.d	t4, 0x350
	or	t4, t4, t8
	ld.b	a0, t4, 0x7
	st.b	a0, t1, 0x7
	st.b	a0, t1, 0x6
	addi.d	t1, t1, 0x20
	li.d  tp, 0x1;  sub.d	t0, t0, tp
	bnez	t0, reset_rd_oe
	nop

	li.d	t1, 0x350 // reset trddata
	or	t1, t1, t8
	ld.b	a0, t1, 0x6
	li.d	t1, 0x1c0
	or	t1, t1, t8
	st.b	a0, t1, 0x0

	GET_NUMBER_OF_SLICES
	li.d     t1, 0x20
	or      t1, t1, t8
11:
	li.d	a0, 0x0
#ifdef DDR_DLL_BYPASS
	li.d	a0, 0x80
#endif
	st.b      a0, t1, OFFSET_DLL_GATE
	li.d  tp, 0x1;  sub.d    t0, t0, tp
	addi.d	t1, t1, 0x20
	bnez    t0, 11b
	nop
	MM_PRINTSTR("\r\n")
#endif

/* gate leveling set 1 to 0 */
	GET_NUMBER_OF_SLICES
	li.d	t1, 0x20
	or	t1, t1, t8
	li.d	t2, 0x180
	or	t2, t2, t8
glvl_req_set0:
	li.d	a0, 0x1
	st.b	a0, t8, 0x181
	li.d	a0, 0x0
	st.b	a0, t8, 0x181

glvl_done_sampling0:
	ld.b	a0, t8, 0x186
	beqz	a0, glvl_done_sampling0
	nop

	li.d     t6, 0x0
glvl_resp_set0:
	ld.b	a0, t2, 0x7
	li.d	t4, 0x3
	and	a0, a0, t4
	beqz	a0, glvl_resp_set0_done
	nop

dll_gate_add0:
	ld.b	a0, t1, OFFSET_DLL_GATE
	addi.d	a0, a0, 0x1
	li.d	t4, 0x7f
	and	a0, a0, t4
#ifdef DDR_DLL_BYPASS
	ld.b	t2, t8, 0x4
	addi.d	t2, t2, 0x2
1:
	blt	a0, t2, 2f
	nop
	sub.d	a0, a0, t2
	b	1b
	nop
2:
	ori	a0, 0x80
#endif
	st.b	a0, t1, OFFSET_DLL_GATE
	li.d	t4, 0x7f
	and	a0, a0, t4
	bnez	a0, 1f
	nop

	ld.b	a0, t1, OFFSET_RDOE_BEGIN
	addi.d	a0, a0, 0x1
	st.b	a0, t1, OFFSET_RDOE_BEGIN
	ld.b	a0, t1, OFFSET_RDOE_END
	addi.d	a0, a0, 0x1
	st.b	a0, t1, OFFSET_RDOE_END
	RDOE_SUB_TRDDATA_ADD
/*
	ld.b	a0, t1, OFFSET_ODTOE_BEGIN
	addi.d	a0, a0, 0x1
	st.b	a0, t1, OFFSET_ODTOE_BEGIN
	ld.b	a0, t1, OFFSET_ODTOE_END
	addi.d	a0, a0, 0x1
	st.b	a0, t1, OFFSET_ODTOE_END
*/
1:
	li.d    tp, MDL_CNT;  beq  t6, tp, 99f; 	li.d    tp, MDL_CNT;  bge     t6, tp, leveling_failed; 99:
	nop
	addi.d   t6, t6, 0x1
	b 	glvl_req_set0
	nop

glvl_resp_set0_done:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\n gate leveling 0 is found\r\n")
#endif
	li.d  tp, 0x1;  sub.d	t0, t0, tp
	addi.d	t1, t1, 0x20
	addi.d	t2, t2, 0x1
	li.d     t6, 0x0
	bnez	t0, glvl_req_set0
	nop

#ifdef  PRINT_DDR_LEVELING   //print registers
	MM_PRINTSTR("\r\nThe MC param after gate leveling 1 to 0 is:\r\n")
	PRINT_THE_MC_PARAM
#endif

/* unknown reason to reset init_start */
reset_init_start:
	li.d     t1, 0x18
	or      t1, t1, t8
	li.d	a0, 0x0
	st.b      a0, t1, 0x0

	li.d     a0, 0x1
	st.b      a0, t1, 0x0

wait_init_done:
	li.d     t1, 0x160
	or      t1, t1, t8
	ld.b      a0, t1, 0x3
	beqz    a0, wait_init_done
	nop

/* 0 to 1 */
	GET_NUMBER_OF_SLICES
	li.d	t1, 0x20
	or	t1, t1, t8
	li.d	t2, 0x180
	or	t2, t2, t8
	li.d	s7, GATE_FILTER_LENGTH
glvl_req_set1:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\ngate leveling req\r\n")
#endif
	li.d	a0, 0x1
	st.b	a0, t8, 0x181
	li.d	a0, 0x0
	st.b	a0, t8, 0x181

glvl_done_sampling1:
	ld.b	a0, t8, 0x186
	beqz	a0, glvl_done_sampling1
	nop

glvl_resp_set1:
	ld.b	a0, t2, 0x7
	li.d	t4, 0x3
	and	a0, a0, t4
	bnez	a0, glvl_resp_set1_done
	nop
	li.d	s7, GATE_FILTER_LENGTH

dll_gate_add1:
	ld.b	a0, t1, OFFSET_DLL_GATE
	addi.d	a0, a0, 0x1
	li.d	t4, 0x7f
	and	a0, a0, t4
#ifdef DDR_DLL_BYPASS
	ld.b	t4, t8, 0x4
	addi.d	t4, t4, 0x2
1:
	blt	a0, t4, 2f
	nop
	sub.d	a0, a0, t4
	b	1b
	nop
2:
	ori	a0, 0x80
#endif
	st.b	a0, t1, OFFSET_DLL_GATE
	li.d	t3, 0x7f
	and	a0, a0, t3
	bnez	a0, 1f
	nop

	ld.b	a0, t1, OFFSET_RDOE_BEGIN
	addi.d	a0, a0, 0x1
	st.b	a0, t1, OFFSET_RDOE_BEGIN
	ld.b	a0, t1, OFFSET_RDOE_END
	addi.d	a0, a0, 0x1
	st.b	a0, t1, OFFSET_RDOE_END
	RDOE_SUB_TRDDATA_ADD
/*
	ld.b	a0, t1, OFFSET_ODTOE_BEGIN
	addi.d	a0, a0, 0x1
	st.b	a0, t1, OFFSET_ODTOE_BEGIN
	ld.b	a0, t1, OFFSET_ODTOE_END
	addi.d	a0, a0, 0x1
	st.b	a0, t1, OFFSET_ODTOE_END
*/
1:
	li.d    tp, MDL_CNT;  beq  t6, tp,  99f; 	li.d    tp, MDL_CNT;  bge     t6, tp,  leveling_failed; 99:
	nop
	addi.d   t6, t6, 0x1
	b 	    glvl_req_set1
	nop

glvl_resp_set1_done:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\n gate leveling 1 is found @ slice")
	li.d	a0, 0x8
	sub.d	a0, a0, t0
	bl 	mm_hexserial
	nop
#endif
	li.d  tp, 0x1;  sub.d	s7, s7, tp
	bnez	s7, dll_gate_add1
	nop
	li.d	s7, GATE_FILTER_LENGTH

//return the more add
	ld.b	a0, t1, OFFSET_DLL_GATE
	andi	a0, a0, 0x7f
	li.d	t4, GATE_FILTER_LENGTH
	li.d  tp, 0x1;  sub.d	t4, t4, tp
	blt	a0, t4, 1f	// if a0 less then t4, sub t4
	nop
	sub.d	a0, a0, t4
#ifdef DDR_DLL_BYPASS
	ori	a0, a0, 0x80
#endif
	st.b	a0, t1, OFFSET_DLL_GATE
	b	2f
	nop
1:
	li.d	a1, 0x80
#ifdef DDR_DLL_BYPASS
	ld.b	a1, t8, 0x4
	addi.d	a1, a1, 0x2
#endif
	ld.b	a0, t1, OFFSET_DLL_GATE
	li.d	t4, GATE_FILTER_LENGTH
	li.d  tp, 0x1;  sub.d	t4, t4, tp
	add.d	a0, a0, a1
	sub.d	a0, a0 ,t4
	st.b	a0, t1, OFFSET_DLL_GATE

	ld.b	a0, t1, OFFSET_RDOE_BEGIN
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	st.b	a0, t1, OFFSET_RDOE_BEGIN
	ld.b	a0, t1, OFFSET_RDOE_END
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	st.b	a0, t1, OFFSET_RDOE_END
	RDOE_ADD_TRDDATA_SUB
/*
	ld.b	a0, t1, OFFSET_ODTOE_BEGIN
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	st.b	a0, t1, OFFSET_ODTOE_BEGIN
	ld.b	a0, t1, OFFSET_ODTOE_END
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	st.b	a0, t1, OFFSET_ODTOE_END
*/
2:

	li.d  tp, 0x1;  sub.d	t0, t0, tp
	addi.d	t1, t1, 0x20
	addi.d	t2, t2, 0x1
	li.d     t6, 0x0
	bnez	t0, glvl_req_set1
	nop



#ifdef  PRINT_DDR_LEVELING   //print registers
	MM_PRINTSTR("\r\nThe MC param after gate leveling 0 to 1 is:\r\n")
	PRINT_THE_MC_PARAM
#endif

#ifdef	PREAMBLE_CHECK_DEBUG

	li.d	s7, 0x8
	li.d     t1, 0x250
	or      t1, t1, t8
	ld.b      a0, t1, 0x2
	li.d     t1, 0x1
	and     a0, a0, t1
	bne     a0, t1, 1f //when rd_after_write enabled, the 9th device may don't need leveling
	nop
	addi.d	s7, s7, 0x1
1:
//	li.d	s7, 0x5
	li.d	t1, 0x28
	or 	t1, t1, t8
	li.d	t2, 0x180
	or	t2, t2, t8

	li.d     t5,     0x0
preamble_check_init:
/* check the preamble exist */
	MM_PRINTSTR("\r\nPREAMBLE CHECK!!\r\n")
// set the gate signal 0.75 period before
	li.d 	s6,	PREAMBLE_LENGTH_3A9 //s6 represents 0.75 period to be checked
	li.d	a3, 0x80
	li.d	t4, 0x0
	or	t4, t4, t8
	ld.b	a0, t4, 0x0
	li.d    tp, 0x2;  beq	a0, tp, 1f
	nop
	li.d	s6, PREAMBLE_LENGTH_3A8
1:
#ifdef DDR_DLL_BYPASS
	ld.b	a2, t8, 0x4
	andi	a2, a2, 0x7f
	addi.d	a2, a2, 0x2
	or	a3, a2, zero
	srli.d	a2, a2, 0x2
	sub.d	a2, a3, a2
	li.d	t4, 0x7f
	and	a2, a2, t4
	or 	s6, a2, zero
#endif

	ld.b	a0, t1, 0x7	// if the rd_oe > 4 the set the rd_oe = 3
	li.d    tp, 0x4;  blt	a0, tp, 1f
	nop
	li.d	a0, 0x3
	st.b	a0, t1, 0x7
1:
	ld.b	a0, t1, 0x6
	li.d    tp, 0x4;  blt	a0, tp, 1f
	nop
	li.d	a0, 0x3
	st.b	a0, t1, 0x6
1:

	ld.b	a0, t1, 0x10
	andi	a0, a0, 0x7f
	bgeu	a0, s6, 1f
	nop
	add.d	a0, a0, a3
	sub.d	a0, a0, s6
#if 0
	or	t4, a0, zero
	bl	mm_hexserial
	nop
2:
	bl	mm_hexserial
	nop
	ld.b	a0, t1, 0x10
	addi.d	a0, a0, 0x1
	st.b	a0, t1, 0x10
	bne	a0, t4, 2b
	nop
#endif
#if 1
#ifdef DDR_DLL_BYPASS
	ori	a0, a0, 0x80
#endif
	st.b	a0, t1, 0x10
#endif
	ld.b	a0, t1, 0x7
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	st.b	a0, t1, 0x7
	ld.b	a0, t1, 0x6
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	st.b	a0, t1, 0x6
	RDOE_ADD_TRDDATA_SUB
	b	3f
	nop
1:
	sub.d	a0, a0, s6
#ifdef DDR_DLL_BYPASS
	ori	a0, a0, 0x80
#endif
	st.b	a0, t1, 0x10
3:
/*	li.d	a0, 0xa1
	st.b	a0, t1, 0x10*/
	li.d t4, 0x180
	or  t4, t4, t8
	li.w	a0, 0x1
	st.b  a0, t4, 0x1
	li.w	a0, 0x0
	st.b	a0, t4, 0x1
	li.w	a0, 0x1
	st.b  a0, t4, 0x1
	li.w	a0, 0x0
	st.b	a0, t4, 0x1

	li.d t3, 0x2
	li.d	t6, 0x5
	andi	s6, s6, 0x7f
	li.d  tp, 0x6;  sub.d	s6, s6, tp
	b 	glvl_redo_req_set_0
	nop
glvl_check_preamble:


	li.d  tp, 0x1;  sub.d	s6, s6, tp
	bnez	s6, 1f
	nop
	addi.d	s6, s6, 0x1
1:

	ld.b      a0, t2, 0x7
	li.d     t4, 0x3
	and     a0, a0, t4

	bnez	a0, test_continuous5_0
	nop
#ifdef LVL_DEBUG
	MM_PRINTSTR("The 1 is not found\r\n")
#endif
	ld.b	a0, t1, 0x10
	addi.d	a0, a0, 0x1
	li.d	t4, 0x7f
	and 	a0, a0, t4
#ifdef DDR_DLL_BYPASS
	ld.b	t4, t8, 0x4
	addi.d	t4, t4, 0x2
1:
	blt	a0, t4, 2f
	nop
	sub.d	a0, a0, t4
	b	1b
	nop
2:
	ori	a0, 0x80
#endif
	st.b	a0, t1, 0x10
	li.d	t4, 0x7f
	and	a0, a0, t4
	bnez	a0,	1f
	nop

	ld.b	a0, t1, 0x6
	addi.d	a0, a0, 0x1
	st.b	a0, t1, 0x6
	ld.b	a0, t1, 0x7
	addi.d	a0, a0, 0x1
	st.b	a0, t1, 0x7
	ld.b	a0, t1, 0x7
	RDOE_SUB_TRDDATA_ADD
1:
	li.d	t6, 0x5
	b 	glvl_redo_req_set_0
	nop

test_continuous5_0:
	li.d  tp, 0x1;  sub.d	t6, t6, tp
	bnez	t6, 1f
	nop
	li.d    tp, 0x1;  beq	s6, tp, glvl_check_preamble_end
	nop
	li.d    tp, GCL_CNT;  beq  t5, tp, 99f; 	li.d    tp, GCL_CNT;  bge     t5, tp, leveling_failed; 99:
	nop
	addi.d   t5, t5, 0x1
	b	glvl_check_preamble_fail
	nop
1:
#ifdef PRINT_PREAMBLE_CHECK
	MM_PRINTSTR("The 1 found in preamble test@")
	or	a0, s6, zero
	bl 	mm_hexserial
	nop
	or	a0, t6, zero
	bl 	mm_hexserial
	nop
	MM_PRINTSTR("\r\n")
#endif

	ld.b	a0, t1, 0x10
	addi.d	a0, a0, 0x1
	li.d	t4, 0x7f
	and 	a0, a0, t4
#ifdef DDR_DLL_BYPASS
	ld.b	t4, t8, 0x4
	addi.d	t4, t4, 0x2
1:
	blt	a0, t4, 2f
	nop
	sub.d	a0, a0, t4
	b	1b
	nop
2:
	ori	a0, 0x80
#endif
	st.b	a0, t1, 0x10
	li.d	t4, 0x7f
	and	a0, a0, t4
	bnez	a0,	1f
	nop

	ld.b	a0, t1, 0x6
	addi.d	a0, a0, 0x1
	st.b	a0, t1, 0x6
	ld.b	a0, t1, 0x7
	addi.d	a0, a0, 0x1
	st.b	a0, t1, 0x7
	ld.b	a0, t1, 0x7
	RDOE_SUB_TRDDATA_ADD
1:
	b	glvl_redo_req_set_0
	nop

glvl_check_preamble_fail:
	MM_PRINTSTR("\r\nThe preamble check failed @")
	or	a0, s6, zero
	bl 	mm_hexserial
	nop
	MM_PRINTSTR("\r\n")

	li.d	s6, 0x0
	ld.b	a0, t1, 0x6
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	st.b	a0, t1, 0x6
	ld.b	a0, t1, 0x7
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	st.b	a0, t1, 0x7
	bnez	a0, 1f
	nop
	MM_PRINTSTR("\r\nThe rd_oe become 0 in the preamble check!\r\n")
	RDOE_ADD_TRDDATA_SUB
1:


	li.d	t3, 0x0
glvl_redo_req_set_0:
	li.d     t4, 0x180
	or      t4, t4, t8
	li.d     a0, 0x1
	st.b      a0, t4, 0x1
	li.d	a0, 0x0
	st.b      a0, t4, 0x1

1:			//glvl_done_sampling
	li.d     t4, 0x180
	or      t4, t4, t8
	ld.b      a0, t4, 0x6
	li.d    tp, 0x1;  bne     a0, tp, 1b
	nop

#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\npreamble req\r\nrd_oe is")
	ld.d	a0, t1, 0x0
	srli.d	a0, a0, 48
	andi	a0, a0, 0xfff
	bl	mm_hexserial
	nop
	ld.b	a0, t8, 0x1c0
	bl	mm_hexserial
	nop
	MM_PRINTSTR("\r\n t1 & t2 is")
	or	a0, t1, zero
	bl	mm_hexserial
	nop
	or	a0, t2, zero
	bl	mm_hexserial
	nop
	MM_PRINTSTR("\r\n 0x118")
	ld.b	a0, t8, 0x118
	bl	mm_hexserial
	nop
#endif

	li.d    tp, 0x1;  beq	t3, tp, glvl_redo_resp_set1_0
	nop

	li.d    tp, 0x2;  beq	t3, tp, glvl_check_preamble
	nop


	li.d	t3, 0x1
#ifdef LVL_DEBUG
	ld.d	a0, t8, 0x188
	srli.d	a0, a0, 32
	bl	mm_hexserial
	nop
#endif
	ld.b      a0, t2, 0x7
	li.d     t4, 0x3
	and     a0, a0, t4
	li.d    tp, 0x0;  beq     a0, tp, glvl_redo_set0_end
	nop
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\nglvl redo set 0 add\r\n")
#endif
	ld.b	a0, t1, 0x10
	addi.d	a0, a0, 0x1
	li.d	t4, 0x7f
	and 	a0, a0, t4
#ifdef DDR_DLL_BYPASS
	ld.b	t4, t8, 0x4
	addi.d	t4, t4, 0x2
1:
	blt	a0, t4, 2f
	nop
	sub.d	a0, a0, t4
	b	1b
	nop
2:
	ori	a0, 0x80
#endif
	st.b	a0, t1, 0x10
#ifdef LVL_DEBUG
	bl	mm_hexserial
	nop
	ld.b	a0, t1, 0x10
#endif
	li.d	t4, 0x7f
	and	a0, a0, t4
	li.d	t3, 0x0
	bnez	a0,	glvl_redo_set0_end
	nop

#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\nrd_oe add 1\r\n")
#endif
	/* rd_oe_begin and rd_oe_end add 1 */
	ld.d      a0, t1, 0x0
	li.d     t4, 0x0101000000000000
	add.d   a0, a0, t4
	st.d      a0, t1, 0x0
	ld.b	a0, t1, 0x7
	RDOE_SUB_TRDDATA_ADD
	/* odt_oe_begin and odt_oe_end add 1 */
	ld.d      a0, t1, 0x8
	li.d     t4, 0x0000000001010000
	add.d   a0, a0, t4
	st.d      a0, t1, 0x8

glvl_redo_set0_end:
	b	glvl_redo_req_set_0
	nop

glvl_redo_resp_set1_0:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\nglvl redo resp set 1\r\n")
#endif
	ld.b      a0, t2, 0x7
	li.d     t4, 0x3
	and     a0, a0, t4
	bnez    a0, preamble_check_init
	nop

	ld.b	a0, t1, 0x10
	addi.d	a0, a0, 0x1
	li.d	t4, 0x7f
	and 	a0, a0, t4
#ifdef DDR_DLL_BYPASS
	ld.b	t4, t8, 0x4
	addi.d	t4, t4, 0x2
1:
	blt	a0, t4, 2f
	nop
	sub.d	a0, a0, t4
	b	1b
	nop
2:
	ori	a0, 0x80
#endif
	st.b	a0, t1, 0x10
#ifdef LVL_DEBUG
	bl	mm_hexserial
	nop
	ld.b	a0, t1, 0x10
#endif
	li.d	t4, 0x7f
	and	a0, a0, t4
	bnez	a0,	1f
	nop

#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\nrd oe add 1 @ glvl redo add\r\n")
#endif
	/* rd_oe_begin and rd_oe_end add 1 */
	ld.d      a0, t1, 0x0
	li.d     t4, 0x0101000000000000
	add.d   a0, a0, t4
	st.d      a0, t1, 0x0
	ld.b	a0, t1, 0x7
	RDOE_SUB_TRDDATA_ADD
	/* odt_oe_begin and odt_oe_end add 1 */
	ld.d      a0, t1, 0x8
	li.d     t4, 0x0000000001010000
	add.d   a0, a0, t4
	st.d      a0, t1, 0x8

1:

	b	glvl_redo_req_set_0
	nop


glvl_check_preamble_end:
#ifdef  PRINT_PREAMBLE_CHECK   //print registers
	MM_PRINTSTR("\r\nThe MC param after preamble check is:\r\n")
	PRINT_THE_MC_PARAM
#endif
	li.d	s6, 0x0
	MM_PRINTSTR("\r\nThe preamble check success\r\n")

	ld.b	a0, t1, 0x7
	li.d    tp, 0x4;  blt	a0, tp, 1f
	nop
	li.d  tp, 0x4;  sub.d	a0, a0, tp
	st.b	a0, t1, 0x7
	st.b	a0, t1, 0x6
	RDOE_ADD_TRDDATA_SUB
1:
	li.d	a3, 0x80
#ifdef DDR_DLL_BYPASS
	ld.b	a3, t8, 0x4
	addi.d	a3, a3, 0x2
	andi	a3, a3, 0x7f
#endif
	ld.b	a0, t1, 0x10
	andi	a0, a0, 0x7f
	li.d    tp, 0x4;  bgeu	a0, tp, 1f
	nop
	add.d	a0, a0, a3
	li.d  tp, 0x4;  sub.d	a0, a0, tp
#ifdef DDR_DLL_BYPASS
	ori	a0, a0, 0x80
#endif
	st.b	a0, t1, 0x10

	ld.b	a0, t1, 0x7
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	st.b	a0, t1, 0x7
	ld.b	a0, t1, 0x6
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	st.b	a0, t1, 0x6
	RDOE_ADD_TRDDATA_SUB
1:
	li.d  tp, 0x4;  sub.d	a0, a0, tp
#ifdef DDR_DLL_BYPASS
	ori	a0, a0, 0x80
#endif
	st.b	a0, t1, 0x10

#if 1
/* unknown reason to reset init_start */
	li.d     t4, 0x18
	or      t4, t4, t8
	li.d     a0, 0x0
	st.b      a0, t4, 0x0

	li.d     t4, 0x18
	or      t4, t4, t8
	li.d     a0, 0x1
	st.b      a0, t4, 0x0
1:
	li.d     t4, 0x160
	or      t4, t4, t8
	ld.b      a0, t4, 0x3
	beqz    a0, 1b
	nop
#endif

#if 0
get_burst_length: //save in a6
	li.d	t4, 0x168
	or	t4, t4, t8
	ld.b	a6, t4, 0x4
	addi.d	a6, a6, 0x1
	srli.d	a6, a6, 0x1

	li.d	t4, 0x180//send glvl request
	or	t4, t4, t8
	li.d	a0, 0x1
	st.b	a0, t4, 0x1
1:
	ld.b	a0, t4, 0x6 //glvl done
	li.d    tp, 0x1;  bne	a0, tp, 1b
	nop
	ld.b	s3, t2, 0x7

	li.d	t4, 0x180
	or	t4, t4, t8
	li.d	a0, 0x1
	st.b	a0, t4, 0x1
1:
	ld.b	a0, t4, 0x6
	li.d    tp, 0x1;  bne	a0, tp, 1b
	nop
	ld.b	t6, t2, 0x7

//glvl response check
	li.d	t4, 0x1c
	and	s3, s3, t4
	and	t6, t6, t4
	srli.d	s3, s3, 0x2
	srli.d	t6, t6, 0x2
	li.d    tp, 0x4;  blt	s3, tp, 1f
	nop
	or	t6, t6, 0x8
1:
	sub.d	t6, t6, s3
	beq	t6, a6, glvl_last_check_end
	nop

	ld.b	a0, t1, 0x7
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	st.b	a0, t1, 0x7
	ld.b	a0,	t1, 0x6
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	st.b	a0, t1, 0x6
	RDOE_ADD_TRDDATA_SUB
	MM_PRINTSTR("\r\nThe edges number is incorrect!\r\n")
	b	preamble_check_init
	nop
#endif
glvl_last_check_end:
	addi.d	t1, t1, 0x20
	addi.d	t2, t2, 0x1
	li.d  tp, 0x1;  sub.d	s7, s7, tp
	li.d     t5,     0x0
	bnez	s7, preamble_check_init
	nop
#endif

/* set rddqs_lt_half */
	GET_NUMBER_OF_SLICES
	li.d	t1, 0x20
	or	t1, t1, t8
rddqs_lt_half_set:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\nsetting rddqs lt_half\r\n")
#endif
	ld.b	a0, t1, OFFSET_DLL_GATE
	li.d	t4, 0x7f
	and	a0, a0, t4
#ifdef DDR_DLL_BYPASS
	slli.d    a0, a0, 0x7 // x 128
	ld.w      t5, t8, 0x4 //get dll_ck value, store at t5
	addi.d   t5, t5, 0x2
	div.du    a0, a0, t5 //get dll_gate, no bypass mode
#endif
	ld.b	a1, t1, OFFSET_DLL_WRDQ
	add.d	a0, a0, a1
	and	a0, a0, t4
#if 0
	or	a1, a0, zero
	bl	mm_hexserial
	nop
	or	a0, a1, zero
#endif
	li.d    tp, RDDQS_LTHF_STD1;  bgeu	a0, tp, rddqs_lthalf_set1
	nop
	li.d    tp, RDDQS_LTHF_STD2;  bltu	a0,	tp, rddqs_lthalf_set1
	nop
	b	rddqs_lthalf_set0
	nop
rddqs_lthalf_set0:
	li.d	a0, 0x0
	st.b	a0, t1, OFFSET_RDDQS_LTHF
	b	1f
	nop
rddqs_lthalf_set1:
	li.d	a0, 0x1
	st.b	a0, t1, OFFSET_RDDQS_LTHF
1:
	addi.d	t1, t1, 0x20
	li.d  tp, 0x1;  sub.d	t0, t0, tp
	bnez	t0, rddqs_lt_half_set
	nop

#if 1
/* unknown reason to reset init_start */
	li.d     t4, 0x18
	or      t4, t4, t8
	li.d     a0, 0x0
	st.b      a0, t4, 0x0

	li.d     t4, 0x18
	or      t4, t4, t8
	li.d     a0, 0x1
	st.b      a0, t4, 0x0
1:
	li.d     t4, 0x160
	or      t4, t4, t8
	ld.b      a0, t4, 0x3
	beqz    a0, 1b
	nop
#endif

#if 1
	GET_NUMBER_OF_SLICES
	li.d	t1, 0x20
	or	t1, t1, t8
dll_gate_set_loop:
	beqz     t0, gate_sub_end
	nop
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\n setting dll_gate_sub \r\n")
#endif
#ifdef DDR_DLL_BYPASS
	ld.b      a2, t8, 0x4 //dll_value_ck
	addi.d   a2, a2, 0x2
	or	a3, a2, zero
	srli.d    a2, a2, 0x2
	li.d     t4, 0xff
	and     a2, a2, t4
#else
	li.d	a3, 0x80
	li.d     a2, DLL_GATE_SUB
#endif
	ld.b      a0, t1, OFFSET_DLL_GATE
	andi	a0, a0, 0x7f
	bgeu    a0, a2, dll_gate_sub20
	nop
#ifdef DDR_DLL_BYPASS
	ori     a0, a0, 0x80
	sub.d	a0, a0, a2
	add.d	a0, a0, a3
#else
	add.d	a0, a0, a3
	sub.d	a0, a0, a2
#endif
	st.b      a0, t1, OFFSET_DLL_GATE

	ld.b	a0, t1, OFFSET_RDOE_BEGIN
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	st.b	a0, t1, OFFSET_RDOE_BEGIN
	ld.b	a0, t1, OFFSET_RDOE_END
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	st.b	a0, t1, OFFSET_RDOE_END
	RDOE_ADD_TRDDATA_SUB
/*
	ld.b	a0, t1, OFFSET_ODTOE_BEGIN
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	st.b	a0, t1, OFFSET_ODTOE_BEGIN
	ld.b	a0, t1, OFFSET_ODTOE_END
	li.d  tp, 0x1;  sub.d	a0, a0, tp
	st.b	a0, t1, OFFSET_ODTOE_END
*/
	addi.d	t1, t1, 0x20
	li.d  tp, 0x1;  sub.d	t0, t0, tp
	b       dll_gate_set_loop
	nop
dll_gate_sub20:
	sub.d    a0, a0, a2
#ifdef DDR_DLL_BYPASS
	ori     a0, a0, 0x80
#endif
	st.b      a0, t1, OFFSET_DLL_GATE
	addi.d	t1, t1, 0x20
	li.d  tp, 0x1;  sub.d	t0, t0, tp
	b       dll_gate_set_loop
	nop
gate_sub_end:
#endif

#ifdef NO_EDGE_CHECK
#else
#if 1
/* unknown reason to reset init_start */
	li.d     t1, 0x18
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t4, 0xffffffffffffff00
	and     a0, a0, t4
	st.d      a0, t1, 0x0

	li.d     t1, 0x18
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t4, 0xffffffffffffff00
	and     a0, a0, t4
	ori     a0, a0, 0x1
	st.d      a0, t1, 0x0

1:
	li.d     t1, 0x160
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t4, 0x00000000ff000000
	and     a0, a0, t4
	beqz    a0, 1b
	nop
#endif

rd_oe_sub:

get_burst_length_half: //save in a6
	li.d     t1, 0x168
	or      t1, t1, t8
	ld.d      a6, t1, 0x0
	li.d     t4, 0x000000ff00000000
	and     a6, a6, t4
	li.d tp, 0x0000000100000000; add.d   a6, a6, tp
	srli.d    a6, a6, 33 // div 2


	li.d     s6, 0x1
glvl_req_set_last_0:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\n last 0 req")
#endif
	li.d     t1, 0x180
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t4, 0xffffffffffff00ff
	and     a0, a0, t4
	ori     a0, a0, 0x100
	st.d      a0, t1, 0x0

	li.d     a1, 0x1
glvl_done_sampling_last_0:
	li.d     t1, 0x180
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t4, 0x00ff000000000000
	and     a0, a0, t4
	srli.d    a0, a0, 48
	bne     a0, a1, glvl_done_sampling_last_0
	nop

glvl_resp_last_0:
	li.d     s7, 0x0
	li.d     t1, 0x180
	or      t1, t1, t8
	ld.d      s3, t1, 0x0 //save 0x180
	ld.d      s4, t1, 0x8 //save 0x188

glvl_req_set_last_1:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\n last 1 req")
#endif
	li.d     t1, 0x180
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t4, 0xffffffffffff00ff
	and     a0, a0, t4
	ori     a0, a0, 0x100
	st.d      a0, t1, 0x0

	li.d     a1, 0x1
glvl_done_sampling_last_1:
	li.d     t1, 0x180
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t4, 0x00ff000000000000
	and     a0, a0, t4
	srli.d    a0, a0, 48
	bne     a0, a1, glvl_done_sampling_last_1
	nop

glvl_resp_last_1:
	li.d     t1, 0x180
	or      t1, t1, t8
	ld.d      t2, t1, 0x0 //lvl_resp 0
	ld.d      t6, t1, 0x8 //lvl_resp 1-8

#if 1 // print the two sequence samples of leveling responds
#ifdef LVL_DEBUG
	or    t6, s3, zero
	li.d     a0, 0x180
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

	or    t6, s4, zero
	li.d     a0, 0x188
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

	li.d     t1, 0x180
	or      t1, t1, t8
	ld.d      t6, t1, 0x0 //lvl_resp 0
	or    a0, t1, zero
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

	li.d     t1, 0x188
	or      t1, t1, t8
	ld.d      t6, t1, 0x0 //lvl_resp 0
	or    a0, t1, zero
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
#endif
#endif

	li.d     t1, 0x180
	or      t1, t1, t8
	ld.d      t2, t1, 0x0 //lvl_resp 0
	ld.d      t6, t1, 0x8 //lvl_resp 1-8

#if 1 //debug
glvl_resp_check_0:
	li.d     t4, 0x1c00000000000000
	and     t3, t2, t4 //second sample
	and     t5, s3, t4 //first sample
	srli.d    t3, t3, 58
	srli.d    t5, t5, 58
	li.d     t4, 0x4
	bge     t5, t4, 1f //lvl_resp[4:2] ge 0x4
	nop
	b       2f
	nop
1:
	ori     t3, t3, 0x8
2:
	sub.d   t3, t3, t5
	bne     t3, a6, rd_oe_0_sub
	nop

glvl_resp_check_1:
	li.d     t4, 0x000000000000001c
	and     t3, t6, t4 //second sample
	and     t5, s4, t4 //first sample
	srli.d    t3, t3, 2
	srli.d    t5, t5, 2
	li.d     t4, 0x4
	bge     t5, t4, 1f
	nop
	b       2f
	nop
1:
	ori     t3, t3, 0x8
2:
	sub.d   t3, t3, t5
	bne     t3, a6, rd_oe_1_sub
	nop

glvl_resp_check_2:
	li.d     t4, 0x0000000000001c00
	and     t3, t6, t4 //second sample
	and     t5, s4, t4 //first sample
	srli.d    t3, t3, 10
	srli.d    t5, t5, 10
	li.d     t4, 0x4
	bge     t5, t4, 1f
	nop
	b       2f
	nop
1:
	ori     t3, t3, 0x8
2:
	sub.d   t3, t3, t5
	bne     t3, a6, rd_oe_2_sub
	nop

glvl_resp_check_3:
	li.d     t4, 0x00000000001c0000
	and     t3, t6, t4 //second sample
	and     t5, s4, t4 //first sample
	srli.d    t3, t3, 18
	srli.d    t5, t5, 18
	li.d     t4, 0x4
	bge     t5, t4, 1f
	nop
	b       2f
	nop
1:
	ori     t3, t3, 0x8
2:
	sub.d   t3, t3, t5
	bne     t3, a6, rd_oe_3_sub
	nop

glvl_resp_check_4:
	li.d     t4, 0x000000001c000000
	and     t3, t6, t4 //second sample
	and     t5, s4, t4 //first sample
	srli.d    t3, t3, 26
	srli.d    t5, t5, 26
	li.d     t4, 0x4
	bge     t5, t4, 1f
	nop
	b       2f
	nop
1:
	ori     t3, t3, 0x8
2:
	sub.d   t3, t3, t5
	bne     t3, a6, rd_oe_4_sub
	nop

glvl_resp_check_5:
	li.d     t4, 0x0000001c00000000
	and     t3, t6, t4 //second sample
	and     t5, s4, t4 //first sample
	srli.d    t3, t3, 34
	srli.d    t5, t5, 34
	li.d     t4, 0x4
	bge     t5, t4, 1f
	nop
	b       2f
	nop
1:
	ori     t3, t3, 0x8
2:
	sub.d   t3, t3, t5
	bne     t3, a6, rd_oe_5_sub
	nop

glvl_resp_check_6:
	li.d     t4, 0x00001c0000000000
	and     t3, t6, t4 //second sample
	and     t5, s4, t4 //first sample
	srli.d    t3, t3, 42
	srli.d    t5, t5, 42
	li.d     t4, 0x4
	bge     t5, t4, 1f
	nop
	b       2f
	nop
1:
	ori     t3, t3, 0x8
2:
	sub.d   t3, t3, t5
	bne     t3, a6, rd_oe_6_sub
	nop

glvl_resp_check_7:
	li.d     t4, 0x001c000000000000
	and     t3, t6, t4 //second sample
	and     t5, s4, t4 //first sample
	srli.d    t3, t3, 50
	srli.d    t5, t5, 50
	li.d     t4, 0x4
	bge     t5, t4, 1f
	nop
	b       2f
	nop
1:
	ori     t3, t3, 0x8
2:
	sub.d   t3, t3, t5
	bne     t3, a6, rd_oe_7_sub
	nop

glvl_resp_check_8:
/* identify wheather there is ecc slice */
	li.d     t1, 0x250
	or      t1, t1, t8
	ld.b      a0, t1, 0x2
	li.d     t1, 0x1
	and     a0, a0, t1
	bne     a0, t1, 3f //when rd_after_write enabled, the 9th device may don't need leveling
	nop

	li.d     t4, 0x1c00000000000000
	and     t3, t6, t4 //second sample
	and     t5, s4, t4 //first sample
	srli.d    t3, t3, 58
	srli.d    t5, t5, 58
	li.d     t4, 0x4
	bge     t5, t4, 1f
	nop
	b       2f
	nop
1:
	ori     t3, t3, 0x8
2:
	sub.d   t3, t3, t5
	bne     t3, a6, rd_oe_8_sub
	nop

3:
	beq     s7, s6, rd_oe_sub
	nop

	b       gate_leveling_exit
	nop

rd_oe_0_sub:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\n rd_oe_0 and rd_odt_0 sub")
#endif
	li.d     t1, 0x028
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0101000000000000
	sub.d   a0, a0, t2
	st.d      a0, t1, 0x0

	li.d     t1, 0x030
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0000000001010000
	sub.d   a0, a0, t2
	st.d      a0, t1, 0x0
	li.d     s7, 0x1
	b       glvl_resp_check_1

rd_oe_1_sub:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\n rd_oe_1 and rd_odt_1 sub")
#endif
	li.d     t1, 0x048
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0101000000000000
	sub.d   a0, a0, t2
	st.d      a0, t1, 0x0

	li.d     t1, 0x050
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0000000001010000
	sub.d   a0, a0, t2
	st.d      a0, t1, 0x0
	li.d     s7, 0x1
	b       glvl_resp_check_2

rd_oe_2_sub:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\n rd_oe_2 and rd_odt_2 sub")
#endif
	li.d     t1, 0x068
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0101000000000000
	sub.d   a0, a0, t2
	st.d      a0, t1, 0x0

	li.d     t1, 0x070
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0000000001010000
	sub.d   a0, a0, t2
	st.d      a0, t1, 0x0
	li.d     s7, 0x1
	b       glvl_resp_check_3

rd_oe_3_sub:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\n rd_oe_3 and rd_odt_3 sub")
#endif
	li.d     t1, 0x088
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0101000000000000
	sub.d   a0, a0, t2
	st.d      a0, t1, 0x0

	li.d     t1, 0x090
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0000000001010000
	sub.d   a0, a0, t2
	st.d      a0, t1, 0x0
	li.d     s7, 0x1
	b       glvl_resp_check_4

rd_oe_4_sub:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\n rd_oe_4 and rd_odt_4 sub")
#endif
	li.d     t1, 0x0a8
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0101000000000000
	sub.d   a0, a0, t2
	st.d      a0, t1, 0x0

	li.d     t1, 0x0b0
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0000000001010000
	sub.d   a0, a0, t2
	st.d      a0, t1, 0x0
	li.d     s7, 0x1
	b       glvl_resp_check_5

rd_oe_5_sub:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\n rd_oe_5 and rd_odt_5 sub")
#endif
	li.d     t1, 0x0c8
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0101000000000000
	sub.d   a0, a0, t2
	st.d      a0, t1, 0x0

	li.d     t1, 0x0d0
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0000000001010000
	sub.d   a0, a0, t2
	st.d      a0, t1, 0x0
	li.d     s7, 0x1
	b       glvl_resp_check_6

rd_oe_6_sub:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\n rd_oe_6 and rd_odt_6 sub")
#endif
	li.d     t1, 0x0e8
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0101000000000000
	sub.d   a0, a0, t2
	//st.d      a0, t1, 0x0

	li.d     t1, 0x0f0
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0000000001010000
	sub.d   a0, a0, t2
	//st.d      a0, t1, 0x0
	li.d     s7, 0x1
	b       glvl_resp_check_7

rd_oe_7_sub:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\n rd_oe_7 and rd_odt_7 sub")
#endif
	li.d     t1, 0x108
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0101000000000000
	sub.d   a0, a0, t2
	st.d      a0, t1, 0x0

	li.d     t1, 0x110
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0000000001010000
	sub.d   a0, a0, t2
	st.d      a0, t1, 0x0
	li.d     s7, 0x1
	b       glvl_resp_check_8

rd_oe_8_sub:
#ifdef LVL_DEBUG
	MM_PRINTSTR("\r\n rd_oe_8 and rd_odt_8 sub")
#endif
	li.d     t1, 0x128
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0101000000000000
	sub.d   a0, a0, t2
	st.d      a0, t1, 0x0

	li.d     t1, 0x130
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t2, 0x0000000001010000
	sub.d   a0, a0, t2
	st.d      a0, t1, 0x0
	li.d     s7, 0x1
	b       rd_oe_sub

#endif //debug
#endif

gate_leveling_exit:
	li.d     t1, 0x180
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t4, 0xffffffffffffff00
	and     a0, a0, t4
	st.d      a0, t1, 0x0


//   li.d      t1, 0x0000002020187803
//   st.d       t1, t8, 0xb8
/* unknown reason to reset init_start */
reset_init_start3:
	li.d     t1, 0x18
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t4, 0xffffffffffffff00
	and     a0, a0, t4
	st.d      a0, t1, 0x0

	li.d     t1, 0x18
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t4, 0xffffffffffffff00
	and     a0, a0, t4
	ori     a0, a0, 0x1
	st.d      a0, t1, 0x0

wait_init_done3:
	li.d     t1, 0x160
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t4, 0x00000000ff000000
	and     a0, a0, t4
	beqz    a0, wait_init_done3
	nop

#ifdef DDR_DLL_BYPASS //bypass dll_wrdqs, dll_wrdata and  dll_rddqs_p/n
	li.d     t1, 0x0
	or      t1, t1, t8
	ld.d      a1, t1, 0x0
	li.d     t4, 0x0000ffff00000000
	and     a1, a1, t4
	srli.d    a1, a1, 32 // dll_value store in a1
//	add.d   a1, a1, 0x2

/* identify wheather there is ecc slice */
	li.d     t1, 0x250
	or      t1, t1, t8
	ld.b      a0, t1, 0x2
	li.d     t1, 0x1
	and     a0, a0, t1
	bne     a0, t1, 1f //when rd_after_write enabled, the 9th device may don't need leveling
	nop
	li.d     t3, 0x9 //loop times
	b       2f
	nop

1:
	li.d     t3, 0x8 //loop times

2:

	li.d     t1, 0x38
	or      t1, t1, t8
3:
	//set dll_wrdata
	ld.b      a0, t1, 0x1
	mul.d  a0, a1, a0
	srli.d    a0, a0, 0x7
	ori     a0, a0, 0x80
	st.b      a0, t1, 0x1

	//set dll_wrdqs
	ld.b      a0, t1, 0x2
	mul.d  a0, a1, a0
	srli.d    a0, a0, 0x7
	ori     a0, a0, 0x80
	st.b      a0, t1, 0x2

	//set dll_rddqs_p
	ld.b      a0, t1, 0x3
	mul.d  a0, a1, a0
	srli.d    a0, a0, 0x7
	ori     a0, a0, 0x80
	st.b      a0, t1, 0x3

	//set dll_rddqs_n
	ld.b      a0, t1, 0x4
	mul.d  a0, a1, a0
	srli.d    a0, a0, 0x7
	ori     a0, a0, 0x80
	st.b      a0, t1, 0x4

	li.d  tp, 0x1;  sub.d    t3, t3, tp
	addi.d   t1, t1, 0x20
	bnez    t3, 3b
	nop

#endif

#ifdef PM_DPD_FRE
//when rd_oe_start/stop is set to 0x2, the rddqs_lt_half should.d be reversed
//because the rd_oe_start/stop only changed in this file, and all the rd_oe_start/stop change at the same time, here we only consider the rd_oe_start/stop of slice0
	ld.h      a0, t8, 0x2c
	li.d     t4, 0x0202
	bne     t4, a0, 3f
	nop

/* identify wheather there is ecc slice */
	li.w      t0, 0x8
	li.d     t1, 0x250
	or      t1, t1, t8
	ld.b      a0, t1, 0x2
	li.d     t1, 0x1
	and     a0, a0, t1
	bne     a0, t1, 1f //when rd_after_write enabled, the 9th device may don't need leveling
	nop
	addi.d   t0, t0, 0x1

1:

	li.d     t1, 0x20
	or      t1, t1, t8

2:
	ld.b      a0, t1, 0x2
	xori    a0, a0, 0x1
	st.b      a0, t1, 0x2
	addi.d   t1, t1, 0x20
	li.d  tp, 0x1;  sub.d   t0, t0, tp
	bnez    t0, 2b
	nop

3:

#endif




100:
#if 0
test_memory:
	li.d     t0, PHYS_TO_UNCACHED(0x00000000)
	GET_NODE_ID_a0
	or      t0, t0, a0
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

	li.d     t5, PHYS_TO_UNCACHED(0x00000000)
	GET_NODE_ID_a0
	or      t5, t5, a0
	ld.d      t6, t5, 0x30
	li.d     t2, 0x5555555555555555
	beq	t6, t2, 2f
	nop
	ld.d	t6, t5, 0x20
	beq	t6, t2, 2f
	nop
	ld.d	t6, t5, 0x10
	beq	t6, t2, 2f
	nop
	ld.d	t6, t5, 0x00
	beq	t6, t2, 3f
	nop
	MM_PRINTSTR("\r\nthe memory test failed!\r\n")
	b	4f
	nop

2:
	li.d	t1, 0x1d0
	or	t1, t1, t8
	ld.b	a0, t1, 0x4
	li.d  tp, 0x1;  sub.d	a0,	a0, tp
	st.b	a0, t1, 0x4
	b	test_memory
	nop
3:
	MM_PRINTSTR("the memory test sucess!\r\n")
	nop
4:
#endif
//set pm_dll_bypass
	li.d     t1, 0x1
	st.b      t1, t8, 0x19
//remove dll_close_disable and dll_reync_disable
	li.d     t1, 0x0
	st.b      t1, t8, 0x7

leveling_failed:
	MM_PRINTSTR("Leveling failed!\r\n")
	li.d     t1, 0x180
	or      t1, t1, t8
	ld.d      a0, t1, 0x0
	li.d     t4, 0xffffffffffffff00
	and     a0, a0, t4
	st.d      a0, t1, 0x0

	or    ra, s5, zero
    jirl    zero, ra, 0
	nop

LEAF(hexserial4)
	or	a2, ra, zero
	or	a1, a0, zero
	li.w	a3, 0
1:
	rotri.w	a0, a1, 4
	or	a1, a0, zero
	andi	a0, a0, 0xf
	la	a4, hexchar
	add.w	a4, a4, s0
//    sub.d   a4, a4, s0
	add.w	a4, a4, a0
	ld.bu	a0, a4, 0
	bl	mm_tgt_putchar

	addi.w	a3, a3, -1
	bnez	a3, 1b

	or	ra, a2, zero
    jirl    zero, ra, 0
	nop
END(hexserial4)
