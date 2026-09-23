/* Beep sweep stub: proves the image is executed and measures the effective
   instruction-fetch speed of the window the boot ROM hands over in.
   Runs standalone -- touches only the APB BAR and GPIO39, then loops. */
        .text
        .globl  _start
_start:
        /* APB window: GPIO sits behind it */
        li.d    $t0, 0x800000FE00001000
        li.d    $t1, 0x800000001FE20000
        st.w    $t1, $t0, 0x10
        ld.w    $t2, $t0, 0x04
        ori     $t2, $t2, 2
        st.w    $t2, $t0, 0x04

        /* GPIO39 as output */
        li.d    $t3, 0x800000001FE00504
        ld.w    $t4, $t3, 0
        li.d    $t5, ~0x80
        and     $t4, $t4, $t5
        st.w    $t4, $t3, 0

        /* GPIO39 data register and the buzzer bit */
        li.d    $t3, 0x800000001FE00514
        ori     $t2, $zero, 0x80
        li.d    $t6, 0x40                  /* half-period delay, swept below */

burst:
        ori     $t7, $zero, 0x80           /* half periods per burst */
tone:
        ld.w    $t4, $t3, 0
        or      $t5, $t4, $t2
        xor     $t5, $t5, $t2              /* force the bit low */
        st.w    $t5, $t3, 0
        move    $t8, $t6
d1:     addi.w  $t8, $t8, -1
        bnez    $t8, d1
        ld.w    $t4, $t3, 0
        or      $t4, $t4, $t2              /* force it high */
        st.w    $t4, $t3, 0
        move    $t8, $t6
d2:     addi.w  $t8, $t8, -1
        bnez    $t8, d2
        addi.w  $t7, $t7, -1
        bnez    $t7, tone

        li.d    $t8, 0x8000                /* gap */
g1:     addi.w  $t8, $t8, -1
        bnez    $t8, g1

        slli.d  $t6, $t6, 2                /* 0x40 -> 0x100 -> 0x400 -> 0x1000 */
        li.d    $t5, 0x1000
        beq     $t6, $t5, restart
        b       burst
restart:
        li.d    $t6, 0x40
        b       burst
