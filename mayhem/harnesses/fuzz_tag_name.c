/*
 * Fuzz the tag-name checkers that plc_tag_create() runs before any network I/O: CIP symbolic names
 * (ControlLogix, Micro800) and PCCC logical addresses (PLC/5, SLC, MicroLogix, LGX-PCCC).
 * The first input byte picks the PLC family, the rest is the tag name.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <libplctag/protocols/ab/tag.h>

static const plc_type_t PLC_TYPES[] = {AB_PLC_PLC5,    AB_PLC_SLC,       AB_PLC_MLGX,
                                       AB_PLC_LGX,     AB_PLC_LGX_PCCC,  AB_PLC_MICRO800};

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    struct ab_tag_t *tag = NULL;
    char *name = NULL;

    if(size < 1) { return -1; }

    tag = (struct ab_tag_t *)calloc(1, sizeof(*tag));
    name = (char *)malloc(size);
    if(!tag || !name) { abort(); }

    tag->plc_type = PLC_TYPES[data[0] % (sizeof(PLC_TYPES) / sizeof(PLC_TYPES[0]))];

    memcpy(name, data + 1, size - 1);
    name[size - 1] = '\0';

    (void)check_tag_name(tag, name);

    free(name);
    free(tag);
    return 0;
}
