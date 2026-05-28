#pragma once
#import "../../deps/mongoose.h"

// Dispatch all /api/* routes. scripts_dir: base directory for .lua files.
void api_handle(struct mg_connection *c, struct mg_http_message *hm,
                const char *scripts_dir);
