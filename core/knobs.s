| SPDX-License-Identifier: GPL-2.0-or-later
| core-dt2 2.0: knob drawers. The SRC page draws each parameter's knob through SourcePageView's vtable slot 45
| (0x401edd4c, stock 0x40069b8e: the widget). Core takes the slot once; a mod that draws the knobs of its own
| parameter codes adds to the table `core_knobs` an entry of three longs {first code, last code, fn}. For a code
| in an entry's range core jumps to fn with the stock call's stack and registers (fn is then the widget: it may
| call the stock one, KNOB_STOCK, itself); every other code draws as stock. Stack at the slot: 0 return,
| 4 view, 8 bitmap, 12 x, 16 y, 20 code, 24 value, then five more arguments.

        .section .run, "ax"
        .balign 4                       | (a .run section is byte-aligned by default: keep code even)
        .globl  core_knob_widget
core_knob_widget:
        lea     -16(%sp), %sp           | 12(sp): where to go; 0-8(sp): d0, d1, a0
        movem.l %d0-%d1/%a0, (%sp)
        move.l  36(%sp), %d0            | code
        lea     core_knobs, %a0
1:      move.l  (%a0)+, %d1             | first code; 0 ends the table
        beq.s   8f
        cmp.l   %d1, %d0
        blt.s   2f
        cmp.l   (%a0), %d0
        bgt.s   2f
        move.l  4(%a0), %d1             | this entry's drawer
        bra.s   9f
2:      addq.l  #8, %a0
        bra.s   1b
8:      move.l  #KNOB_STOCK, %d1
9:      move.l  %d1, 12(%sp)
        movem.l (%sp), %d0-%d1/%a0
        lea     12(%sp), %sp
        rts                             | a jump that keeps every register and the stack
