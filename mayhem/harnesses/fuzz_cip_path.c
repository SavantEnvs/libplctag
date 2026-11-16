/* Fuzz the CIP routing-path encoder (the `path=` attribute: "1,0", IP segments, DH+ addresses). */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <libplctag/protocols/ab/tag.h>
#include <libplctag/protocols/ab/cip.h>

static const plc_type_t PLC_TYPES[] = {AB_PLC_PLC5,    AB_PLC_SLC,       AB_PLC_MLGX,
                                       AB_PLC_LGX,     AB_PLC_LGX_PCCC,  AB_PLC_MICRO800};

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    uint8_t conn_path[MAX_CONN_PATH + MAX_IP_ADDR_SEG_LEN];
    int conn_path_size = (int)sizeof(conn_path);
    int needs_connection = 0;
    int is_dhp = 0;
    uint16_t dhp_dest = 0;
    char *path = NULL;
    plc_type_t plc_type;

    if(size < 1) { return -1; }

    /* Precondition from session.c:791: the library rejects any path string of MAX_CONN_PATH or more bytes before
     * encoding, because cip_encode_path() only bounds its output per segment. The string here is size-1 bytes. */
    if(size > MAX_CONN_PATH) { return -1; }

    plc_type = PLC_TYPES[data[0] % (sizeof(PLC_TYPES) / sizeof(PLC_TYPES[0]))];

    path = (char *)malloc(size);
    if(!path) { abort(); }
    memcpy(path, data + 1, size - 1);
    path[size - 1] = '\0';

    (void)cip_encode_path(path, &needs_connection, plc_type, conn_path, &conn_path_size, &is_dhp, &dhp_dest);

    free(path);
    return 0;
}
