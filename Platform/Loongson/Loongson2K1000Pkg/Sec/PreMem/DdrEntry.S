#include "PmonDefs.h"
	.text
ASM_GLOBAL ASM_PFX(DdrEntryAsm)
ASM_PFX(DdrEntryAsm):
	addi.d	$sp, $sp, -16
	st.d	$ra, $sp, 0
	st.d	$s2, $sp, 8
/*
 * Copyright (c) 2021 Loongson Technology Corporation Limited (www.loongson.cn)
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *  This product includes software developed by Opsycon AB, Sweden.
 * 4. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS
 * OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 * NOTE: All ddr code is based on the mips-ls2k. We translate mips to loongarch
 *       with the following changes:
 *           1. Replace `v0/v1/t9` with `a4/a5/a6`.
 *           2. Use `tp` to store a temporary value as 'at'.
 *           3. Temporary use of MM_PRINTSTR to avoid damaging A4, A5,
 *               mm_hexserial[64], and so on.
 *           4. Deleted some temporarily unnecessary files.
 */

#include "ddr_dir/ddr_entry.h"

    MM_PRINTSTR("\r\nStart Init Memory, wait a while......\r\n")
####################################
    or    msize, zero, zero
    or    s3, zero, zero
//!!!!important--s1 must be correctly set

    MM_PRINTSTR("NODE 0 MEMORY CONFIG BEGIN\r\n")
#ifdef  AUTO_DDR_CONFIG
    li.d     s1, 0xff100004  //set use MC1 or MC0 or MC1/0 and give All device id
#else
	//li.d     s1, 0xc2e30400c2e30404
	#ifdef DDR_S1
	li.d     s1, DDR_S1
	#else
	li.d     s1, 0xf0a31004
	#endif
#endif
#include "ddr_dir/loongson3_ddr2_config.S"

//close default internal mapping in ddr controller
	li.d      t0, PHYS_TO_UNCACHED(0x1fe00424)
	ld.b      a0, t0, 0x1
	andi     a0, a0, 0xfd
	st.b      a0, t0, 0x1
	dbar 0

	li.d      t0, PHYS_TO_UNCACHED(0x1fe00420)
	ld.d      a0, t0, 0x0
	or    t6, a0, zero
	srli.d    a0, t6, 32
	bl     mm_hexserial
	nop
	or    a0, t6, zero
	bl     mm_hexserial
	nop
	MM_PRINTSTR("\r\n")

/* test memory */
    li.d      t0, 0x9000000000000000
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

	addi.d  t1, t1, -1
	addi.d  t5, t5, 8
	bnez    t1, 1b
	nop

	MM_PRINTSTR("The cached  data is:\r\n")
	li.d     t1, 8
	li.d     t5, 0x9000000000000000
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
##########################################
#ifdef  DEBUG_DDR
	MM_PRINTSTR("\r\nDo test?(0xf: skip): ")
	bl     inputaddress
	nop
	andi     a4, a4, 0xf
	li.d     a1, 0x1
	bgt     a4, a1, back_start
	nop
	li.d     s1, 0x0010000080000000
	MM_PRINTSTR("\r\ndefault s1 = 0x");
	srli.d    a0, s1, 32
	bl     mm_hexserial
	nop
	MM_PRINTSTR("__")
	or    a0, s1, zero
	bl     mm_hexserial
	nop
	MM_PRINTSTR("\r\nChange test param s1(0: skip)?: ")
	bl     inputaddress
	nop
	beqz    a4, 1f
	nop
	or    s1, a4, zero
1:
	li.d     t1, 0x0010
	bl     test_mem
	nop
	or    t1, a4, zero
	MM_PRINTSTR("\r\n")
	srli.d    a0, t1, 32
	bl     mm_hexserial
	nop
	or    a0, t1, zero
	bl     mm_hexserial
	nop
	beqz    t1, back_start
	nop
	MM_PRINTSTR("  Error found!!\r\n")

//2:
#endif
    b   back_start
#ifdef  AUTO_ARB_LEVEL
#include "ddr_dir/store_auto_arb_level_info.S"
#endif

#include "ddr_dir/memdebug.S"

#include "i2c.S"


#######################################
#ifdef  AUTO_DDR_CONFIG
#include "ddr_dir/detect_node_dimm_all.S"
#endif

#######################################
#include "ddr_dir/ls3A8_ddr_config.S"
#ifdef DDR3_DIMM
#include "ddr_dir/loongson3C_ddr3_leveling.S"
#endif
#ifdef ARB_LEVEL
#include "ddr_dir/ARB_level_new.S"
#endif
#ifdef  DEBUG_DDR
#include "ddr_dir/Test_Mem.S"
#endif
back_start:
	ld.d	$s2, $sp, 8
	ld.d	$ra, $sp, 0
	addi.d	$sp, $sp, 16
	jr	$ra
