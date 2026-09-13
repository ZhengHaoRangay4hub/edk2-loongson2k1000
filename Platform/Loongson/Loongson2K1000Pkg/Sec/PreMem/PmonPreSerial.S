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
1:
	ld.bu	$a2, $a0, 5
	andi	$a2, $a2, 0x20
	beqz	$a2, 1b
	li.w	$a1, 3
	st.b	$a1, $a0, 3
	li.w	$a1, 71
	st.b	$a1, $a0, 2
	jirl	$zero, $ra, 0

#------------------------------------------------------------------------------
# tgt_putchar - blocking char output (a0 = char)
#------------------------------------------------------------------------------
ASM_GLOBAL ASM_PFX(tgt_putchar)
ASM_PFX(tgt_putchar):
	li.d	$a1, COM1_BASE_ADDR
1:
	ld.bu	$a2, $a1, 0x5
	andi	$a2, $a2, 0x20
	beqz	$a2, 1b
	st.b	$a0, $a1, 0
	jirl	$zero, $ra, 0

#------------------------------------------------------------------------------
# stringserial - print NUL terminated string at a0
#------------------------------------------------------------------------------
ASM_GLOBAL ASM_PFX(stringserial)
ASM_PFX(stringserial):
1:
	ld.bu	$a2, $a0, 0
	beqz	$a2, 2f
	bl	tgt_putchar
	addi.d	$a0, $a0, 1
	b	1b
2:
	jirl	$zero, $ra, 0

#------------------------------------------------------------------------------
# hexserial / hexserial64 - hex dump helpers used by the DDR assembly
#------------------------------------------------------------------------------
ASM_GLOBAL ASM_PFX(hexserial)
ASM_PFX(hexserial):
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
	jirl	$zero, $ra, 0

ASM_GLOBAL ASM_PFX(hexserial64)
ASM_PFX(hexserial64):
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
	jirl	$zero, $ra, 0

	.section .rodata
	.align 3
.Lhexchar:
	.ascii	"0123456789abcdef"
	.text
