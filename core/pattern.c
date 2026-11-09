/* core-dt2 2.6: the pattern service, for the Digitakt II 1.17.
 *
 * Mods read a step's trig, its notes (the NOTE, VEL and LEN locks) and its parameter locks, and change them
 * through the firmware's own pattern editors, as the panel does: the editors keep the pattern's records, slots,
 * counts and flags consistent and tell the rest of the firmware about the change. The layout is in
 * docs/PATTERN.md of Digi2Core.
 *
 * Call the writers from the UI side (ev_tick, ev_key, ev_enc, ev_draw), not from the sequencer's fire hook.
 * Tracks are 0-15, steps 0-127. They act on the active pattern. */
#include <stdint.h>

#define PATTERN        (*(uint8_t *volatile *)0x4316501c)
#define PAT_SIZE       121740
#define PAT_INDEX      121736          /* u32: the pattern's own number, 0-127 */
#define TRK_STRIDE     1701
#define REC_BASE       27216           /* 8192 records of 6 bytes */
#define REC_HEAD       76368           /* u16 [track * 128 + step] */
#define REC_NEXT       80464           /* u16 [record] */
#define PL_BASE        97872           /* 80 slots of 258 bytes */
#define PL_SLOTOF      118512          /* s8 [track * 71 + value index] */
#define PL_COUNT       119648          /* u8 [track * 128 + step] */
#define NREC           8192
#define NSLOT          80

/* The firmware, 1.17 (C calling convention: 32-bit arguments on the stack, result in d0) */
#define FW_PROJECT     0x40198b7e      /* the project: 128 pattern objects at +0x43d0, 2388 bytes apart */
#define FW_STEP_FLAGS  0x400597c8      /* (track object, step, flags, on): bit 0 the trig; on sets it up */
#define FW_TRIG_NOTES  0x400392be      /* (trig store, track, step, vector of 4-byte notes) */
#define FW_PLOCK_SET   0x40054ad4      /* (track object, step, value index, value) -> bool */
#define FW_PLOCK_CLR   0x40054b5c      /* (track object, step): all its parameter locks */
#define FW_TRACK_LEN   0x40054a6c      /* (track object) -> the track's length in steps */
#define PATOBJ_FIRST   0x43d0
#define PATOBJ_STRIDE  2388
#define TRACKOBJ_FIRST 0x70
#define TRACKOBJ_STRIDE 132

struct core_note {                      /* one of a trig's notes; 0xff: the track's */
    uint8_t note, vel, len, flag;       /* flag: 0; the step builder skips a note whose flag is negative */
};

struct fw_vector { const void *begin, *end, *cap; };

typedef uint32_t (*fw1)(uint32_t);
typedef uint32_t (*fw2)(uint32_t, uint32_t);
typedef uint32_t (*fw4)(uint32_t, uint32_t, uint32_t, uint32_t);

static int ok(int track, int step)
{
    return (unsigned)track < 16 && (unsigned)step < 128 && PATTERN;
}

static uint16_t rd16(const uint8_t *p)
{
    return (uint16_t)((p[0] << 8) | p[1]);
}

/* The active pattern's bytes, or 0 */
uint8_t *core_pattern(void)
{
    return PATTERN;
}

/* The firmware's object for the active pattern, or 0 */
uint8_t *core_pattern_obj(void)
{
    uint8_t *pat = PATTERN, *proj, *o;
    uint32_t i;
    if (!pat || !(proj = (uint8_t *)((uint32_t (*)(void))FW_PROJECT)()))
        return 0;
    i = *(uint32_t *)(pat + PAT_INDEX);
    if (i < 128) {
        o = proj + PATOBJ_FIRST + PATOBJ_STRIDE * i;
        if (*(uint8_t **)(o + 16) == pat)
            return o;
    }
    for (i = 0; i < 128; i++) {         /* the index does not match: find the object by its pattern */
        o = proj + PATOBJ_FIRST + PATOBJ_STRIDE * i;
        if (*(uint8_t **)(o + 16) == pat)
            return o;
    }
    return 0;
}

/* The firmware's editor for a track of the active pattern, or 0 */
uint8_t *core_track_obj(int track)
{
    uint8_t *o;
    if ((unsigned)track >= 16 || !(o = core_pattern_obj()))
        return 0;
    return o + TRACKOBJ_FIRST + TRACKOBJ_STRIDE * track;
}

/* The track's length in steps (1-128), or 0 */
int core_track_len(int track)
{
    uint8_t *tv = core_track_obj(track);
    return tv ? (int)((fw1)FW_TRACK_LEN)((uint32_t)tv) : 0;
}

/* 1 if the step has a trig */
int core_trig_get(int track, int step)
{
    return ok(track, step) && (rd16(PATTERN + TRK_STRIDE * track + 2 * step) & 1);
}

