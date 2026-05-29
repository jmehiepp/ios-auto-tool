#pragma once
#import <Foundation/Foundation.h>
#import "../../deps/mongoose.h"

void claude_handle_chat(struct mg_connection *c, struct mg_http_message *hm);
