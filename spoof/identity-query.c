#include "identity-query.h"
#include <errno.h>
#include <string.h>
int iat_identity_string_read(const char *replacement, void *output, size_t *size) {
    if (!replacement || !size) { errno=EINVAL; return -1; }
    size_t required=strlen(replacement)+1, available=*size;
    *size=required;
    if (!output) return 0;
    if (available<required) { errno=ENOMEM; return -1; }
    memcpy(output,replacement,required); return 0;
}
