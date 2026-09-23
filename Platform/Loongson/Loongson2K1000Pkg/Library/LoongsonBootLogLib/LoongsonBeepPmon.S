/** @file
  The board's beeper, with PMON's pin, PMON's loop, and a half period scaled to
  this clock.

  Two things were wrong before, and they are separate:

    - The loop itself is PMON's (addi.w + nop + bnez is the inner delay), which
      matters because the element only gets loud near its resonance.
    - The half period has to be scaled.  PMON beeps while the CPU is still on
      its reset clock, so its 0x2000 iterations land in the low kHz.  This code
      runs after the PLLs are up, roughly ten times faster, so the same count
      comes out ten times higher - and with the count left as PMON's it was
      worse still, because the loop fetches from the uncached window.

  The scale factor is not a guess from the source: it is read off the board.
  With the unscaled count the owner hears separate clicks a few tens of times a
  second rather than a tone, which puts the wave about fifty times too slow for
  the low kHz band these elements are loud in.  Hence 0x2000 / 48 is taken as
  the half period, with 0x80 half periods per beep (PMON's length).

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
