#pragma once
#ifdef IOSAT_ROOTHIDE
#include <roothide.h>
#define IAT_PATH(value) jbroot(value)
#define IAT_BOOTSTRAP_PATH(value) jbroot(value)
#else
#define IAT_PATH(value) (value)
#ifdef IOSAT_ROOTLESS
#define IAT_BOOTSTRAP_PATH(value) "/var/jb" value
#else
#define IAT_BOOTSTRAP_PATH(value) (value)
#endif
#endif
