/*
 * Fuzz the stateless decoders applied to bytes received from a PLC: CIP/PCCC error-status decoding,
 * the PCCC data-type byte, and the CIP type-info lookups. The first input byte picks the decoder.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <libplctag/protocols/ab/tag.h>
#include <libplctag/protocols/ab/cip.h>
#include <libplctag/protocols/ab/error_codes.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    uint8_t *buf = NULL;
    int a = 0;
    int b = 0;

    if(size < 1) { return -1; }

    /* exact-size heap copy so ASan sees any read past the end of the response */
    buf = (uint8_t *)malloc(size - 1 ? size - 1 : 1);
    if(!buf) { abort(); }
    memcpy(buf, data + 1, size - 1);

    switch(data[0] % 6) {
        case 0: (void)decode_cip_error_short(buf, size - 1); break;
        case 1: (void)decode_cip_error_long(buf, size - 1); break;
        case 2: (void)decode_cip_error_code(buf, size - 1); break;
        case 3: (void)pccc_decode_error(buf, size - 1); break;
        case 4: (void)pccc_decode_dt_byte(buf, (int)(size - 1), &a, &b); break;
        default:
            if(size > 1) {
                (void)cip_lookup_encoded_type_size(buf[0], &a);
                (void)cip_lookup_data_element_size(buf[0], &b);
            }
            (void)pccc_calculate_bcc(buf, (int)(size - 1));
            (void)pccc_calculate_crc16(buf, (int)(size - 1));
            break;
    }

    free(buf);
    return 0;
}
