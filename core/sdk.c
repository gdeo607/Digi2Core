/* SPDX-License-Identifier: GPL-2.0-or-later */
/* core-dt2 2.7: the SDK alpha's machines (elekloader/sdk_alpha_machine.h) on the Digitakt II, UI side.
 *
 * A mod built by sdk_alpha_build contributes each machine to the table sdk_alpha_machines. At boot (before the
 * machine and parameter tables are built) core makes each one a core machine (struct core_machine_dt2): its id is
 * its type (7-23), a clone of MANUAL SLICE as STRING is, listed at the end of the machine list, with its pages as
 * SRC page 1 and 2.
 *
 * A synth machine keeps its values in twelve places of a sound, the slots of core_params (params.s): SRC page 1
 * A-H (value index 25-28, 31-34) and page 2's four (29, 30, 69, 70). Each knob takes one slot, which saves, locks
 * and is an LFO destination as any of them: a knob on page 1 encoder e the slot e, then page 2's knobs and the
 * knobs on no page the free slots, page 2's first. Every SDK machine shares the twelve parameter codes
 * SDK_CODE + slot: their names and value texts are the active track's machine's, as .present last left them.
 *
 * Not yet: the encoder of a hidden knob still edits it, the sound (render), mono machines and MIDI CCs. */
#include "dev.h"

#define SDK_CODE 327                    /* codes 327-338: slot s is SDK_CODE + s */
#define SLOTS 12
#define TEMPLATE 0xfe                   /* the LEV row: a plain 0..127 knob */
#define CLONE_SLICE 6
#define F_ONEPAGE 1
#define F_PAGE2 4
#define F_OWN_H 8                       /* knob H (value 34) is the machine's: halfword 12, not the level */
#define F_OWN_28 16                     /* values 28-30, 69, 70 are the machine's without a page 2 (core 2.7) */
#define F_HIDDEN 32                     /* f3: codes on no page (core 2.7) */

/* The firmware (OS 1.17). */
typedef void (*rect_fn)(void *bmp, int x0, int y0, int x1, int y1, int colour);
typedef void (*knob_fn)(void *, void *, int, int, int, int, int, int, int, int, int);
#define FILLRECT   ((rect_fn)0x401131aeu)
#define KNOB_STOCK ((knob_fn)0x40069b8eu)
#define KIT        (*(uint8_t *const volatile *)0x43165028u)    /* the active kit: sound t at +0x34 + 0x450 t */
#define UI_TRACK   (*(volatile uint8_t *)0x42936825u)           /* the active track */
#define SOUND(t)   (KIT + 0x34 + 0x450 * (t))                    /* the kit's sound t: values at +0x14, 8.8 */
#define SOUND_TYPE 0xa2                                         /* a sound's machine type (byte) */

static int32_t type_of(uint32_t t)
{
    return KIT ? (int8_t)SOUND(t)[SOUND_TYPE] : -1;
}

/* core's (machines.s, params.s) */
struct core_machine_dt2 {
    int32_t type, clone_of, position, flags;
    int32_t f[9];                       /* A-H, then the level (10) */
    const char *name, *short_name;
    int32_t f2[8];                      /* SRC page 2's A-H */
    int32_t f3[4];                      /* core 2.7, flag bit 5: codes on no page */
};
struct core_param_dt2 {
    int32_t code;
    const char *name, *short_name;
    int32_t template_code, slot, min, max, def;
    void (*formatter)(int32_t raw, char *buf);
    int32_t randomize;
};
extern int32_t mo_alt;                  /* machines.s: (type << 8 | track) + 1 while SRC page 2 is shown */

const char sdk_alpha_abi_v1[] = "sdk alpha 1";

static const uint8_t slot_value[SLOTS] = { 25, 26, 27, 28, 31, 32, 33, 34, 29, 30, 69, 70 };

static struct core_machine_dt2 descs[SDK_ALPHA_MACHINES];
const struct core_machine_dt2 *core_sdk_machines[SDK_ALPHA_MACHINES + 1];   /* machines.s walks it after core_machines */
static struct core_param_dt2 params[SLOTS];
const struct core_param_dt2 *core_sdk_params[SLOTS + 1];   /* params.s walks it after core_params */
static int8_t slot_of[SDK_ALPHA_MACHINES][SDK_ALPHA_KNOBS];  /* knob -> slot, -1 none */
static int8_t knob_at[SDK_ALPHA_MACHINES][SLOTS];            /* slot -> knob, -1 none */
static char names[SLOTS][ELEK_UI_LABEL_MAX + 1];             /* each shared code's name: the active machine's */

void dt2_fillrect(void *bmp, int32_t x0, int32_t y0, int32_t x1, int32_t y1, int32_t on)
{
    FILLRECT(bmp, x0, y0, x1, y1, on);
}

