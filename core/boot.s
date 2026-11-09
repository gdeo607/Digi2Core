| SPDX-License-Identifier: GPL-2.0-or-later
| core-dt2 2.0: the boot work (core.s calls core_boot_init with BOOT_INIT, after the copy of the mods' RAM and
| before the OS reads its data): the machine and parameter tables the mods add to.
        .section .run, "ax"
        .balign 4                       | (a .run section is byte-aligned by default: keep code even)
        .globl  core_boot_init
core_boot_init:
        lea     -44(%sp), %sp
        movem.l %d2-%d7/%a2-%a6, (%sp)
        jsr     core_sdk_boot           | core 2.7: the SDK machines and their codes, for the two below
        jsr     core_machines_boot
        jsr     core_params_boot
        jsr     core_store_boot
        movem.l (%sp), %d2-%d7/%a2-%a6
        lea     44(%sp), %sp
        rts

| core_boot_late: at 0x4000053e, the reset code's two calls (`jsr` the SRAM data copy, `jsr` the .bss clear), where
| DigiKit's loader runs on the unit: after VBR_FN (the vector base is set), before the OS turns the caches on.
| core_boot_init there, then the two stock calls; their rts returns past the site.
        .globl  core_boot_late
core_boot_late:
        jsr     core_boot_init
        jsr     0x4000045c
        jmp     0x400004b2
