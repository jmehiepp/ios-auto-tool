#pragma once
#include <stdbool.h>
#include "../../deps/mongoose.h"
bool iat_request_authorized(struct mg_http_message *hm);
bool iat_same_origin(struct mg_http_message *hm);
bool iat_handle_session(struct mg_connection *c, struct mg_http_message *hm);
