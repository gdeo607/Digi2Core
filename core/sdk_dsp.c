/* SPDX-License-Identifier: AGPL-3.0-or-later */
/* core-dt2 2.7: the SDK machines' voices on the DSP (compiled by Selache's selcc through DigiKit's pk_build).
 *
 * Each SDK machine's mod carries a stub the SDK builder writes (its dsp-inline voice routine, registered in
 * core_dsp_voices for the machine's type) and its render, in SHARC assembly as on the Digitone II (elekloader's
 * docs/SDK.md, "render on the Digitone II"). The stub calls core's _sk_enter (sdk_dsp.s), which calls sdk_dsp_voice
 * for the voice on core's C stack, then the machine's render with R4 = the voice and R8 = its 32 floats, then
 * _sk_leave. As machines-dn2's dispatcher: a note-on's own block is silent and the next one has start set; idle is
 * always 0. cc holds the CCs of the voice's track since its last render, as elekloader's mods/sdk-alpha/machine.c
 * keeps them: the ColdFire (sdk.c core_sdk_cc) posts each CC in a mailbox in the frame's tail, which mb_poll reads
 * in the DSPI landing rings, with each track's legato bend (a mono machine's) after it. sdk_dsp_voice reads the voice's controls
 * from the DSP's copy of the frame, as core's frame builder leaves them (machines.s: slots 0-11 of core_params at
 * halfwords 0-2, 13, 6-8, 12, 14, 15, 10, 11 of the track's block), maps each knob as the ColdFire's sdk_alpha_map
 * does, and keeps each voice's 256 bytes of state. */
#include <stdint.h>

#define VOICES 32
#define FRAMES 32
#define SLOTS 12
#define STATE_WORDS 64                  /* ELEK_VOICE_STATE_MAX / 4 */
#define RAW_MAX (127 << 8)

/* sdk_alpha_machine.h's struct elek_voice (the same layout under selcc: eight words). */
struct elek_voice {
    const int32_t *knob;
    uint32_t track, start;
    int32_t pitch, velocity;
    void *state;
    uint32_t idle;
    const int32_t *cc;
};

/* What a machine's stub gives (the SDK builder writes it): its id, its knob count, and each knob's slot and
 * range. */
struct sdk_dsp_machine {
    int32_t id, count;
    int32_t slot[SLOTS], min[SLOTS], max[SLOTS];
};

/* The firmware's (core's sharc_raw externs: DigiKit's 1.17 anchors, as dsp-inline's). Byte addresses. */
extern volatile uint32_t fw_frame[];        /* the frame copy: halfword k in word k / 2, odd k the high half */
extern volatile uint32_t fw_trig_latch[];   /* a byte a voice: non-zero in the blocks of a note-on */
extern volatile uint8_t fw_records[];       /* voice v's record at + 0x1d8 v; its ACTIVE byte at +0x1b8 */
extern volatile uint32_t fw_rx0[], fw_rx1[]; /* the DSPI transfer's two landing rings, 2748 bytes: the frame with its tail */
extern volatile uint32_t fw_type_cache[];   /* track t's machine type: halfword t */
/* sdk_dsp.s's (reserved, not loaded) */
extern uint32_t sdk_dsp_state[];            /* VOICES * STATE_WORDS */
extern uint32_t sdk_dsp_cc[];               /* 16 * 128: each track's CCs (cleared at the first call) */
#define cc_table sdk_dsp_cc

static const uint8_t slot_hw[SLOTS] = { 0, 1, 2, 13, 6, 7, 8, 12, 14, 15, 10, 11 };

static int32_t voice_id[VOICES];
static int32_t voice_trig[VOICES], voice_start[VOICES];   /* (words: selcc's byte arrays are not trusted here) */
static int32_t knob[SLOTS];
static struct elek_voice ev;
static int32_t cc_none[128];             /* every CC -1: none came */
static int32_t cc_ready;

/* The CC mailbox (sdk.c): halfword MB_AT of the frame is the newest CC's number n, then MB_N entries newest first
 * (track << 8 | cc, value), then n again. */
