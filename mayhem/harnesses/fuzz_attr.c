/* Fuzz the "key=value&key=value" attribute-string parser behind plc_tag_create(). */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <utils/attr.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    char *str = (char *)malloc(size + 1);
    attr attrs = NULL;

    if(!str) { return 0; }
    memcpy(str, data, size);
    str[size] = '\0';

    attrs = attr_create_from_str(str);
    if(attrs) {
        static const char *const names[] = {"protocol", "gateway", "path", "plc", "cpu", "name", "elem_count", "elem_size",
                                            "debug", "read_cache_ms", "use_connected_msg", "allow_packing", "str_max_capacity"};
        size_t i;

        for(i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
            (void)attr_get_str(attrs, names[i], "");
            (void)attr_get_int(attrs, names[i], 0);
            (void)attr_get_float(attrs, names[i], 0.0f);
        }

        (void)attr_remove(attrs, "name");
        attr_destroy(attrs);
    }

    free(str);
    return 0;
}
