/* SPDX-License-Identifier: GPL-2.0-or-later */
/* core-dt2 2.7: the SDK alpha's device layer for the Digitakt II (OS 1.17): what the shared part (sdk_machine.c, a
 * copy of elekloader's mods/sdk-alpha/machine.c) needs of the firmware. A mod built by sdk_alpha_build contributes
 * each machine to the table sdk_alpha_machines; sdk.c makes each one a core machine at boot. */
#ifndef SDK_ALPHA_DEV_H
#define SDK_ALPHA_DEV_H

#include "sdk_machine.h"

#define SDK_ALPHA_MACHINES 16
#define dev_fillrect dt2_fillrect

extern void dt2_fillrect(void *bmp, int32_t x0, int32_t y0, int32_t x1, int32_t y1, int32_t on);
extern const struct elek_machine *const sdk_alpha_machines[];   /* the table, ending in 0 */

static inline int dev_candidate(uint32_t i, const struct elek_machine **m)
{
    *m = sdk_alpha_machines[i];
    return *m != 0;
}
#endif
