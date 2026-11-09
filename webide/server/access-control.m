#import "access-control.h"
#import "../../daemon/runtime-paths.h"

static bool token_equals(struct mg_str supplied) {
    const char *expected = iat_access_token().UTF8String;
    if (!expected || supplied.len != 64) return false;
    unsigned char diff = 0;
    for (size_t i = 0; i < 64; i++) diff |= supplied.buf[i] ^ expected[i];
    return diff == 0;
}
bool iat_same_origin(struct mg_http_message *hm) {
    struct mg_str *origin = mg_http_get_header(hm, "Origin");
    struct mg_str *host = mg_http_get_header(hm, "Host");
    if (!origin) return true;
    if (!host) return false;
    NSString *text = [[NSString alloc] initWithBytes:origin->buf length:origin->len encoding:NSUTF8StringEncoding];
    NSString *authority = [[NSString alloc] initWithBytes:host->buf length:host->len encoding:NSUTF8StringEncoding];
    return [text isEqualToString:[@"http://" stringByAppendingString:authority]] ||
           [text isEqualToString:[@"https://" stringByAppendingString:authority]];
}
bool iat_request_authorized(struct mg_http_message *hm) {
    if (!iat_same_origin(hm)) return false;
    struct mg_str *auth = mg_http_get_header(hm, "Authorization");
    if (auth && auth->len > 7 && memcmp(auth->buf, "Bearer ", 7) == 0 &&
        token_equals(mg_str_n(auth->buf + 7, auth->len - 7))) return true;
    struct mg_str *cookie = mg_http_get_header(hm, "Cookie");
    return cookie && token_equals(mg_http_get_header_var(*cookie, mg_str("iat_session")));
}
bool iat_handle_session(struct mg_connection *c, struct mg_http_message *hm) {
    if (!mg_match(hm->uri, mg_str("/api/session"), NULL)) return false;
    if (!iat_same_origin(hm)) {
        mg_http_reply(c, 403, "Content-Type: application/json\r\n", "{\"error\":\"origin rejected\"}"); return true;
    }
    if (mg_match(hm->method, mg_str("POST"), NULL)) {
        char *value = mg_json_get_str(hm->body, "$.token");
        bool accepted = value && token_equals(mg_str(value));
        free(value);
        if (accepted) {
            NSString *header = [NSString stringWithFormat:
                @"Content-Type: application/json\r\nCache-Control: no-store\r\nSet-Cookie: iat_session=%@; Path=/; HttpOnly; SameSite=Strict\r\n", iat_access_token()];
            mg_http_reply(c, 200, header.UTF8String, "{\"ok\":true}");
        } else mg_http_reply(c, 401, "Content-Type: application/json\r\nCache-Control: no-store\r\n", "{\"error\":\"invalid access code\"}");
    } else if (mg_match(hm->method, mg_str("DELETE"), NULL)) {
        mg_http_reply(c, 200, "Set-Cookie: iat_session=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict\r\n", "{}");
    } else mg_http_reply(c, iat_request_authorized(hm) ? 200 : 401, "Content-Type: application/json\r\nCache-Control: no-store\r\n", "{}");
    return true;
}
