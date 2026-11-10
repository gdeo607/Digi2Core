/* SPDX-License-Identifier: AGPL-3.0-or-later */
/* core-dt2 2.7: the SDK machines' voices on the DSP (compiled by Selache's selcc through DigiKit's pk_build).
 *
 * Each SDK machine's mod carries a stub the SDK builder writes (its dsp-inline voice routine, registered in
 * core_dsp_voices for the machine's type) and its render, in SHARC assembly as on the Digitone II (elekloader's
 * docs/SDK.md, "render on the Digitone II"). The stub calls core's _sk_enter (sdk_dsp.s), which calls sdk_dsp_voice
 * for the voice on core's C stack, then the machine's render with R4 = the voice and R8 = its 32 floats, then
 * _sk_leave. As machines-dn2's dispatcher: a note-on's own block is silent and the next one has start set; idle is
 * always 0; cc is every CC -1 (MIDI CCs do not reach the DSP yet). sdk_dsp_voice reads the voice's controls
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
/* sdk_dsp.s's (reserved, not loaded) */
extern uint32_t sdk_dsp_state[];            /* VOICES * STATE_WORDS */

static const uint8_t slot_hw[SLOTS] = { 0, 1, 2, 13, 6, 7, 8, 12, 14, 15, 10, 11 };

static int32_t voice_id[VOICES];
static int32_t voice_trig[VOICES], voice_start[VOICES];   /* (words: selcc's byte arrays are not trusted here) */
static int32_t knob[SLOTS];
static struct elek_voice ev;
static int32_t cc_none[128];             /* every CC -1: none came (MIDI CCs do not reach the DSP yet) */
static int32_t cc_ready;

static uint32_t frame_hw(uint32_t k)
{
    uint32_t w = fw_frame[k >> 1];
    return (k & 1 ? w >> 16 : w) & 0xffff;
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
        cc_ready = 1;
    }
    if (voice_id[v] != m->id) {
        for (int i = 0; i < STATE_WORDS; ++i)
            state[i] = 0;
        voice_id[v] = m->id;
        voice_start[v] = 0;
    }
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
    ev.pitch = (int32_t)(frame_hw(1 + (uint32_t)t) << 8);
    ev.velocity = velocity < 1 ? 1 : velocity > 127 ? 127 : velocity;
    ev.state = state;
    ev.idle = 0;
    ev.cc = cc_none;
    return &ev;
}
