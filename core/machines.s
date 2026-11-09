| SPDX-License-Identifier: AGPL-3.0-or-later
| core-dt2 2.0: added machine types (DigiKit's core/machines 0.2.0 for the Digitakt II 1.17, as a core service).
|
| DigiKit's framework, ported: patchkit sized its tables to the machines selected when it patched; here the
| core does not know the mods, so every table covers the whole range of added types, 7 (MF_FIRST) to 23
| (MF_LAST, the highest type the DSP's selector table was read to: DigiKit's types.toml), and the core fills
| it at boot from the table `core_machines` (a pointer per machine, to a `struct core_machine_dt2`):
|
|   +0   type       7-23, permanent (a project stores it): claim it as the resource machine:<type>
|   +4   clone_of   the stock type (0-6) whose permission mask, per-type byte, name hint and DSP selector it takes,
|                   and whose `type == SLICE` tests it passes when that is 6
|   +8   position   its index in the machine list (0xffffffff: not listed)
|   +12  flags      bit 0 one SRC page (onepage.s); bit 1 POLY may lend and borrow its voices; bit 2 a second
|                   SRC page of its own (+60); bit 3 knob H (value 34) is its own parameter, not LEV: the DSP gets it
|                   in frame halfword 12 and the level halfword 9 stays at 100 (core 2.2)
|   +16  f[9]       the descriptor's nine parameter codes (A-H, then the level, 10)
|   +52  name       C string: the machine list (upper-cased), +56 short: the SRC page header
|   +60  f2[8]      with flag bit 2: the codes of SRC page 2, knobs A-H (0: no knob). Page 2 takes a code of a
|                   parameter on value index 29, 30, 69 or 70 (core_params slots 8-11); SRC toggles the pages
|
| A type no installed mod adds is a gap row, as DigiKit's: a clone of type 0 that is not listed, so a
| project that names it plays as type 0. What each routine does at its site is DigiKit's (comments kept);
| the hook tails (the displaced instructions, then a jump back) are written out below.

        .equ    MF_FIRST, 7
        .equ    MF_LAST, 23
        .equ    MF_N, MF_LAST - MF_FIRST + 1    | rows: types 7-23
        .equ    O_LONG,   0             | descriptor: chars of the std::string long name (built by mf_ensure)
        .equ    O_SHORT,  4             | descriptor: chars of the std::string short name (built by mf_ensure)
        .equ    O_F0,     8             | descriptor: the nine parameter descriptor IDs, O_F0 .. O_F0 + 32
        .equ    O_CLONE,  44
        .equ    O_POS,    48
        .equ    O_FLAGS,  52
        .equ    O_NAME,   56            | pointer to the display name (C string)
        .equ    O_SNAME,  60            | pointer to the short label (C string)
        .equ    O_ONEPAGE, 64
        .equ    O_F2,     68            | page 2: eight codes (zero without flag bit 2)
        .equ    ROWSIZE,  100
        .equ    SLICE,    6
        .equ    REPSIZE,  48            | bytes per std::string representation in mf_strbuf
        | struct core_machine_dt2
        .equ    D_TYPE, 0
        .equ    D_CLONE, 4
        .equ    D_POS, 8
        .equ    D_FLAGS, 12
        .equ    D_F0, 16
        .equ    D_NAME, 52
        .equ    D_SNAME, 56
        .equ    D_F2, 60

        .section .run, "ax"
        .balign 4                       | (a .run section is byte-aligned by default: keep code even)

| ---- core_machines_boot: the rows and the copies of the stock tables, at boot (from core_boot_init). The
| image is in RAM at its addresses; the tables are read from it as the build left it. Clobbers d0-d2, a0-a2.
        .globl  core_machines_boot
core_machines_boot:
        lea     mf_rows, %a0            | every row a gap row
        moveq   #MF_N, %d1
1:      moveq   #ROWSIZE / 4, %d0
        movea.l %a0, %a1
2:      clr.l   (%a1)+
        subq.l  #1, %d0
        bne.s   2b
        moveq   #10, %d0
        move.l  %d0, O_F0 + 32(%a0)
        moveq   #-1, %d0
        move.l  %d0, O_POS(%a0)
        lea     mf_empty, %a1
        move.l  %a1, O_NAME(%a0)
        move.l  %a1, O_SNAME(%a0)
        lea     ROWSIZE(%a0), %a0
        subq.l  #1, %d1
        bne.s   1b
        lea     core_machines, %a2      | the machines the mods add
3:      move.l  (%a2)+, %d0
        beq.w   6f
        movea.l %d0, %a1
        move.l  D_TYPE(%a1), %d0
        subi.l  #MF_FIRST, %d0
        cmpi.l  #MF_N, %d0
        bcc.s   3b                      | not a type the core takes
        move.l  #ROWSIZE, %d1
        muls.l  %d1, %d0
        lea     mf_rows, %a0
        adda.l  %d0, %a0
        moveq   #8, %d1                 | f0-f8
        lea     D_F0(%a1), %a1
        lea     O_F0(%a0), %a0
4:      move.l  (%a1)+, (%a0)+
        subq.l  #1, %d1
        bpl.s   4b
        lea     -O_F0 - 36(%a0), %a0
        movea.l -4(%a2), %a1
        move.l  D_CLONE(%a1), O_CLONE(%a0)
        move.l  D_POS(%a1), O_POS(%a0)
        move.l  D_FLAGS(%a1), %d0
        move.l  %d0, O_FLAGS(%a0)
        andi.l  #1, %d0
        move.l  %d0, O_ONEPAGE(%a0)
        move.l  D_NAME(%a1), O_NAME(%a0)
        move.l  D_SNAME(%a1), O_SNAME(%a0)
        btst    #2, O_FLAGS + 3(%a0)
        beq.w   3b
        moveq   #7, %d1                 | page 2: f2[0..7]
        lea     D_F2(%a1), %a1
        lea     O_F2(%a0), %a0
5:      move.l  (%a1)+, (%a0)+
        subq.l  #1, %d1
        bpl.s   5b
        bra.w   3b
6:      | the listed machines
        moveq   #0, %d2
        lea     mf_rows, %a0
        moveq   #MF_N, %d1
7:      moveq   #-1, %d0
        cmp.l   O_POS(%a0), %d0
        beq.s   8f
        addq.l  #1, %d2
8:      lea     ROWSIZE(%a0), %a0
        subq.l  #1, %d1
        bne.s   7b
        move.l  %d2, mf_entries
        | names: {long, short, header hint} per type; the stock rows, then each added type's
        lea     MF_TAB_NAMES, %a1
        lea     mf_names, %a0
        move.l  #MF_FIRST * 12, %d0
        bsr.w   mf_bytes
        lea     mf_rows, %a2
        moveq   #MF_N, %d2
9:      move.l  O_NAME(%a2), (%a0)+
        move.l  O_SNAME(%a2), (%a0)+
        move.l  O_CLONE(%a2), %d0
        move.l  %d0, %d1
        add.l   %d0, %d0
        add.l   %d1, %d0
        lsl.l   #2, %d0                 | 12 * clone
        lea     MF_TAB_NAMES + 8, %a1
        adda.l  %d0, %a1
        moveq   #4, %d0
        bsr.w   mf_bytes
        lea     ROWSIZE(%a2), %a2
        subq.l  #1, %d2
        bne.s   9b
        | permission masks
        lea     MF_TAB_PERMIT, %a1
        lea     mf_permit, %a0
        move.l  #MF_FIRST * 4, %d0
        bsr.w   mf_bytes
        lea     mf_rows, %a2
        moveq   #MF_N, %d2
10:     move.l  O_CLONE(%a2), %d0
        lsl.l   #2, %d0
        lea     MF_TAB_PERMIT, %a1
        adda.l  %d0, %a1
        moveq   #4, %d0
        bsr.w   mf_bytes
        lea     ROWSIZE(%a2), %a2
        subq.l  #1, %d2
        bne.s   10b
        | per-type bytes
        lea     MF_TAB_PERTYPE, %a1
        lea     mf_pertype, %a0
        moveq   #MF_FIRST, %d0
        bsr.w   mf_bytes
        lea     mf_rows, %a2
        moveq   #MF_N, %d2
11:     move.l  O_CLONE(%a2), %d0
        lea     MF_TAB_PERTYPE, %a1
        move.b  (%a1, %d0.l), (%a0)+
        lea     ROWSIZE(%a2), %a2
        subq.l  #1, %d2
        bne.s   11b
        rts

| copy d0 bytes from a1 to a0 (a0, a1 advance; the stock tables are not all longword-aligned)
mf_bytes:
        tst.l   %d0
        beq.s   2f
1:      move.b  (%a1)+, (%a0)+
        subq.l  #1, %d0
        bne.s   1b
2:      rts

| ---- core_machine_row(type) -> d0: the row of an added type 7-23 (DigiKit's layout), or 0. For mods that
| ask what a track's machine is (POLY: bit 1 of +52, the flags).
        .globl  core_machine_row
core_machine_row:
        move.l  4(%sp), %d0
        subi.l  #MF_FIRST, %d0
        cmpi.l  #MF_N, %d0
        bcc.s   1f
        move.l  %d1, -(%sp)
        move.l  #ROWSIZE, %d1
        muls.l  %d1, %d0
        addi.l  #mf_rows, %d0
        move.l  (%sp)+, %d1
        rts
1:      moveq   #0, %d0
        rts

| ---- mf_ensure: build the run-time tables once. Preserves every register (not the flags).
mf_ensure:
        tst.b   mf_ready
        bne.w   9f
        lea     -60(%sp), %sp
        movem.l %d0-%d7/%a0-%a6, (%sp)
        | list: the stock order, then each entry inserted at min(position, length)
        lea     mf_list_buf, %a0
        lea     MF_TAB_LIST, %a1
        move.l  #MF_FIRST, %d2
        move.l  %d2, %d3                | d3 = length
1:      move.l  (%a1)+, (%a0)+
        subq.l  #1, %d2
        bne.s   1b
        lea     mf_rows, %a2
        move.l  #MF_N, %d4
        move.l  #MF_FIRST, %d5          | d5 = the type of entry k
2:      move.l  O_POS(%a2), %d0
        addq.l  #1, %d0
        beq.s   20f                     | position -1: a gap row (a number nobody selected): not listed
        subq.l  #1, %d0
        cmp.l   %d3, %d0
        bls.s   3f
        move.l  %d3, %d0
3:      lea     mf_list_buf, %a0
        move.l  %d3, %d1
4:      cmp.l   %d0, %d1                | shift the entries from position up by one
        bls.s   6f
        move.l  -4(%a0, %d1.l*4), %d6
        move.l  %d6, (%a0, %d1.l*4)
        subq.l  #1, %d1
        bra.s   4b
6:      move.l  %d5, (%a0, %d0.l*4)
        addq.l  #1, %d3
20:     addq.l  #1, %d5
        lea     ROWSIZE(%a2), %a2
        subq.l  #1, %d4
        bne.s   2b
        lea     mf_list_buf, %a0        | where the list builder's copy ends (its literal reads this)
        lea     (%a0, %d3.l*4), %a0
        move.l  %a0, mf_list_end
        | rank pairs {type, display position}
        lea     mf_list_buf, %a0
        lea     mf_rank_buf, %a1
        moveq   #0, %d0
7:      move.l  (%a0)+, (%a1)+
        move.l  %d0, (%a1)+
        addq.l  #1, %d0
        cmp.l   %d3, %d0
        bcs.s   7b
        | descriptors: std::string representations of the upper-cased names
        lea     mf_rows, %a2
        lea     mf_strbuf, %a3
        move.l  #MF_N, %d4
10:     movea.l O_NAME(%a2), %a0
        bsr.s   mf_rep
        move.l  %d0, O_LONG(%a2)
        movea.l O_SNAME(%a2), %a0
        bsr.s   mf_rep
        move.l  %d0, O_SHORT(%a2)
        lea     ROWSIZE(%a2), %a2
        subq.l  #1, %d4
        bne.s   10b
        moveq   #-1, %d0
        move.b  %d0, mf_ready
        movem.l (%sp), %d0-%d7/%a0-%a6
        lea     60(%sp), %sp
9:      rts

| a0 = C string, a3 = destination; builds {length, capacity, refcount -1, upper-cased chars, 0} at a3, returns the
| address of the chars in d0 and advances a3 to the next 4-byte boundary. Clobbers d1, d2, a0, a1.
mf_rep:
        moveq   #0, %d1
        lea     12(%a3), %a1
1:      move.b  (%a0)+, %d2
        beq.s   2f
        cmpi.b  #'a', %d2
        blo.s   3f
        cmpi.b  #'z', %d2
        bhi.s   3f
        subi.l  #32, %d2
3:      move.b  %d2, (%a1)+
        addq.l  #1, %d1
        cmpi.l  #REPSIZE - 13, %d1      | (a name longer than the slot is cut)
        bcs.s   1b
2:      clr.b   (%a1)
        addq.l  #1, %a1
        move.l  %d1, (%a3)
        move.l  %d1, 4(%a3)
        moveq   #-1, %d2
        move.l  %d2, 8(%a3)
        move.l  %a3, %d0
        addi.l  #12, %d0
        lea     REPSIZE(%a3), %a3
        rts

| ---- dispatch: `FUN_xxxx(type)` returns the descriptor of a machine type. Site: function entry (d0, d1 free).
        .globl  mf_dispatch
mf_dispatch:
        move.l  4(%sp), %d0
        subi.l  #MF_FIRST, %d0
        cmpi.l  #MF_N, %d0
        bcc.s   1f
        bsr.w   mf_ensure
        move.l  #ROWSIZE, %d1
        muls.l  %d1, %d0
        addi.l  #mf_rows, %d0
        rts
1:      moveq   #6, %d1                 | the displaced instructions
        move.l  4(%sp), %d0
        jmp     MF_DISPATCH + 6

| ---- list builder entry: make sure the tables exist before the builder reads mf_list_buf (its literals point
| there: the begin, and the end through mf_list_end). Site: function entry; every register is preserved.
        .globl  mf_list_entry
mf_list_entry:
        bsr.w   mf_ensure
        lea     -0x18(%sp), %sp         | the displaced instructions
        movem.l %d2-%d5/%a2-%a3, (%sp)
        jmp     MF_LIST_ENTRY + 8

| ---- rank: the std::map insert gets the (type, position) pairs of mf_rank_buf instead of the caller's array.
| Site: the `jsr` of the insert; stack: 0 map, 4 begin, 8 end. d0 free.
        .globl  mf_rank
mf_rank:
        bsr.w   mf_ensure
        move.l  #mf_rank_buf, %d0
        move.l  %d0, 4(%sp)
        move.l  mf_entries, %d0         | the listed machines (gap rows are not in mf_rank_buf)
        addq.l  #MF_FIRST, %d0
        lsl.l   #3, %d0
        addi.l  #mf_rank_buf, %d0
        move.l  %d0, 8(%sp)
        jsr     MF_RANK_FN              | the displaced call
        jmp     MF_RANK + 6

| mf_row: d0 = index k (< MF_N) -> a0 = &rows[k]. Preserves every other register (not the flags).
mf_row:
        move.l  %d1, -(%sp)
        move.l  #ROWSIZE, %d1
        muls.l  %d0, %d1
        addi.l  #mf_rows, %d1
        movea.l %d1, %a0
        move.l  (%sp)+, %d1
        rts

| ---- clone tests. `type == SLICE` must also be true for an added type whose clone_of is SLICE. Each site is the
| whole stock test (a prefix, `cmp`, a conditional branch); the hook replaces it: the routine runs the stock
| prefix and compare, and takes the branch itself (DigiKit's, unchanged).
        .macro CLONE_BODY treg, eq, neq
        beq.w   6f
        cmpi.l  #MF_FIRST, %d\treg
        bcc.s   4f
        jmp     \neq                    | a stock type other than SLICE: the stock answer
4:
        lea     -16(%sp), %sp
        movem.l %d0-%d2/%a0, (%sp)
        .if \treg < 3
        move.l  (\treg * 4, %sp), %d0
        .else
        move.l  %d\treg, %d0
        .endif
        subi.l  #MF_FIRST, %d0
        cmpi.l  #MF_N, %d0
        bcc.s   5f
        bsr.w   mf_row
        move.l  O_CLONE(%a0), %d1
        cmpi.l  #SLICE, %d1
        bne.s   5f
        movem.l (%sp), %d0-%d2/%a0
        lea     16(%sp), %sp
6:      jmp     \eq
5:      movem.l (%sp), %d0-%d2/%a0
        lea     16(%sp), %sp
        jmp     \neq
        .endm

        .globl  mf_clone0, mf_clone1, mf_clone2, mf_clone3, mf_clone4, mf_clone5, mf_clone6
| clone.0: moveq #6,D1; cmp.l D0,D1; beq.w T (equal -> T)
mf_clone0:
        moveq   #6, %d1
        cmp.l   %d0, %d1
        CLONE_BODY 0, MF_C0A, MF_C0 + 8
| clone.1: moveq #6,D1; cmp.l D0,D1; bne.b U
mf_clone1:
        moveq   #6, %d1
        cmp.l   %d0, %d1
        CLONE_BODY 0, MF_C1 + 6, MF_C1A
| clone.2: moveq #6,D1; cmp.l D0,D1; bne.w U
mf_clone2:
        moveq   #6, %d1
        cmp.l   %d0, %d1
        CLONE_BODY 0, MF_C2 + 8, MF_C2A
| clone.3: addq.l #4,SP; cmp.l D0,D6; bne.b U (d6 holds SLICE)
mf_clone3:
        addq.l  #4, %sp
        cmp.l   %d0, %d6
        CLONE_BODY 0, MF_C3 + 6, MF_C3A
| clone.4: moveq #6,D0; cmp.l D2,D0; bne.b U (the type is in d2)
mf_clone4:
        moveq   #6, %d0
        cmp.l   %d2, %d0
        CLONE_BODY 2, MF_C4 + 6, MF_C4A
| clone.6: moveq #6,D1; mvs.b (0x990,A0),D0; cmp.l D0,D1; bne.w U. (The frame builder: a SLICE track's slice words
| at frame +0xee..+0xf9. A machine with a page 2 or a knob H of its own is not a SLICE here: those words carry its
| values; core 2.5 adds the knob-H machines, whose H is at +0xf2.)
mf_clone6:
        moveq   #6, %d1
        mvs.b   0x990(%a0), %d0
        bsr.w   mf_own_frame
        beq.s   7f
        jmp     MF_C6A
7:      cmp.l   %d0, %d1
        CLONE_BODY 0, MF_C6 + 12, MF_C6A

| mf_own_frame: d0 = a machine type -> Z clear when it is an added type with flag bit 2 or 3: the frame's halfwords
| 10-15 carry its own values (page 2, knob D, knob H), not a SLICE's slice words (core 2.5). Preserves every register.
mf_own_frame:
        lea     -12(%sp), %sp
        movem.l %d0/%d1/%a0, (%sp)
        subi.l  #MF_FIRST, %d0
        cmpi.l  #MF_N, %d0
        bcc.s   1f
        bsr.w   mf_row
        move.l  O_FLAGS(%a0), %d0
        andi.l  #12, %d0
        bra.s   2f
1:      moveq   #0, %d0
2:      movem.l (%sp), %d0/%d1/%a0      | (movem leaves the flags)
        lea     12(%sp), %sp            | (lea leaves the flags)
        rts

| mf_has_page2: d0 = a machine type -> Z clear when it is an added type with flag bit 2. Preserves every register.
        .globl  mf_has_page2
mf_has_page2:
        lea     -12(%sp), %sp
        movem.l %d0/%d1/%a0, (%sp)
        subi.l  #MF_FIRST, %d0
        cmpi.l  #MF_N, %d0
        bcc.s   1f
        bsr.w   mf_row
        move.l  O_FLAGS(%a0), %d0
        andi.l  #4, %d0
        bra.s   2f
1:      moveq   #0, %d0
2:      movem.l (%sp), %d0/%d1/%a0      | (movem leaves the flags)
        lea     12(%sp), %sp            | (lea leaves the flags)
        rts

| ---- the frame builder, after its fourth per-track copy (stock 0x4002ebdc: lea 12(sp),sp; move.w d7,148(a3)): for a
| track whose machine has a page 2, its smoothed values 69 and 70 (a5 + 0x22 + 2 * index) go to frame +0xee, +0xf0
| (the DSP's per-track halfwords 10 and 11), the place of a SLICE track's slice words, unused by stock otherwise.
        .globl  core_frame_hi
core_frame_hi:
        lea     12(%sp), %sp            | the displaced instructions
        move.w  %d7, 148(%a3)
        lea     (%a2, %d4.l), %a0       | the track's type, as the builder reads it below (a0, d0 are reloaded there)
        mvs.b   0x990(%a0), %d0
        bsr.w   mf_own_frame            | a page 2 or a knob H of its own (core 2.5: knob H alone too)
        beq.s   1f
        move.l  0xac(%a5), 0xee(%a4)    | values 69 and 70
        move.l  0x5a(%a5), 0xf4(%a4)    | values 28 and 29 to halfwords 13 and 14, 30 to 15: the builder zeroes
        move.w  0x5e(%a5), 0xf8(%a4)    | halfwords 3-5 (the sample machines' SAMP, BANK, SLOT) after this point (core 2.3)
        bsr.w   mf_own_h
        beq.s   1f
        move.w  0xec(%a4), 0xf2(%a4)    | knob H (value 34) to halfword 12; the level the DSP applies after the voice
        move.l  #0x6400, %d0            | (halfword 9) stays at the stock default, 100 (d0 is reloaded after)
        move.w  %d0, 0xec(%a4)
1:      jmp     FRAME_HI_RET

| mf_own_h: d0 = a machine type -> Z clear when it is an added type with flag bit 3 (knob H is its own parameter, not
| LEV: core 2.2). Preserves every register.
mf_own_h:
        lea     -12(%sp), %sp
        movem.l %d0/%d1/%a0, (%sp)
        subi.l  #MF_FIRST, %d0
        cmpi.l  #MF_N, %d0
        bcc.s   1f
        bsr.w   mf_row
        move.l  O_FLAGS(%a0), %d0
        andi.l  #8, %d0
        bra.s   2f
1:      moveq   #0, %d0
2:      movem.l (%sp), %d0/%d1/%a0      | (movem leaves the flags)
        lea     12(%sp), %sp            | (lea leaves the flags)
        rts

| clone.5 is the masked test `(type & ~2) == 4` (types 4 and 6): d0 becomes the clone_of of an added type before the
| stock mask. Site: the first three instructions of the test (d1 is set by them).
mf_clone5:
        lea     -8(%sp), %sp
        movem.l %d1/%a0, (%sp)
        move.l  %d0, %d1
        subi.l  #MF_FIRST, %d0
        cmpi.l  #MF_N, %d0
        bcc.s   1f
        bsr.w   mf_row
        move.l  O_CLONE(%a0), %d1
1:      move.l  %d1, %d0
        movem.l (%sp), %d1/%a0
        lea     8(%sp), %sp
        moveq   #-3, %d1                | the displaced instructions
        and.l   %d1, %d0
        moveq   #4, %d1
        jmp     MF_C5 + 6

| ---- type argument of the parameter mapping: `FUN(index, type, filter)` answers the parameter code of a (mirror
| index 25..34, machine type) pair. For an added type: the slots with a descriptor field answer with the entry's
| field, the two without (29, 30) answer as the clone does; every other index runs the stock code (DigiKit's).
        .globl  mf_typearg
mf_typearg:
        move.l  0x10(%sp), %d0
        subi.l  #MF_FIRST, %d0
        cmpi.l  #MF_N, %d0
        bcc.w   9f
        lea     -16(%sp), %sp
        movem.l %d1-%d2/%a0/%a2, (%sp)
        bsr.w   mf_ownidx               | a code of the machine's own on this value index answers first
        bne.s   8f
        move.l  %a0, %d2
        subi.l  #25, %d2
        cmpi.l  #9, %d2
        bhi.s   7f
        lsl.l   #2, %d2
        lea     mf_slotmap, %a2
        move.l  (%a2, %d2.l), %d2
        bmi.s   6f
        bsr.w   mf_row
        move.l  (%a0, %d2.l), %d0
        movem.l (%sp), %d1-%d2/%a0/%a2
        lea     16(%sp), %sp
        jmp     MF_TYPEARG_EXIT
6:      bsr.w   mf_row
        move.l  O_CLONE(%a0), %d0
        movem.l (%sp), %d1-%d2/%a0/%a2
        lea     16(%sp), %sp
        move.l  %d0, 0x10(%sp)
        bra.s   9f
7:      movem.l (%sp), %d1-%d2/%a0/%a2
        lea     16(%sp), %sp
9:      move.l  0x10(%sp), %d0          | the displaced instructions
        movea.l 0x14(%sp), %a1
        jmp     MF_TYPEARG + 8
8:      movem.l 4(%sp), %d2/%a0/%a2     | d0 = the code (d1 is the stock code's scratch)
        lea     16(%sp), %sp
        jmp     MF_TYPEARG_EXIT

| mf_ownidx: d0 = row index k, a0 = value index -> d0 = the code among the row's f[0..7] and f2[0..7] whose
| parameter row (pf_table) has that value index, Z clear; or d0 = 0, Z set. Preserves every other register.
mf_ownidx:
        lea     -20(%sp), %sp
        movem.l %d1-%d3/%a1-%a2, (%sp)
        move.l  %a0, %d3                | the value index
        bsr.w   mf_row                  | a0 = the row
        lea     O_F0(%a0), %a1
        moveq   #7, %d2
        bsr.s   2f
        bne.s   8f
        lea     O_F2(%a0), %a1
        moveq   #7, %d2
        bsr.s   2f
8:      movea.l %d3, %a0
        movem.l (%sp), %d1-%d3/%a1-%a2
        lea     20(%sp), %sp
        tst.l   %d0
        rts
2:      move.l  (%a1)+, %d0             | scan d2 + 1 codes at a1: d0 = the match or 0
        beq.s   3f
        cmpi.l  #339, %d0               | (core_params: 275 stock rows + 64 added)
        bcc.s   3f
        move.l  %d0, %d1
        lsl.l   #4, %d1
        sub.l   %d0, %d1
        lsl.l   #2, %d1                 | 60 * code
        addi.l  #pf_table + 4, %d1
        movea.l %d1, %a2
        cmp.l   (%a2), %d3
        beq.s   4f
3:      subq.l  #1, %d2
        bpl.s   2b
        moveq   #0, %d0
4:      tst.l   %d0
        rts

| ---- one SRC page (DigiKit's onepage.s): for SourcePageView on a track whose machine has one_page, the page
| count accessor answers 1 (and puts the index back to 0), and the page setter takes page 0.
| mo_is_one: a0 = a view -> d0 != 0 when its track's machine has one_page. Scratch: d0, d1, a0, a1.
mo_is_one:
        lea     -8(%sp), %sp
        movem.l %d2/%a2, (%sp)
        movea.l %a0, %a2
        move.l  0x74(%a2), -(%sp)
        jsr     MO_CUR                  | the current track
        addq.l  #4, %sp
        move.l  %d0, -(%sp)
        move.l  0x78(%a2), -(%sp)
        jsr     MO_TRACK                | its object
        addq.l  #8, %sp
        move.l  %d0, -(%sp)
        jsr     MO_TYPE                 | the machine type (-1: none)
        addq.l  #4, %sp
        subi.l  #MF_FIRST, %d0
        cmpi.l  #MF_N, %d0
        bcc.s   1f                      | a stock type (or none)
        move.l  #ROWSIZE, %d1
        muls.l  %d1, %d0
        addi.l  #mf_rows, %d0
        movea.l %d0, %a0
        move.l  O_ONEPAGE(%a0), %d0
        bra.s   2f
1:      moveq   #0, %d0
2:      movem.l (%sp), %d2/%a2
        lea     8(%sp), %sp
        tst.l   %d0
        rts

        .globl  mo_count
mo_count:                               | at the page count accessor: 4(sp) = view
        movea.l 4(%sp), %a0
        move.l  #MO_SRCVT, %d0
        cmp.l   (%a0), %d0
        bne.s   9f
        bsr.w   mo_is_one
        beq.s   9f
        movea.l 4(%sp), %a0
        clr.l   0x90(%a0)
        moveq   #1, %d0
        rts
9:      movea.l 4(%sp), %a0             | the displaced instructions
        move.l  0x80(%a0), %d0
        jmp     MO_COUNT + 8

        .globl  mo_setpage
mo_setpage:                             | at the page setter: 4(sp) = view, 8(sp) = page
        movea.l 4(%sp), %a0
        move.l  #MO_SRCVT, %d0
        cmp.l   (%a0), %d0
        bne.s   9f
        bsr.w   mo_is_one
        beq.s   5f
        clr.l   8(%sp)
        bra.s   9f
5:      tst.l   8(%sp)                  | a machine with a page 2 of its own: SRC (page 1 asked) toggles it, and the
        beq.s   9f                      | view stays on its page 0 (its page 1 is the sample editor)
        movea.l 4(%sp), %a0
        bsr.w   mo_row_of
        beq.s   9f
        movea.l %d0, %a1
        btst    #2, O_FLAGS + 3(%a1)
        beq.s   9f
        cmp.l   mo_alt, %d1
        bne.s   6f
        moveq   #0, %d1
6:      move.l  %d1, mo_alt
        clr.l   8(%sp)
9:      movea.l 4(%sp), %a0             | the displaced instructions
        move.l  8(%sp), %d1
        jmp     MO_SETPAGE + 8

| mo_row_of: a0 = a SourcePageView -> d0 = the row of its track's added machine (Z set: 0, a stock type), d1 = the
| key of page 2 for that track and type ((type << 8 | track) + 1). Scratch: d0, d1, a0, a1.
mo_row_of:
        lea     -8(%sp), %sp
        movem.l %d2/%a2, (%sp)
        movea.l %a0, %a2
        move.l  0x74(%a2), -(%sp)
        jsr     MO_CUR                  | the current track
        addq.l  #4, %sp
        move.l  %d0, %d2
        move.l  %d0, -(%sp)
        move.l  0x78(%a2), -(%sp)
        jsr     MO_TRACK                | its object
        addq.l  #8, %sp
        move.l  %d0, -(%sp)
        jsr     MO_TYPE                 | the machine type (-1: none)
        addq.l  #4, %sp
        move.l  %d0, %d1
        lsl.l   #8, %d1
        andi.l  #0xff, %d2
        or.l    %d2, %d1
        addq.l  #1, %d1
        subi.l  #MF_FIRST, %d0
        cmpi.l  #MF_N, %d0
        bcc.s   1f
        bsr.w   mf_row
        move.l  %a0, %d0
        bra.s   2f
1:      moveq   #0, %d0
2:      movem.l (%sp), %d2/%a2
        lea     8(%sp), %sp
        tst.l   %d0
        rts

| ---- the code of knob k on the SRC page (SourcePageView vfunc 47, stock 0x40017cd4: 4(sp) = view, 8(sp) = k):
| page 2 of an added machine answers with its f2[k]. Every other case is the stock function.
        .globl  mo_codeat
mo_codeat:
        movea.l 4(%sp), %a0
        bsr.w   mo_row_of
        beq.s   9f
        movea.l %d0, %a1
        btst    #2, O_FLAGS + 3(%a1)
        beq.s   9f
        moveq   #1, %d0
        move.b  %d0, mo_seen            | the SRC page of a two-page machine is on screen
        cmp.l   mo_alt, %d1
        bne.s   9f
        moveq   #2, %d0
        move.b  %d0, mo_seen
        move.l  8(%sp), %d0
        cmpi.l  #8, %d0
        bcc.s   9f
        move.l  O_F2(%a1, %d0.l*4), %d0
        rts
9:      jmp     MO_CODEAT

| ---- ev_draw: the page marker of a two-page machine, over the right of the SRC page's header ("1/2", "2/2").
        .globl  mo_draw
mo_draw:                                | 4(sp) = bitmap, 8(sp) = controller
        moveq   #0, %d0
        move.b  mo_seen, %d0
        beq.s   9f
        clr.b   mo_seen
        move.l  %d2, -(%sp)
        move.l  %d0, %d2
        clr.l   -(%sp)                  | colour 0
        pea     63.w
        pea     127.w
        pea     56.w
        pea     110.w
        move.l  28(%sp), -(%sp)         | bitmap
        jsr     FILLRECT
        lea     24(%sp), %sp
        lea     mo_m1, %a0
        cmpi.l  #2, %d2
        bne.s   1f
        lea     mo_m2, %a0
1:      move.l  %a0, -(%sp)
        pea     mo_fmt
        pea     -1.w
        pea     57.w
        pea     113.w
        pea     FONT5
        move.l  32(%sp), -(%sp)         | bitmap
        jsr     TEXTF
        lea     28(%sp), %sp
        move.l  (%sp)+, %d2
9:      rts

| descriptor field offset of mirror index 25 .. 34 (-1: none)
        .balign 4
mf_slotmap:
        .long   8, 12, 16, 20, -1, -1, 24, 28, 32, 36
mf_empty:
        .byte   0
mo_fmt: .asciz  "%s"
mo_m1:  .asciz  "1/2"
mo_m2:  .asciz  "2/2"

        .section .bss
        .balign 4
        .globl  mf_rows, mf_names, mf_permit, mf_pertype, mf_list_buf, mf_list_end, mf_entries
mf_ready:    .space 4
mo_alt:      .space 4                   | page 2 shown: (type << 8 | track) + 1, else 0
mo_seen:     .space 4                   | ev_draw: 1/2 the SRC page of a two-page machine was drawn on page 1/2
mf_entries:  .space 4
mf_list_end: .space 4
mf_rows:     .space ROWSIZE * MF_N
mf_names:    .space 12 * (MF_LAST + 1)
mf_permit:   .space 4 * (MF_LAST + 1)
mf_pertype:  .space (MF_LAST + 4) & ~3
mf_list_buf: .space 4 * (MF_LAST + 1)
mf_rank_buf: .space 8 * (MF_LAST + 1)
mf_strbuf:   .space REPSIZE * 2 * MF_N

| ---- value 28 (core 2.4). Before and after the per-frame parameter update, stock splits each audio track's value 28
| (a sample machine's SAMP: bank * 128 + slot) into 29 and 30 (0x4002e8de) and joins them back into 28 (0x4002e974),
| which cuts any other value 28 to its low 10 bits. A machine with a page 2 of its own keeps 28, 29 and 30 as they are.
| Sites: tst.l d0; beq.s SKIP; move.w / mvs.w 90(a4),d0 (8 bytes); the track is d7 (split) / d6 (join).
        .globl  core_split28, core_join28
core_split28:
        tst.l   %d0
        beq.s   1f
        move.l  %d7, %d0
        bsr.s   trk_page2
        bne.s   1f
        moveq   #0, %d0
        move.w  90(%a4), %d0
        jmp     0x4002e8e6
1:      jmp     0x4002e8fe

core_join28:
        tst.l   %d0
        beq.s   1f
        move.l  %d6, %d0
        bsr.s   trk_page2
        bne.s   1f
        mvs.w   90(%a4), %d0
        jmp     0x4002e97c
1:      jmp     0x4002e994

| trk_page2: d0 = an audio track -> Z clear when its machine (type byte 0x800064e0 + 154 t, the copy the frame builder reads) has a page 2. Keeps d1-a7.
trk_page2:
        lea     -8(%sp), %sp
        movem.l %d1/%a0, (%sp)
        move.l  #154, %d1
        muls.l  %d0, %d1
        addi.l  #0x800064e0, %d1          | the working copy 0x400d9406 makes of 0x80003cd0
        movea.l %d1, %a0
        mvs.b   (%a0), %d0
        bsr.w   mf_has_page2
        movem.l (%sp), %d1/%a0          | (movem and lea leave the flags)
        lea     8(%sp), %sp
        rts
