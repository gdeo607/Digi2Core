# Digi2Core: core-dt2 2.6 for the Digitakt II

The core every mod in this family builds on, for the **Elektron Digitakt II** on **OS 1.17**. It is an elekloader
mod (`core`, version 2.6). It starts from core 1.0 (irpina's boot copier and hook bus, unchanged: the same seven
sites, events and `.fast` table) and adds the frameworks DigiKit's All-in-One builds its machines on, turned into core
services. On top of those it gives added machines a second SRC page with controls that are saved, p-lockable and LFO
destinations.

On its own it changes nothing the unit does. Mods that use it:

- [Digi2MacroOSC](https://github.com/gdeo607/Digi2MacroOSC): MACRO, a macro-oscillator machine.
- [Digi2ElixirPotionsDRUM](https://github.com/gdeo607/Digi2ElixirPotionsDRUM): ELIXIR, a drum-synthesis machine with two SRC pages.

> Unofficial and unsupported, and experimental. Flashing modified firmware is at your own risk; the stock OS always
> recovers the unit (hold FUNC while powering on, TRIG 4, then send the stock .syx over MIDI). This repository
> contains no Elektron code or firmware.

## Building firmware with it

```
python -m elekloader.patch --stock Digitakt_II_OS1.17.syx \
  --mod elemods/core-2.6.elemod --mod <a mod>.elemod --out Digitakt_II_mods.syx
```

You need an elekloader with `sharc_raw` support for the Digitakt II (the `dt2-sharc-raw` branch of
[gdeo607/elekloader](https://github.com/gdeo607/elekloader/tree/dt2-sharc-raw), proposed upstream). Never share the
resulting .syx: it contains Elektron's OS.

## What a mod gets

| table / event | entry | what a mod gets |
|---|---|---|
| `ev_tick`, `ev_draw`, `ev_key`, `ev_enc`, `ev_settings`, `ev_personalize`, `core_fast` | as core 1.0 | the hook bus |
| `core_machines` | pointer to a `struct core_machine_dt2` (`machines.s`); the SDK's `"machines": [{"id", "descriptor"}]` adds it and claims `machine:<id>` | a machine type 7-23: the machine list, its name, page, permission, per-type byte, its parameters on A-H, the clone tests, one or two SRC pages |
| `core_params` | pointer to a `struct core_param_dt2` (`params.s`); claim `param:<code>` | a parameter code 275-338: name, label, range, default, formatter, randomizer, its knob bar; it locks and saves as the template's kind does |
| `core_knobs` | `{first code, last code, fn}` | the SRC page's knob widget for those codes |
| DSP `core_dsp_voices` | `{type, pc}` (list, 16) | the voices of that machine type render with the mod's DSP routine (DigiKit's dsp-inline ABI) |
| DSP `core_mf_selector` | 4 bytes at index = type | the DSP's sample-renderer selector for the type (a machine gives its clone's) |
| `core_machine_row(type)` | function | an added type's row, its flags at +52 |
| `core_trig_*`, `core_plock_*` | functions (`core/pattern.h`) | the active pattern's trigs, their notes (NOTE, VEL, LEN locks) and parameter locks, read and edited through the firmware's own pattern editors (below) |

Machine flags (`struct core_machine_dt2` +12): bit 0 one SRC page; bit 1 the machine's voices may be shared by a
POLY mode; bit 2 a second SRC page; bit 3 knob H is the machine's own parameter, not LEV.

Mods ship their DSP code as relocatable objects (`sharc_raw` `objects`); the linker places them in the DSP's free L2,
so two mods never need to agree on DSP addresses.

## The second SRC page

A machine with flag bit 2 gets SRC page 2 (press SRC again; "1/2" / "2/2" in the header) with up to four codes of its
own, and knob D of page 1 is usable too. These are the only places in a sound's 71 values that a synth machine can
take over:

| page | knob | value index | stock use | `core_params` slot |
|---|---|---|---|---|
| 1 | D | 28 | SAMP (sample machines) | 3 |
| 2 | A | 29 | BANK | 8 |
| 2 | B | 30 | SLOT | 9 |
| 2 | C | 69 | nothing on audio tracks | 10 |
| 2 | D | 70 | nothing on audio tracks | 11 |

- **Saved**: the stock OS saves runtime values 0-68 only. Core copies the save and load tables with 69 -> storage slot
  77 and 70 -> slot 78 (the record's zero-filled spare area), points every user at the copies and raises the bounds
  (sound save and load, the lock-id maps, pattern-lock save and load). A project saved with core loads on the stock
  OS, which ignores slots 77 and 78.
- **P-locks**: locks are kept per value index below 71 and saved by storage id, so the same tables cover them.
- **LFO**: the LFO writes any index up to 70. The list the firmware builds for a machine's SRC group (LFO destinations,
  machine-select defaults, randomize) walks 25..34 and, through core's end function, 69 and 70.
- **DSP**: the frame builder copies 69 and 70 to the per-track halfwords 10 and 11, and 28-30 to halfwords 13-15 (the
  builder zeroes 3-5 for sample machines).

## The pattern service

`core/pattern.h` declares it; [docs/PATTERN.md](docs/PATTERN.md) has the layout it reads.

| function | does |
|---|---|
| `core_trig_get(track, step)`, `core_trig_set(track, step, on)` | is there a trig; place or remove one as a trig key in GRID RECORDING does (a new trig takes the track's defaults; a removed one loses its notes and locks) |
| `core_trig_notes(track, step, notes, max)`, `core_trig_set_notes(track, step, notes, n)` | a trig's notes, `{note, vel, len, flag}`, 0xff for the track's; a trig the panel places has four |
| `core_trig_lock(track, step, which, value)` | one NOTE (0), VEL (1) or LEN (2) lock, as the TRIG page sets it; 0xff clears |
| `core_plock_get / set(track, step, index, value)`, `core_plock_clear(track, step)`, `core_plock_count` | a parameter lock of value index 0-70, 8.8 (high byte = the value as the sound stores it); a pattern has 80 slots |
| `core_pattern()`, `core_pattern_obj()`, `core_track_obj(track)`, `core_track_len(track)` | the active pattern's bytes, the firmware's objects for it and its tracks, a track's length |

Tracks are 0-15, steps 0-127. The writers call the firmware's editors (the step-flag, trig-note and
parameter-lock routines the panel uses), so the records, slots, counts and step flags stay as the firmware keeps
them. Call them from the UI side (`ev_tick`, `ev_key`, `ev_enc`, `ev_draw`), not from the sequencer's fire hook.

## Versions

- **2.1**: the second SRC page; values 69 and 70 saved, lockable and LFO destinations (`storage.s`).
- **2.2**: flag bit 3: knob H is the machine's own parameter; the DSP's level (halfword 9) stays at 100 for such a
  machine and knob H's value goes to halfword 12.
- **2.3**: values 28-30 reach the DSP (halfwords 13-15).
- **2.4**: stock splits each audio track's value 28 into 29 and 30 (bank and slot) around the per-frame parameter
  update and joins them back, cutting any other value 28 to its low 10 bits; a machine with its own page 2 now keeps
  28-30 as they are. Checked in the emulator; not yet heard on a unit.
- **2.5**: a machine with its own knob H (flag bit 3) but no page 2 also keeps halfwords 10-15 as its own values
  (the clone-6 slice copy skips them).
- **2.6**: the pattern service (`pattern.c`, `pattern.h`). Checked in the emulator: a trig placed, NOTE, VEL and LEN
  locked and a TUNE lock set, changed and cleared write the same bytes the panel does; out-of-range calls are
  refused.

Known: on the SRC page a trig key picks a sample and turns the track into ONESHOT, as on the stock OS.

## Layout

| path | what |
|---|---|
| `core/` | the sources: `core.s`, `settings.s`, `fast.s`, `personalize.s`, `boot.s` (core 1.0), `machines.s`, `params.s`, `knobs.s`, `storage.s`, `pattern.c` and `pattern.h`, `mod.json`, `sharc_raw.json` and DigiKit's `dsp-inline-dsp.dko.json` |
| `docs/PATTERN.md` | the 1.17 pattern: tracks, trig records (NOTE, VEL, LEN locks) and parameter-lock slots |
| `tools/build_core.py` | writes `core/mod.json` and `core/sharc_raw.json` from your stock file and DigiKit's 1.17 anchors |
| `elemods/` | the built core |

Build the core with elekloader's SDK and an m68k cross GCC:

```
python -m elekloader.sdk.build core --stock Digitakt_II_OS1.17.syx
```

## Licence

AGPL-3.0-or-later (see `LICENSE`), as DigiKit's frameworks; core 1.0 is GPL-2.0-or-later (irpina, elekloader).