/* Place (on) or remove a trig, as a trig key does in GRID RECORDING: a new trig takes the track's defaults,
 * a removed one loses its notes and parameter locks. 0 on success, -1 if out of range or past the track's
 * length. */
int core_trig_set(int track, int step, int on)
{
    uint8_t *tv;
    if (!ok(track, step) || !(tv = core_track_obj(track)) || step >= core_track_len(track))
        return -1;
    ((fw4)FW_STEP_FLAGS)((uint32_t)tv, (uint32_t)step, 1, on ? 1 : 0);
    return 0;
}

/* A trig's notes, at most max; returns how many (0: no trig, or no notes) */
int core_trig_notes(int track, int step, struct core_note *out, int max)
{
    const uint8_t *pat = PATTERN, *r;
    unsigned rec;
    int n = 0, guard = NREC;
    if (!ok(track, step))
        return 0;
    rec = rd16(pat + REC_HEAD + 2 * (track * 128 + step));
    while (rec < NREC && n < max && guard--) {
        r = pat + REC_BASE + 6 * rec;
        out[n].note = r[2];
        out[n].vel = r[3];
        out[n].len = r[4];
        out[n].flag = r[5];
        n++;
        rec = rd16(pat + REC_NEXT + 2 * rec);
    }
    return n;
}

/* Replace a trig's notes with n of them (1-4): the first note's NOTE is the trig's NOTE lock, each note's VEL
 * and LEN its locks, 0xff the track's. A trig the panel places has four, all 0xff; pass four to keep that
 * shape. The step must have a trig. 0 on success, -1 otherwise. */
int core_trig_set_notes(int track, int step, const struct core_note *notes, int n)
{
    uint8_t *tv;
    struct fw_vector v;
    if (n < 1 || n > 4 || !core_trig_get(track, step) || !(tv = core_track_obj(track)))
        return -1;
    v.begin = notes;
    v.end = v.cap = notes + n;
    ((fw4)FW_TRIG_NOTES)(*(uint32_t *)(tv + 48), (uint32_t)track, (uint32_t)step, (uint32_t)&v);
    return 0;
}

/* One of the step's notes changed: NOTE (0-127), VEL (1-127) or LEN (the TRIG page's index), 0xff to clear.
 * which: 0 NOTE (first note only), 1 VEL, 2 LEN (all notes, as the TRIG page does). 0 or -1. */
int core_trig_lock(int track, int step, int which, int value)
{
    struct core_note n[4];
    int k, c = core_trig_notes(track, step, n, 4);
    if (c < 1 || which < 0 || which > 2 || value < 0 || value > 255)
        return -1;
    for (k = 0; k < c; k++) {
        if (which == 0 && k == 0)
            n[k].note = (uint8_t)value;
        else if (which == 1)
            n[k].vel = (uint8_t)value;
        else if (which == 2)
            n[k].len = (uint8_t)value;
    }
    return core_trig_set_notes(track, step, n, c);
}

/* A parameter lock: the value (0-0xffff, 8.8: the high byte is the value as a sound stores it) the step locks
 * the track's value index (0-70) to, or -1 */
int core_plock_get(int track, int step, int index)
{
    const uint8_t *pat = PATTERN;
    int slot;
    uint16_t v;
    if (!ok(track, step) || (unsigned)index > 70)
        return -1;
    slot = (int8_t)pat[PL_SLOTOF + 71 * track + index];
    if (slot < 0 || slot >= NSLOT)
        return -1;
    v = rd16(pat + PL_BASE + 258 * slot + 2 + 2 * step);
    return v == 0xffff ? -1 : v;
}

/* Lock a value index of the track to value (0-0x7fff in practice; 8.8) on a step with a trig, as holding the
 * trig and turning a knob does. 0 on success, -1 (no trig, no free slot of 80, out of range) */
int core_plock_set(int track, int step, int index, int value)
{
    uint8_t *tv;
    if (!core_trig_get(track, step) || (unsigned)index > 70 || value < 0 || value > 0xfffe
        || !(tv = core_track_obj(track)))
        return -1;
    return (((fw4)FW_PLOCK_SET)((uint32_t)tv, (uint32_t)step, (uint32_t)index, (uint32_t)value) & 0xff) ? 0 : -1;
}

/* Remove every parameter lock of a step. 0 or -1 */
int core_plock_clear(int track, int step)
{
    uint8_t *tv;
    if (!ok(track, step) || !(tv = core_track_obj(track)))
        return -1;
    ((fw2)FW_PLOCK_CLR)((uint32_t)tv, (uint32_t)step);
    return 0;
}

/* How many parameter locks a step has */
int core_plock_count(int track, int step)
{
    return ok(track, step) ? PATTERN[PL_COUNT + track * 128 + step] : 0;
}
