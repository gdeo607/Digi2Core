| SPDX-License-Identifier: AGPL-3.0-or-later
| core-dt2 2.1: the page-2 values 69 and 70 are saved, loaded, p-locked and offered as LFO destinations.
|
| A sound keeps 71 values (runtime index 0-70) and is saved as 91 storage slots, of which the stock OS uses 77; two
| tables map one to the other: save (runtime 0-68 -> slot, 69 longs at ST_SAVE) and load (slot 0-76 -> runtime, 77
| longs at ST_LOAD). Runtime 69 and 70 are not in them, so the stock OS never saves them. Core copies both tables
| at boot with two more entries (69 -> slot 77, 70 -> slot 78 and back), points every user of them at the copies
| and raises their bounds (mod.json's sites): the sound save and load, the lock-id maps both ways, the pattern-lock
| save and load. Slots 77 and 78 are inside the record's zero-filled area that the stock OS skips on load, so a
| project saved here still loads on the stock OS (the two values are ignored there). The LFO DEST value of a sound
| goes through the same tables, so an LFO aimed at 69 or 70 is saved too.
|
| The parameter list the firmware builds for a machine's SRC group (machine select defaults, randomize, the LFO and
| MOD destinations) walks value index 25..34 with an end function; core's end function continues at 69 and 70 for
| a machine with a page 2 of its own.

        .equ    N_SAVE, 69
        .equ    N_LOAD, 77

        .section .run, "ax"
        .balign 4

| ---- core_store_boot: the two tables (from core_boot_init). Clobbers d0, a0, a1.
        .globl  core_store_boot
core_store_boot:
        lea     ST_SAVE, %a1
        lea     st_save, %a0
        moveq   #N_SAVE, %d0
1:      move.l  (%a1)+, (%a0)+
        subq.l  #1, %d0
        bne.s   1b
        moveq   #77, %d0
        move.l  %d0, (%a0)+             | runtime 69 -> slot 77
        moveq   #78, %d0
        move.l  %d0, (%a0)+             | runtime 70 -> slot 78
        lea     ST_LOAD, %a1
        lea     st_load, %a0
        moveq   #N_LOAD, %d0
2:      move.l  (%a1)+, (%a0)+
        subq.l  #1, %d0
        bne.s   2b
        moveq   #69, %d0
        move.l  %d0, (%a0)+             | slot 77 -> runtime 69
        moveq   #70, %d0
        move.l  %d0, (%a0)+             | slot 78 -> runtime 70
        rts

| ---- the end of the SRC-group walk (the list builder's `jsr (a3)`, stock 0x400da004: return 34). The builder keeps
| the value index in d2 and the track's type in d4 and stops when the end is below d2. For a type with a page 2 of
| its own, after 34 the walk goes on at 69 and ends after 70. d0 = the end; d1, a0, a1 are scratch.
        .globl  st_list_end
st_list_end:
        cmpi.l  #35, %d2
        blt.s   9f
        move.l  %d0, -(%sp)
        move.l  %d4, %d0
        jsr     mf_has_page2
        movea.l (%sp)+, %a0             | (movea leaves the flags)
        beq.s   9f
        cmpi.l  #69, %d2
        bge.s   1f
        moveq   #69, %d2                | skip 35..68
1:      moveq   #70, %d0
        rts
9:      moveq   #34, %d0
        rts

        .section .bss
        .balign 4
        .globl  st_save, st_load
st_save: .space 4 * (N_SAVE + 2)
st_load: .space 4 * (N_LOAD + 2)
