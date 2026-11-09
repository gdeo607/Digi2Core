# The Digitakt II 1.17 pattern and its locks

The active pattern's address is the long at `0x4316501c`. A pattern is 121740 bytes (`0x1db8c`, the size every
pattern copy in the firmware uses). Offsets below are from its start; "step" is 0-127 and "track" 0-15.

Read from the step builder (`0x400d6582`, which fills the fire event) and its lock reader (`0x400d6516`), and checked
in the emulator by diffing the pattern while trigs and locks are set from the panel (`lkdiff.py`, LOCKDBG).

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
| `2 * step` | the step's word: bit 0 trig, bit 7 and up flags (a trig placed from the panel is `0x0381`) |
| 256, 384, 512 + step | per-step locks of track settings the step builder uses, signed; -1 the track's own (1161, 1162, 1163) |
| 640, 768, 896 + step | the step's trig condition arguments; 896 = -1 no condition (the track's 1168) |
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
| 5 | 0; the step builder skips a record whose byte 5 is negative |

The fire event carries the pattern's record base at +28 and the record index at +32 (-1 when the step has none,
and then +38..+41 are the track's NOTE, VEL, LEN and 0).

## Parameter-lock slots

A pattern has 80 slots. A slot is a header of two bytes, the value index (0-70) and the track, then 128 signed
16-bit values, one per step, `0xffff` for a step without the lock. A value is 8.8 fixed point: the high byte is the
value as the sound stores it (TUNE at 0 is `0x4000`). The slot table at 118512 points each locked value of a track
at its slot; the counts at 119648 let the step builder skip steps without locks. For a step, the lock reader walks
the track's 71 values and copies `{index, value}` pairs for each slot that has a value at that step.

Not known yet: what bytes 2-4 of records 2-4 hold when a trig has more than one note, and the step word's flag bits.

Emulator note: a turn while a trig is held sets the lock at the current value (later turns do not move it), and
the emulator stops with exception vector 5 a few beats into MIDI clock, on the stock OS as well.