static void take(int32_t i, int32_t k, int32_t s)
{
    if (k >= 0 && slot_of[i][k] < 0 && knob_at[i][s] < 0) {
        slot_of[i][k] = (int8_t)s;
        knob_at[i][s] = (int8_t)k;
    }
}

static void take_free(int32_t i, int32_t k)
{
    static const uint8_t order[SLOTS] = { 8, 9, 10, 11, 0, 1, 2, 3, 4, 5, 6, 7 };
    for (int32_t n = 0; k >= 0 && slot_of[i][k] < 0 && n < SLOTS; ++n)
        take(i, k, order[n]);
}

static void put_number(char *buf, int32_t v)
{
    sdk_alpha_number(v, buf, 0);
}

/* The value text of slot s, for the active track's machine (another machine's code shows its number). */
static void slot_text(uint32_t s, int32_t raw, char *buf)
{
    uint32_t t = UI_TRACK;
    const struct sdk_alpha_entry *e = t < 16 ? sdk_alpha_find(type_of(t)) : 0;
    int32_t i = e ? e - sdk_alpha_entries : -1;
    if (i >= 0 && knob_at[i][s] >= 0)
        sdk_alpha_value(e, (uint32_t)knob_at[i][s], raw, buf, 0);
    else
        put_number(buf, raw >> 8);
}
#define SLOT_TEXT(s) static void slot_text##s(int32_t raw, char *buf) { slot_text(s, raw, buf); }
SLOT_TEXT(0) SLOT_TEXT(1) SLOT_TEXT(2) SLOT_TEXT(3) SLOT_TEXT(4) SLOT_TEXT(5)
SLOT_TEXT(6) SLOT_TEXT(7) SLOT_TEXT(8) SLOT_TEXT(9) SLOT_TEXT(10) SLOT_TEXT(11)
static void (*const slot_texts[SLOTS])(int32_t, char *) = {
    slot_text0, slot_text1, slot_text2, slot_text3, slot_text4, slot_text5,
    slot_text6, slot_text7, slot_text8, slot_text9, slot_text10, slot_text11,
};

static int32_t code_of(int32_t i, int32_t page, int32_t encoder)
{
    int32_t k = sdk_alpha_entries[i].encoder[page][encoder];
    return k >= 0 && slot_of[i][k] >= 0 ? SDK_CODE + slot_of[i][k] : 0;
}

/* core_boot_init, before core_machines_boot and core_params_boot. */
void core_sdk_boot(void)
{
    int32_t n = 0;
    sdk_alpha_init();
    for (int32_t i = 0; i < sdk_alpha_count; ++i) {
        const struct sdk_alpha_entry *e = &sdk_alpha_entries[i];
        const struct elek_machine *m = e->machine;
        struct core_machine_dt2 *d = &descs[n];
        if (m->id < 7 || m->id > 23 || e->count > SLOTS)
            continue;                   /* the builder refuses these */
        for (int32_t k = 0; k < SDK_ALPHA_KNOBS; ++k)
            slot_of[i][k] = -1;
        for (int32_t s = 0; s < SLOTS; ++s)
            knob_at[i][s] = -1;
        for (int32_t enc = 0; enc < 8; ++enc)
            take(i, e->encoder[0][enc], enc);
        for (int32_t enc = 0; enc < 8; ++enc)
            take_free(i, e->encoder[1][enc]);
        for (int32_t k = 0; k < (int32_t)e->count; ++k)
            take_free(i, k);
        d->type = m->id;
        d->clone_of = CLONE_SLICE;
        d->position = 255;
        d->flags = F_OWN_H | F_OWN_28 | F_HIDDEN | (e->pages > 1 ? F_PAGE2 : F_ONEPAGE);
        for (int32_t enc = 0; enc < 8; ++enc) {
            d->f[enc] = code_of(i, 0, enc);
            d->f2[enc] = e->pages > 1 ? code_of(i, 1, enc) : 0;
        }
        d->f[8] = 10;
        int32_t h = 0;                  /* the knobs no page shows: their codes in f3 */
        for (int32_t k = 0; k < (int32_t)e->count; ++k) {
            int32_t shown = 0;
            for (int32_t page = 0; page < (int32_t)e->pages; ++page)
                for (int32_t enc = 0; enc < 8; ++enc)
                    shown |= e->encoder[page][enc] == k;
            if (!shown && slot_of[i][k] >= 0 && h < 4)
                d->f3[h++] = SDK_CODE + slot_of[i][k];
        }
        d->name = m->name;
        d->short_name = m->short_name;
        core_sdk_machines[n++] = d;
    }
    core_sdk_machines[n] = 0;
    for (int32_t s = 0; s < SLOTS; ++s) {
        struct core_param_dt2 *p = &params[s];
        names[s][0] = '-';
        p->code = SDK_CODE + s;
        p->name = p->short_name = names[s];
        p->template_code = TEMPLATE;
        p->slot = s;
        p->min = 0;
        p->max = SDK_ALPHA_RAW_MAX;
        p->def = 0;
        p->formatter = slot_texts[s];
        p->randomize = 1;
        core_sdk_params[s] = n ? p : 0;     /* no SDK machine: the codes stay gaps */
    }
    core_sdk_params[SLOTS] = 0;
}

