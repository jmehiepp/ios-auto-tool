#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
// sysctl read contract for an explicitly configured NUL-terminated string.
int iat_identity_string_read(const char *replacement, void *output, size_t *size);
#ifdef __cplusplus
}
#endif
