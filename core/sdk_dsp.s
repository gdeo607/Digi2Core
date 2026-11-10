// core-dt2 2.7: the SDK machines' voices on the DSP, the assembly part (sdk_dsp.c has the C). Each SDK machine's
// stub (the SDK builder writes it, one per machine: its dsp-inline voice routine, registered in core_dsp_voices
// for the machine's type) is:
//       R1 = 1; R1 = R0 AND R1; IF NE JUMP _sk_odd;       the odd voice of a track copies the even one
//       R1 = <the machine's sdk_dsp_machine>; CALL _sk_enter;
//       R0 = PASS R0; IF EQ JUMP _sk_leave;              silent: out is zeroed
//       R4 = PASS R0; R2 = I6; CJUMP <render> (DB); DM(I7,M7) = R2; DM(I7,M7) = <back> - 1;
//   back: JUMP _sk_leave;
// _sk_enter (R0 = the voice, R1 = the machine, R2 = the track, I2 = the voice's output) saves the renderer's I6,
// I7, L6, L7 and L0-L5, moves to core's C stack and calls sdk_dsp_voice; it returns (RTS) with R0 = the
// struct elek_voice or 0 and R8 = the output. _sk_leave puts them back and returns to the renderer. render may
// change R0-R15, I0-I5, I12, I13, M0-M4, L0-L5 and LCNTR, as on the Digitone II.
// The pattern is STRING's entry shim (modules/machines/string/src/dsp/strg_entry.s), itself derived from DigiKit's
// Plaits shim: digikit by Em D - https://github.com/ElekLabs/digikit (modified). SPDX-License-Identifier: AGPL-3.0-or-later

.SECTION/PM seg_pmco;
.GLOBAL _sk_odd;
.GLOBAL _sk_enter;
.GLOBAL _sk_leave;
.EXTERN _di_return_out;
.EXTERN sdk_dsp_voice.;

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

// ---- _sk_enter: R0 = the voice, R1 = the machine, R2 = the track, I2 = the output
_sk_enter:
    R4 = PASS R0;
    R8 = PASS R2;
    R12 = PASS R1;
    R0 = _sk_save;
    I3 = R0;
    R0 = I6;
    DM(I3, M6) = R0;
    R0 = I7;
    DM(I3, M6) = R0;
    R0 = L6;
    DM(I3, M6) = R0;
    R0 = L7;
    DM(I3, M6) = R0;
    R0 = I2;
    DM(I3, M6) = R0;
    R0 = L0;
    DM(I3, M6) = R0;
    R0 = L1;
    DM(I3, M6) = R0;
    R0 = L2;
    DM(I3, M6) = R0;
    R0 = L3;
    DM(I3, M6) = R0;
    R0 = L4;
    DM(I3, M6) = R0;
    R0 = L5;
    DM(I3, M6) = R0;
    L6 = 0;
    L7 = 0;
    R0 = _sk_stack;
    R1 = 4092;
    R0 = R0 + R1;
    I7 = R0;
    R0 = I2;
    DM(I7, M7) = R0;                // sdk_dsp_voice's fourth argument: the output
    R2 = I6;
    CJUMP sdk_dsp_voice. (DB);
    DM(I7, M7) = R2;
    DM(I7, M7) = _sk_enter_back - 1;
_sk_enter_back:
    R1 = _sk_save;
    R2 = 16;
    R1 = R1 + R2;
    I3 = R1;
    R8 = DM(I3, M5);                // the output
    RTS;

// ---- _sk_leave: the renderer's registers back, and its return
_sk_leave:
    R0 = _sk_save;
    I3 = R0;
    R0 = DM(I3, M6);
    I6 = R0;
    R0 = DM(I3, M6);
    I7 = R0;
    R0 = DM(I3, M6);
    L6 = R0;
    R0 = DM(I3, M6);
    L7 = R0;
    R0 = DM(I3, M6);                // (the output)
    R0 = DM(I3, M6);
    L0 = R0;
    R0 = DM(I3, M6);
    L1 = R0;
    R0 = DM(I3, M6);
    L2 = R0;
    R0 = DM(I3, M6);
    L3 = R0;
    R0 = DM(I3, M6);
    L4 = R0;
    R0 = DM(I3, M6);
    L5 = R0;
    JUMP _di_return_out;

.SECTION/DM seg_dmda;
.GLOBAL _sk_save;
.PKDATA _sk_save, 44;                   // I6, I7, L6, L7, the output, L0-L5
.GLOBAL _sk_stack;
.PKBSS _sk_stack, 4096;                 // the C stack (written before it is read)
.GLOBAL sdk_dsp_state.;
.PKBSS sdk_dsp_state., 8192;            // 32 voices x 256 bytes (sdk_dsp.c)
.GLOBAL sdk_dsp_cc.;
.PKBSS sdk_dsp_cc., 8192;               // 16 tracks x 128 CCs (sdk_dsp.c)
