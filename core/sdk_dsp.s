// core-dt2 2.7: the SDK machines' voices on the DSP, the assembly part (sdk_dsp.c has the C). Each SDK machine's
// stub (the SDK builder writes it, one per machine: its dsp-inline voice routine) uses these:
//   _sk_odd    the odd voice of a track: a copy of the even voice's block, then the routine's return (as STRING's);
//   _sk_save   five words: the renderer's I6, I7, L6, L7 and the voice's output while the stub runs on core's stack;
//   _sk_stack  core's C stack for the stubs (4 KB; the stubs run one at a time, in the renderer);
//   sdk_dsp_state.  each voice's 256 bytes of state (reserved, not loaded).
// The pattern is STRING's entry shim (modules/machines/string/src/dsp/strg_entry.s), itself derived from DigiKit's
// Plaits shim: digikit by Em D - https://github.com/ElekLabs/digikit (modified). SPDX-License-Identifier: AGPL-3.0-or-later

.SECTION/PM seg_pmco;
.GLOBAL _sk_odd;
.EXTERN _di_return_out;

// Every instruction in its normal 48-bit form; no indirect jumps.
.NOCOMPRESS;

// ---- the odd voice: a copy of the even voice's block (I2: the odd voice's output; the even one's is 0x80 bytes below)
_sk_odd:
    R0 = I2;
    R1 = -128;
    R0 = R0 + R1;
    I3 = R0;
    LCNTR = 32, DO _sk_copy UNTIL LCE;
    R0 = DM(I3, M6);
_sk_copy:
    DM(I2, M6) = R0;
    JUMP _di_return_out;

.SECTION/DM seg_dmda;
.GLOBAL _sk_save;
.PKDATA _sk_save, 20;                   // I6, I7, L6, L7, the output
.GLOBAL _sk_stack;
.PKBSS _sk_stack, 4096;                 // the C stack (written before it is read)
.GLOBAL sdk_dsp_state.;
.PKBSS sdk_dsp_state., 8192;            // 32 voices x 256 bytes (sdk_dsp.c)
