# The Digitakt II 1.17 pattern and its locks

The active pattern's address is the long at `0x4316501c`. A pattern is 121740 bytes (`0x1db8c`, the size every
pattern copy in the firmware uses). Offsets below are from its start; "step" is 0-127 and "track" 0-15.

Read from the step builder (`0x400d6982`, which fills the fire event), its lock reader (`0x400d6916`) and the editors
the panel calls (below), and checked in the emulator by diffing the pattern while trigs and locks are set from the panel (`lkdiff.py`, LOCKDBG).

| offset | size | what |
|---|---|---|
| `track * 1701` | 1701 per track | a track (below) |
| 27216 | 8192 x 6 | trig records (below) |
| 76368 | 2048 x u16 | first record of each step, `[track * 128 + step]`; `0xffff` none |
| 80464 | 8192 x u16 | next record in the chain, `[record]`; `0xffff` ends it |
| 96848 | 1024 | free-record bitmap, 1 = free (bit 0 of each big-endian long is the first record of its 32) |
| 97872 | 80 x 258 | parameter-lock slots (below) |
| 118512 | 16 x 71 | the slot of each track's value, `[track * 71 + value index]`, signed; -1 not locked |
| 119648 | 2048 | how many parameter locks each step has, `[track * 128 + step]` |
| 121721.. | | pattern-wide bytes the step builder reads (121721, 121722, 121723) |

## A track

| offset | what |
|---|---|
| `2 * step` | the step's word: bit 0 trig, bits 7-10 trig types (bit 7 SYN: it plays a note), bits 11-14 their overrides of the track's word at 1154 (a trig the panel places is `0x0381`, a trigless lock trig `0x7801`) |
| 256, 384, 512 + step | per-step locks of track settings the step builder uses, signed; -1 the track's own (1161, 1162, 1163) |
| 640, 768, 896 + step | the step's trig condition; 896 = -1 none (the track's 1168) |
| 1024 + step | the step's sound lock, signed; -1 none |
| 1152 VEL, 1153 LEN, 1157 NOTE | the track's defaults (LEN: 14 = 1/16, 127 = INF) |

## Trig records

Placing a trig takes four records from the bitmap and chains them from the step's first-record entry. A record:

| byte | what |
|---|---|
| 0 | track |
| 1 | step |
| 2 | NOTE lock, 0xff none (set on the first record only) |
| 3 | VEL lock, 0xff none (set on all four) |
| 4 | LEN lock, 0xff none (set on all four) |
| 5 | micro timing, signed, 0 on the step (LEFT / RIGHT with the trig held); a note before its step is played by the step before |

The fire event carries the pattern's record base at +28 and the record index at +32 (-1 when the step has none,
and then +38..+41 are the track's NOTE, VEL, LEN and 0).

## Parameter-lock slots

A pattern has 80 slots. A slot is a header of two bytes, the value index (0-70) and the track, then 128 signed
16-bit values, one per step, `0xffff` for a step without the lock. A value is 8.8 fixed point: the high byte is the
value as the sound stores it (TUNE at 0 is `0x4000`). The slot table at 118512 points each locked value of a track
at its slot; the counts at 119648 let the step builder skip steps without locks. For a step, the lock reader walks
the track's 71 values and copies `{index, value}` pairs for each slot that has a value at that step.

## The firmware's editors (1.17)

| address | does |
|---|---|
| `0x40198b7e()` | the project; pattern object `i` is at +0x43d0 + 2388 i (its pattern's bytes at +16), track object `t` at +0x70 + 132 t of that (store pointers at +44 parameter locks, +48 trig records; the track at +60) |
| `0x400597c8(track obj, step, flags, on)` | sets or clears step flags; bit 0 places or removes the trig (`0x40059610` sets a new one up: four `{ff, ff, ff, 0}` notes) |
| `0x400392be(trig store, track, step, vector)` | replaces a step's notes: a vector `{begin, end}` of 4-byte `{note, vel, len, flag}` |
| `0x400391a4(trig store, track, step)` | frees a step's records |
| `0x40054ad4(track obj, step, index, value)` | sets a parameter lock (`0x40040702` on the store); `0x40054b5c(track obj, step)` clears a step's |
| `0x40054a6c(track obj)` | the track's length |

The active pattern's own number is the long at +121736.

Not known yet: what bytes 2-4 of records 2-4 hold when a trig has more than one note, and bit 4 of the step word (set on odd steps of an empty pattern).

Emulator note: a turn while a trig is held sets the lock at the current value (later turns do not move it), and
the emulator stops with exception vector 5 a few beats into MIDI clock, on the stock OS as well.
