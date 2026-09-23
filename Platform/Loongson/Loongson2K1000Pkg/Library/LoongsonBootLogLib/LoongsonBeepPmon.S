/** @file
  The board's beeper, with PMON's pin, PMON's loop, and a half period scaled to
  this clock.

  The half period is PMON's own count, 0x2000 iterations of the addi.w + nop +
  bnez inner delay.  That count was tuned on this board at the reset (pre-PLL)
  clock, and every current call site runs there: all SEC progress beeps fire
  before the clock stage.  DXE users of this library run after the PLLs, with
  the loop fetching from the uncached window, so the same count lands far
  above the buzzer's low-kHz resonance there - audible only as clicks.  That
  is a known limitation of the DXE call sites, not of the count itself.

  A previous attempt copied the loop into the locked scache and ran it from
  there.  That is reverted: the lock is set up in Start.S, which only the SEC
  module runs, while this library is linked into DXE modules that never lock
  anything - and on the board itself it produced no sound at all.

  Pin and registers are PMON's unchanged: GPIO39 as bit 7 of the high word,
  direction in 0x1fe00504 (clear = output), data in 0x1fe00514.  No stack, no
  calls, so it beeps even where the C environment cannot run.

  SPDX-License-Identifier: BSD-2-Clause-Patent
**/

.globl LoongsonBeepRaw

#   $a0 = number of beeps
LoongsonBeepRaw:
	li.d	$t1, 0x800000001fe00500
	li.w	$t2, 0x80
	ld.w	$t0, $t1, 4
	or	$t0, $t0, $t2
	xor	$t0, $t0, $t2
	st.w	$t0, $t1, 4		# direction: clear bit 7 = output
	move	$t8, $a0
2:
	li.d	$t1, 0x800000001fe00510
	li.w	$t3, 0x80		# 0x80 half periods per beep (PMON's length)
3:
	li.w	$t2, 0x80
	ld.w	$t0, $t1, 4
	or	$t0, $t0, $t2
	xor	$t0, $t0, $t2
	st.w	$t0, $t1, 4		# low
	li.w	$t4, 0x2000
4:
	addi.w	$t4, $t4, -1
	nop
	bnez	$t4, 4b
	li.w	$t2, 0x80
	ld.w	$t0, $t1, 4
	or	$t0, $t0, $t2
	st.w	$t0, $t1, 4		# high
	li.w	$t4, 0x2000
5:
	addi.w	$t4, $t4, -1
	nop
	bnez	$t4, 5b
	addi.w	$t3, $t3, -1
	bnez	$t3, 3b
	li.w	$t4, 0x20000		# gap between beeps
6:
	addi.w	$t4, $t4, -1
	bnez	$t4, 6b
	addi.w	$t8, $t8, -1
	bnez	$t8, 2b
	li.d	$t1, 0x800000001fe00510
	li.w	$t2, 0x80
	ld.w	$t0, $t1, 4
	or	$t0, $t0, $t2
	xor	$t0, $t0, $t2
	st.w	$t0, $t1, 4		# off
	jirl	$zero, $ra, 0