/* The parameter list the firmware walks for a machine (machine select's defaults, randomize, the LFO's
 * destinations: storage.s's st_list_end, before its first value): the shared codes take this machine's knob
 * defaults, so selecting it starts each knob at its def. */
extern uint8_t pf_table[];              /* params.s: 60-byte rows by code; the default at +0x10 */
void core_sdk_defaults(int32_t type)
{
    const struct sdk_alpha_entry *e = sdk_alpha_find(type);
    if (!e)
        return;
    int32_t i = e - sdk_alpha_entries;
    for (int32_t s = 0; s < SLOTS; ++s) {
        int32_t k = knob_at[i][s];
        *(int32_t *)(pf_table + 60 * (SDK_CODE + s) + 0x10) = k >= 0 ? sdk_alpha_default(&e->machine->knobs[k]) : 0;
    }
}

/* The SRC page, as the knob drawer saw it: set while it draws, counted down by the tick. */
static volatile uint8_t src_drawn;

/* ev_tick: .present with the active track's values when its machine is an SDK one; the shared codes' names follow
 * it, and the frame is recomposed when a label, visibility or glyph changed. */
void core_sdk_tick(uint8_t *ctrl)
{
    uint32_t t = UI_TRACK;
    const uint8_t *kit = KIT;
    if (sdk_alpha_count <= 0 || t >= 16 || !kit)
        return;
    int32_t type = type_of(t);
    const struct sdk_alpha_entry *e = sdk_alpha_find(type);
    if (!e) {
        sdk_alpha_seen = 0;
        return;
    }
    int32_t i = e - sdk_alpha_entries, raw[SDK_ALPHA_KNOBS];
    const uint8_t *sound = SOUND(t) + 0x14;
    for (uint32_t k = 0; k < e->count; ++k)
        raw[k] = slot_of[i][k] >= 0 ? *(const uint16_t *)(sound + 2 * slot_value[(int)slot_of[i][k]]) : 0;
    int32_t page = ELEK_UI_NO_PAGE;
    if (src_drawn) {
        --src_drawn;
        page = e->pages > 1 && mo_alt == ((type << 8) | (int32_t)t) + 1 ? 1 : 0;
    }
    const struct sdk_alpha_entry *before = sdk_alpha_seen;
    int32_t changed = sdk_alpha_present(e, t, page, raw, 0);
    if (changed || before != e) {
        for (int32_t s = 0; s < SLOTS; ++s) {
            int32_t k = knob_at[i][s];
            const char *label = k < 0 ? "-" : sdk_alpha_visible(e, k) ? sdk_alpha_label(e, k) : " ";
            int32_t c = 0;
            while (c < ELEK_UI_LABEL_MAX && label[c]) {
                names[s][c] = label[c];
                ++c;
            }
            names[s][c] = 0;
        }
        ctrl[0x20] = 1;
    }
}

/* The SRC page's knob widget for the shared codes (core_knobs): nothing for a hidden knob, the stock widget
 * otherwise, with the knob's glyph over it. */
void core_sdk_knob(void *view, void *bmp, int x, int y, int code, int value, int a6, int a7, int a8, int a9, int a10)
{
    uint32_t t = UI_TRACK;
    const struct sdk_alpha_entry *e = t < 16 ? sdk_alpha_find(type_of(t)) : 0;
    int32_t s = code - SDK_CODE, k = -1;
    src_drawn = 2;
    if (e && s >= 0 && s < SLOTS)
        k = knob_at[e - sdk_alpha_entries][s];
    if (k >= 0 && !sdk_alpha_visible(e, k))
        return;
    KNOB_STOCK(view, bmp, x, y, code, value, a6, a7, a8, a9, a10);
    const struct elek_glyph *glyph = k >= 0 ? sdk_alpha_glyph(e, k) : 0;
    if (glyph && x >= 3 && x + 21 <= 127 && y >= 0 && y + 24 <= 63) {
        FILLRECT(bmp, x - 3, y + 7, x + 21, y + 24, 0);
        sdk_alpha_blit(bmp, x + 1, y + 7, glyph);
    }
}
