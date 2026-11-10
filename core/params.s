| SPDX-License-Identifier: AGPL-3.0-or-later
| core-dt2 2.0: added parameters (DigiKit's core/params 0.3.0 for the Digitakt II 1.17, as a core service).
|
| The firmware's parameter table (60-byte rows, one per parameter code; 275 stock codes) is copied at boot
| to pf_table with 64 more rows, codes 275 (PF_FIRST) to 338; every reference to the stock table points into
| the copy and every clamp bound is 64 higher (mod.json's sites, DigiKit's anchors). A mod adds a parameter
| through the table `core_params`, a pointer per parameter to a `struct core_param_dt2`:
|
|   +0   code        275-338, fixed (projects and the machine descriptors name it): claim it as param:<code>
|   +4   name        C string, the page header when the knob is touched
|   +8   short       C string, the label under the knob
|   +12  template    the stock code whose row it copies (owner, flag, kind, mask, formatter, value class)
|   +16  slot        0-7: the descriptor field (value index 25, 26, 27, 28, 31, 32, 33, 34); 8-11: SRC page 2
|                    (value index 29, 30, 69, 70; core 2.1)
|   +20  min, +24 max, +28 default (8.8)
|   +32  formatter   0, or fmt(int raw, char *buf): the value text
|   +36  randomize   0 the template's, 1 uniform over min..max in steps of 0x100, or fn(rnd, min, max)
|
| A code no mod adds is a copy of the LEV row (0xfe) that nothing names. +4..+40 is DigiKit's registry row,
| so its three routines below read the descriptors as they read the registry.

        .equ    PF_FIRST, 275           | the stock row count (`cmpi.l #0x113,D0` of the accessor)
        .equ    PF_N, 64
        .equ    PF_ROW, 60
        .equ    PF_GAP, 0xfe            | the row a code nobody adds copies
        .equ    P_TEMPLATE, 8           | the registry row (the descriptor + 4)
        .equ    P_SLOT, 12
        .equ    P_MIN, 16
        .equ    P_MAX, 20
        .equ    P_DEFAULT, 24
        .equ    P_FORMATTER, 28
        .equ    P_RANDOMIZE, 32
        .equ    P_ROWSIZE, 36

        .section .run, "ax"
        .balign 4                       | (a .run section is byte-aligned by default: keep code even)

| ---- core_params_boot: pf_table and the registry rows, at boot (from core_boot_init). Clobbers d0-d4, a0-a3.
        .globl  core_params_boot
core_params_boot:
        lea     PF_T1, %a1              | the stock rows, as the build left them
        lea     pf_table, %a0
        move.l  #PF_FIRST * PF_ROW / 4, %d0
1:      move.l  (%a1)+, (%a0)+
        subq.l  #1, %d0
        bne.s   1b
        moveq   #PF_N, %d1              | every added code a gap: the LEV row, and a registry row for it
        lea     pf_rows, %a2
2:      lea     PF_T1 + PF_GAP * PF_ROW, %a1
        moveq   #PF_ROW / 4, %d0
3:      move.l  (%a1)+, (%a0)+
        subq.l  #1, %d0
        bne.s   3b
        move.l  PF_T1 + PF_GAP * PF_ROW + 0x28, (%a2)+      | name
        move.l  PF_T1 + PF_GAP * PF_ROW + 0x30, (%a2)+      | short
        move.l  #PF_GAP, (%a2)+         | template
        clr.l   (%a2)+                  | slot
        clr.l   (%a2)+                  | min
        move.l  #0x7f00, (%a2)+         | max
        clr.l   (%a2)+                  | default
        clr.l   (%a2)+                  | formatter
        clr.l   (%a2)+                  | randomize
        subq.l  #1, %d1
        bne.s   2b
        moveq   #0, %d3                 | 0: core_params, 1: core_sdk_params (core 2.7: the SDK machines' shared codes)
        lea     core_params, %a3        | the parameters the mods add (a3: the list, never clobbered below)
4:      move.l  (%a3)+, %d0
        bne.s   41f
        tst.l   %d3
        bne.w   9f
        moveq   #1, %d3
        lea     core_sdk_params, %a3
        bra.s   4b
41:     movea.l %d0, %a1
        move.l  (%a1)+, %d4             | code
        subi.l  #PF_FIRST, %d4
        cmpi.l  #PF_N, %d4
        bcc.s   4b
        move.l  %d4, %d0                | the registry row: the descriptor's +4..+40
        moveq   #P_ROWSIZE, %d1
        mulu.l  %d1, %d0
        lea     pf_rows, %a2
        adda.l  %d0, %a2
        moveq   #P_ROWSIZE / 4, %d0
        movea.l %a2, %a0
5:      move.l  (%a1)+, (%a0)+
        subq.l  #1, %d0
        bne.s   5b
        | the table row (DigiKit's [[section]] pf_table "append"): the template's row with the entry's fields
        move.l  %d4, %d0
        addi.l  #PF_FIRST, %d0
        moveq   #PF_ROW, %d1
        mulu.l  %d1, %d0
        lea     pf_table, %a0
        adda.l  %d0, %a0                | a0 = the row
        move.l  P_TEMPLATE(%a2), %d0
        moveq   #PF_ROW, %d1
        mulu.l  %d1, %d0
        lea     PF_T1, %a1
        adda.l  %d0, %a1                | a1 = the template's stock row
        moveq   #PF_ROW / 4, %d0
6:      move.l  (%a1)+, (%a0)+
        subq.l  #1, %d0
        bne.s   6b
        lea     -PF_ROW(%a1), %a1
        lea     -PF_ROW(%a0), %a0
        move.l  P_SLOT(%a2), %d1        | +0x04, +0x18, +0x1c from the slot's row of pf_slots
        cmpi.l  #PF_SLOTS, %d1
        bcs.s   7f
        moveq   #0, %d1
7:      move.l  %d1, %d0
        add.l   %d0, %d0
        add.l   %d1, %d0
        lsl.l   #2, %d0                 | 12 * slot
        lea     pf_slots, %a1
        adda.l  %d0, %a1                | a1 = &pf_slots[slot] (12 bytes: value index, cc word, key)
        move.l  (%a1)+, 0x04(%a0)
        move.l  0x18(%a0), %d2
        andi.l  #0xffff, %d2            | the template's kind
        or.l    (%a1)+, %d2             | (cc << 16)
        move.l  %d2, 0x18(%a0)
        move.l  (%a1), 0x1c(%a0)
        move.l  P_MIN(%a2), 0x08(%a0)
        move.l  P_MAX(%a2), 0x0c(%a0)
        move.l  P_DEFAULT(%a2), 0x10(%a0)
        move.l  0(%a2), 0x28(%a0)       | +0x28 name
        move.l  4(%a2), 0x30(%a0)       | +0x30 short
        move.l  P_FORMATTER(%a2), %d0   | +0x34 the entry's formatter, or the template's
        beq.w   4b
        move.l  %d0, 0x34(%a0)
        bra.w   4b
9:      rts

| ---- the second per-code table's accessor (DigiKit's pf_t2): an added code becomes its template's code, then the
| stock clamp runs. Site: `cmpi.l #stock count,D0` after `move.l 4(sp),D0`. Every other register is preserved.
        .globl  pf_t2
pf_t2:
        lea     -8(%sp), %sp
        movem.l %d1/%a0, (%sp)
        move.l  %d0, %d1
        subi.l  #PF_FIRST, %d1
        cmpi.l  #PF_N, %d1
        bcc.s   1f
        move.l  #P_ROWSIZE, %d0
        muls.l  %d1, %d0
        addi.l  #pf_rows, %d0
        movea.l %d0, %a0
        move.l  P_TEMPLATE(%a0), %d0
        bra.s   2f
1:      move.l  %d1, %d0
        addi.l  #PF_FIRST, %d0
2:      movem.l (%sp), %d1/%a0
        lea     8(%sp), %sp
        cmpi.l  #PF_FIRST, %d0          | the displaced instruction
        jmp     PF_T2 + 6

| ---- the knob drawer (DigiKit's pf_drawone): the value of an added code is mapped from its range onto
| 0 .. 0x7f00 before the drawer sees it. Stack: 0 return address, 4 this, 8 code, 12 value. d0/d1/a0/a1 free.
        .globl  pf_drawone
pf_drawone:
        move.l  8(%sp), %d0
        subi.l  #PF_FIRST, %d0
        cmpi.l  #PF_N, %d0
        bcc.s   9f                      | a stock code
        move.l  #P_ROWSIZE, %d1
        muls.l  %d1, %d0
        addi.l  #pf_rows, %d0
        movea.l %d0, %a0
        move.l  P_MAX(%a0), %d1
        sub.l   P_MIN(%a0), %d1         | the range
        ble.s   9f                      | an empty range: leave it
        cmpi.l  #0x7f00, %d1
        beq.s   9f                      | already the level's range
        move.l  12(%sp), %d0
        sub.l   P_MIN(%a0), %d0
        bge.s   1f
        moveq   #0, %d0
1:      cmp.l   %d1, %d0
        ble.s   2f
        move.l  %d1, %d0
2:      lsl.l   #8, %d0
        movea.l %d0, %a1                | value << 8
        lsl.l   #7, %d0                 | value << 15
        sub.l   %a1, %d0                | value * 0x7f00
        divu.l  %d1, %d0
        move.l  %d0, 12(%sp)
9:      lea     -0x14(%sp), %sp         | the displaced instructions
        movem.l %d2-%d6, (%sp)
        jmp     PF_DRAWONE + 8

| ---- the per-code randomizer (DigiKit's pf_randone): an added code with a `randomize` value picks and writes its
| own value through the stock call. Stack: 0 return address, 4 this, 8 code. d0/d1/a0/a1 free.
        .globl  pf_randone
pf_randone:
        move.l  8(%sp), %d0
        subi.l  #PF_FIRST, %d0
        cmpi.l  #PF_N, %d0
        bcc.w   9f                      | a stock code
        move.l  #P_ROWSIZE, %d1
        muls.l  %d1, %d0
        addi.l  #pf_rows, %d0
        movea.l %d0, %a0
        tst.l   P_RANDOMIZE(%a0)
        beq.w   9f                      | none: the template's randomizer
        lea     -12(%sp), %sp
        movem.l %d2-%d3/%a2, (%sp)
        movea.l %a0, %a2
        jsr     PF_RAND                 | d0 = 0 .. 0x7fff
        move.l  P_MIN(%a2), %d1
        move.l  P_MAX(%a2), %d2
        move.l  P_RANDOMIZE(%a2), %d3
        cmpi.l  #1, %d3
        bne.s   2f
        sub.l   %d1, %d2
        lsr.l   #8, %d2
        addq.l  #1, %d2                 | n = the number of steps
        mulu.l  %d2, %d0
        lsr.l   #8, %d0
        lsr.l   #7, %d0                 | (rnd * n) >> 15 = 0 .. n - 1
        lsl.l   #8, %d0
        add.l   %d1, %d0                | the value
        bra.s   3f
2:      move.l  %d2, -(%sp)             | custom: fn(rnd, min, max)
        move.l  %d1, -(%sp)
        move.l  %d0, -(%sp)
        movea.l %d3, %a0
        jsr     (%a0)
        lea     12(%sp), %sp
3:      pea     1.w                     | the stock call's arguments, last first; this and code were at 16(sp) and 20(sp)
        pea     1.w
        clr.l   -(%sp)
        pea     -1.w
        move.l  %d0, -(%sp)             | value
        move.l  40(%sp), -(%sp)         | code
        move.l  40(%sp), -(%sp)         | this
        jsr     PF_WRITE
        lea     28(%sp), %sp
        movem.l (%sp), %d2-%d3/%a2
        lea     12(%sp), %sp
        moveq   #1, %d0
        rts
9:      link.w  %fp, #-0x34             | the displaced instructions
        movem.l %d2-%d5, (%sp)
        jmp     PF_RANDONE + 8

| slot -> {value index, MIDI CC << 16 | 0xffff (no LSB CC, as the stock's 7-bit rows; core 2.7), per-machine key}: the eight SRC fields (DigiKit's), then the four
| page-2 slots of core 2.1: 8 = index 29 and 9 = index 30 (the stock BANK and SLOT places: CC 24 and 19, keys
| 0x89 and 0x88), 10 = index 69 and 11 = index 70 (free on audio tracks: no CC, no key)
        .balign 4
        .equ    PF_SLOTS, 12
pf_slots:
        .long   25, 0x10ffff, 0x80
        .long   26, 0x11ffff, 0x81
        .long   27, 0x12ffff, 0x82
        .long   28, 0xffffffff, 0x83
        .long   31, 0x14ffff, 0x84
        .long   32, 0x15ffff, 0x85
        .long   33, 0x16ffff, 0x86
        .long   34, 0x17ffff, 0x87
        .long   29, 0x18ffff, 0x89
        .long   30, 0x13ffff, 0x88
        .long   69, 0xffffffff, -1
        .long   70, 0xffffffff, -1

        .section .bss
        .balign 4
        .globl  pf_table, pf_rows
pf_rows:  .space P_ROWSIZE * PF_N
pf_table: .space PF_ROW * (PF_FIRST + PF_N)
