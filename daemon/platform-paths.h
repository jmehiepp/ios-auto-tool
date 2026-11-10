#pragma once
#ifdef IOSAT_ROOTHIDE
#include <roothide.h>
#define IAT_PATH(value) jbroot(value)
#else
#define IAT_PATH(value) (value)
#endif