#define MB_AT 1200
#define MB_N 16
#define MB_BEND (MB_AT + 2 + 2 * MB_N)      /* each track's legato bend (a mono machine's), 1/256 semitone, signed */
#define CC_COUNT 0x1ffffff                  /* cc_count's mask, 25 bits */
static uint32_t mb_last;                    /* the number of the last CC taken */
static uint32_t mb_buf[2 * MB_N];
/* As machine.c: each track's CCs (the value, with cc_count when it came, bits 7 up; 0 none), the count, each
 * track's machine at its last CC with cc_count before its first CC on it (count << 7 | type), and each voice's
 * cc_count at its last render. */
static uint32_t cc_count;
static uint32_t cc_took[16];
static uint32_t voice_seen[VOICES], voice_rendered[VOICES];
static int32_t cc_built[128];
static int32_t built_track = -1;
static uint32_t built_from, built_now;

static uint32_t frame_hw(uint32_t k)
{
    uint32_t w = fw_frame[k >> 1];
    return (k & 1 ? w >> 16 : w) & 0xffff;
}

static uint32_t ring_hw(volatile uint32_t *ring, uint32_t k)
{
    uint32_t w = ring[k >> 1];
    return (k & 1 ? w >> 16 : w) & 0xffff;
}

/* One ring's mailbox into mb_buf: its number, or -1 when the frame caught a write half done (or the DMA is
 * landing a frame over it). The transfer lands from halfword 0 up: read the last number first and the first one
 * last, so equal numbers mean the entries between are of one frame. */
static int32_t mb_read(volatile uint32_t *ring)
{
    uint32_t tail = ring_hw(ring, MB_AT + 1 + 2 * MB_N);
    for (int i = 0; i < 2 * MB_N; ++i)
        mb_buf[i] = ring_hw(ring, MB_AT + 1 + (uint32_t)i);
    uint32_t head = ring_hw(ring, MB_AT);
    if (head != tail)
        return -1;
    return (int32_t)head;
}

static void cc_take(uint32_t track, uint32_t cc, uint32_t value)
{
    uint32_t n = cc_count % CC_COUNT + 1;
    uint32_t w = fw_type_cache[track >> 1];
    uint32_t id = (track & 1 ? w >> 16 : w) & 127;
    if ((cc_took[track] & 127) != id)
        cc_took[track] = cc_count << 7 | id;
    cc_table[128 * track + cc] = n << 7 | (value & 127);
    cc_count = n;
}

/* The CCs posted since the last poll: the newer of the two rings' mailboxes, oldest entry first. */
static void mb_poll(void)
{
    if (ring_hw(fw_rx0, MB_AT) == mb_last && ring_hw(fw_rx1, MB_AT) == mb_last)
        return;
    for (int r = 0; r < 2; ++r) {
        int32_t n = mb_read(r ? fw_rx1 : fw_rx0);
        if (n < 0)
            continue;
        uint32_t fresh = ((uint32_t)n - mb_last) & 0xffff;
        if (fresh == 0 || fresh >= 0x8000)
            continue;                   /* nothing new, or the older ring */
        if (fresh > MB_N)
            fresh = MB_N;               /* more came between two polls than the mailbox holds: the newest */
        for (int j = (int)fresh - 1; j >= 0; --j) {
            uint32_t at = mb_buf[2 * j], value = mb_buf[2 * j + 1];
            uint32_t track = at >> 8;
            if (track < 16 && value < 128)
                cc_take(track, at & 127, value);
        }
        mb_last = (uint32_t)n;
    }
}

static uint32_t latch_byte(volatile uint32_t *latch, uint32_t v)
{
    return (latch[v >> 2] >> (8 * (v & 3))) & 0xff;
}

