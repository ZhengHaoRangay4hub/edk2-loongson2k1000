#------------------------------------------------------------------------------
#
# Early serial helpers, faithful ports of the PMON start.S LEAF routines.
# The DDR/clock assembly (memdebug.S, la_2k1000_clksetting.S) calls these.
#
# SPDX-License-Identifier: BSD-2-Clause-Patent
#
#------------------------------------------------------------------------------

#ifndef __ASSEMBLY__
#define __ASSEMBLY__
#endif

#include "PmonDefs.h"

	.text

#------------------------------------------------------------------------------
# initserial - program UART0 for 115200 8N1 at the pre-PLL clock
#------------------------------------------------------------------------------
ASM_GLOBAL ASM_PFX(initserial)
ASM_PFX(initserial):
	li.d	$a0, COM1_BASE_ADDR
	li.w	$a1, 0x80		# DLAB
	st.b	$a1, $a0, 3
	li.w	$a1, 0			# DLL hi
	st.b	$a1, $a0, 1
	li.w	$a1, 0x36		# DLL lo (54)
	st.b	$a1, $a0, 0
	li.w	$a1, 3			# 8N1
	st.b	$a1, $a0, 3
	li.w	$a1, 71			# FIFO
	st.b	$a1, $a0, 2
	jirl	$zero, $ra, 0

#------------------------------------------------------------------------------
# initserial_later - reprogram UART after PLL bring-up (125MHz APB clock)
#------------------------------------------------------------------------------
ASM_GLOBAL ASM_PFX(initserial_later)
ASM_PFX(initserial_later):
	li.d	$a0, COM1_BASE_ADDR
	li.w	$a1, 0x80
	st.b	$a1, $a0, 3
	li.w	$a1, 0
	st.b	$a1, $a0, 1
	li.w	$a1, 68			# 125M / (68 * 16) ~ 115200
	st.b	$a1, $a0, 0
	li.w	$a6, 0x40000
1:
	ld.bu	$a2, $a0, 5
	andi	$a2, $a2, 0x20
	bnez	$a2, .Llater_tx_ready
	addi.w	$a6, $a6, -1
	bnez	$a6, 1b
.Llater_tx_ready:
	li.w	$a1, 3
	st.b	$a1, $a0, 3
	li.w	$a1, 71
	st.b	$a1, $a0, 2
	jirl	$zero, $ra, 0

#------------------------------------------------------------------------------
# tgt_putchar - blocking char output (a0 = char)
#
# Writes to the console UART and mirrors the byte to the RS232 debug port, so
# a 3.3V TTL adapter on the LVTTL pins and the old RS232 wiring both work.
#------------------------------------------------------------------------------
ASM_GLOBAL ASM_PFX(tgt_putchar)
ASM_PFX(tgt_putchar):
	li.d	$a1, COM1_BASE_ADDR
	li.w	$a6, 0x40000
1:
	ld.bu	$a2, $a1, 0x5
	andi	$a2, $a2, 0x20
	bnez	$a2, .Ltgt_tx_ready
	addi.w	$a6, $a6, -1
	bnez	$a6, 1b
.Ltgt_tx_ready:
	st.b	$a0, $a1, 0

	/*
	 * Mirrors: the same character on the other three debug UARTs.  The wait
	 * for "transmitter ready" is bounded here -- an ungated UART can return a
	 * status register that never sets that bit, and a full poll would hang the
	 * firmware on the very first character.
	 *
	 * The countdown lives in $a6, not $a3: hexserial/hexserial64 hold their
	 * shift register in $a3 across this call, and the PMON originals only
	 * promise to clobber $a0-$a2 (see "used: a0~a2" above LEAF(tgt_putchar) in
	 * ls3a5000_7a/loongson/start.S).  Clobbering $a3 turned every hex number
	 * into the first digit followed by zeros.
	 */
	li.d	$a1, COM1_MIRROR0_ADDR
	li.w	$a6, 0x800
2:
	ld.bu	$a2, $a1, 0x5
	andi	$a2, $a2, 0x20
	bnez	$a2, 3f
	addi.w	$a6, $a6, -1
	bnez	$a6, 2b
3:
	st.b	$a0, $a1, 0

	jirl	$zero, $ra, 0

#------------------------------------------------------------------------------
# stringserial - print NUL terminated string at a0
#
# The callers reach these helpers with `bl`, and every one of them calls
# tgt_putchar - which is itself reached with `bl` and therefore overwrites
# $ra.  PMON keeps the return address in $a4 across the loop (see LEAF
# (hexserial) in ls3a5000_7a/loongson/start.S); without that the final
# `jirl $zero, $ra, 0` jumps back to the instruction after the last `bl`
# inside the helper instead of returning, and the helper spins forever.
#------------------------------------------------------------------------------
ASM_GLOBAL ASM_PFX(stringserial)
ASM_PFX(stringserial):
	ori	$a4, $ra, 0
1:
	ld.bu	$a2, $a0, 0
	beqz	$a2, 2f
	bl	tgt_putchar
	addi.d	$a0, $a0, 1
	b	1b
2:
	ori	$ra, $a4, 0
	jirl	$zero, $ra, 0

#------------------------------------------------------------------------------
# hexserial / hexserial64 - hex dump helpers used by the DDR assembly
#------------------------------------------------------------------------------
ASM_GLOBAL ASM_PFX(hexserial)
ASM_PFX(hexserial):
	ori	$a4, $ra, 0
	ori	$a3, $a0, 0
	li.d	$a5, 8
1:
	rotri.w	$a0, $a3, 28
	or	$a3, $a0, $zero
	andi	$a0, $a0, 0xf
	la	$a1, .Lhexchar
	add.d	$a1, $a1, $a0
	ld.bu	$a0, $a1, 0
	bl	tgt_putchar
	addi.d	$a5, $a5, -1
	bnez	$a5, 1b
	ori	$ra, $a4, 0
	jirl	$zero, $ra, 0

ASM_GLOBAL ASM_PFX(hexserial64)
ASM_PFX(hexserial64):
	ori	$a4, $ra, 0
	ori	$a3, $a0, 0
	li.d	$a5, 16
1:
	rotri.d	$a0, $a3, 60
	or	$a3, $a0, $zero
	andi	$a0, $a0, 0xf
	la	$a1, .Lhexchar
	add.d	$a1, $a1, $a0
	ld.bu	$a0, $a1, 0
	bl	tgt_putchar
	addi.d	$a5, $a5, -1
	bnez	$a5, 1b
	ori	$ra, $a4, 0
	jirl	$zero, $ra, 0

	.section .rodata
	.align 3
.Lhexchar:
	.ascii	"0123456789abcdef"
	.text