/* sdk_alpha_map, as on the ColdFire (split so no 64-bit product is needed). */
static int32_t map(int32_t min, int32_t max, int32_t raw)
{
    uint32_t span = (uint32_t)max - (uint32_t)min;
    if (raw < 0) raw = 0;
    if (raw > RAW_MAX) raw = RAW_MAX;
    uint32_t offset = (span / RAW_MAX) * (uint32_t)raw +
        ((span % RAW_MAX) * (uint32_t)raw + RAW_MAX / 2) / RAW_MAX;
    return (int32_t)((uint32_t)min + offset);
}

/* Voice v (0-31) of track t, which plays machine m: the voice to render into out, or 0 when it is silent (a
 * note-on's own block, or its AMP has ended), with out zeroed. A voice whose machine changed starts from zeroed
 * state. */
struct elek_voice *sdk_dsp_voice(int32_t v, int32_t t, const struct sdk_dsp_machine *m, float *out)
{
    uint32_t *state = sdk_dsp_state + STATE_WORDS * (uint32_t)v;
    if (!cc_ready) {
        for (int i = 0; i < 128; ++i)
            cc_none[i] = -1;
        for (int i = 0; i < 16 * 128; ++i)
            cc_table[i] = 0;
        cc_ready = 1;
    }
    if (voice_id[v] != m->id) {
        for (int i = 0; i < STATE_WORDS; ++i)
            state[i] = 0;
        voice_id[v] = m->id;
        voice_start[v] = 0;
        voice_rendered[v] = 0;
    }
    mb_poll();
    uint32_t trig = latch_byte(fw_trig_latch, (uint32_t)v) != 0;
    int32_t onset = 0;
    if (trig && voice_trig[v] == 0)
        onset = 1;
    voice_trig[v] = (int32_t)trig;
    uint32_t start = 0;
    if (voice_start[v]) {
        start = 1;
        voice_start[v] = 0;
    }
    uint32_t active = fw_records[0x1d8 * v + 0x1b8];
    if (onset || (!active && !start)) {
        if (onset)
            voice_start[v] = 1;         /* the next block starts the note */
        for (int i = 0; i < FRAMES; ++i)
            out[i] = 0.0f;
        return 0;
    }
    uint32_t block = 0x6d + 0x30 * (uint32_t)t;
    int32_t count = m->count < SLOTS ? m->count : SLOTS;
    for (int k = 0; k < count; ++k)
        knob[k] = map(m->min[k], m->max[k], (int32_t)frame_hw(block + slot_hw[m->slot[k]]));
    int32_t velocity = (int32_t)(frame_hw(0x1a + (uint32_t)t) >> 8);
    ev.knob = knob;
    ev.track = (uint32_t)t;
    ev.start = start;
    int32_t bend = (int32_t)(ring_hw(fw_rx0, MB_BEND + (uint32_t)t) ^ 0x8000) - 0x8000;
    ev.pitch = (int32_t)(frame_hw(1 + (uint32_t)t) << 8) + bend * 256;
    ev.velocity = velocity < 1 ? 1 : velocity > 127 ? 127 : velocity;
    ev.state = state;
    ev.idle = 0;
    /* the CCs since this voice's last render (its first on the machine: since its track took the machine) */
    uint32_t now = cc_count, from = voice_seen[v];
    if (!voice_rendered[v]) {
        uint32_t took = cc_took[t];
        uint32_t since = (int32_t)(took & 127) == m->id ? took >> 7 : now;
        if (((from - since) & CC_COUNT) > ((now - since) & CC_COUNT))
            from = since;
    }
    uint32_t span = (now - from) & CC_COUNT;
    ev.cc = cc_none;
    if (span) {
        if (built_track != t || built_from != from || built_now != now) {
            for (int n = 0; n < 128; ++n) {
                uint32_t word = cc_table[128 * (uint32_t)t + (uint32_t)n];
                int32_t value = -1;
                if (word >> 7) {
                    if ((((word >> 7) - from - 1) & CC_COUNT) < span)
                        value = (int32_t)(word & 127);
                }
                cc_built[n] = value;
            }
            built_track = t;
            built_from = from;
            built_now = now;
        }
        ev.cc = cc_built;
    }
    voice_seen[v] = now;
    voice_rendered[v] = 1;
    return &ev;
}
