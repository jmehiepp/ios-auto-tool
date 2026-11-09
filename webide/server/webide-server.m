#import "webide-server.h"
#import "api-handler.h"
#import "access-control.h"
#import "../../daemon/logger.h"
#import "../../engine/screen/screenshot.h"
#include <pthread.h>

#define MAX_WS_CLIENTS 16
static struct mg_mgr manager;
static const char *web_root, *scripts_directory;
static struct mg_connection *log_clients[MAX_WS_CLIENTS];
static NSMutableArray<NSData *> *pending_logs;
static pthread_mutex_t log_lock = PTHREAD_MUTEX_INITIALIZER;

void webide_ws_broadcast_log(const char *level, const char *message) {
    if (!level || !message) return;
    @autoreleasepool {
        NSString *text = [[NSString alloc] initWithBytes:message length:strlen(message) encoding:NSUTF8StringEncoding] ?: @"[invalid UTF-8 log]";
        NSData *data = [NSJSONSerialization dataWithJSONObject:
            @{@"level": @(level), @"data": text} options:0 error:nil];
        if (!data) return;
        pthread_mutex_lock(&log_lock);
        if (!pending_logs) pending_logs = [NSMutableArray array];
        if (pending_logs.count >= 500) [pending_logs removeObjectAtIndex:0];
        [pending_logs addObject:data];
        pthread_mutex_unlock(&log_lock);
    }
}
static void flush_logs(void) {
    pthread_mutex_lock(&log_lock);
    NSArray *batch = [pending_logs copy];
    [pending_logs removeAllObjects];
    pthread_mutex_unlock(&log_lock);
    for (NSData *data in batch) for (int i = 0; i < MAX_WS_CLIENTS; i++) {
        struct mg_connection *client = log_clients[i];
        if (client && client->send.len < 1024 * 1024)
            mg_ws_send(client, data.bytes, data.length, WEBSOCKET_OP_TEXT);
    }
}
static void stream_frame(struct mg_connection *c) {
    uint64_t previous = 0, now = mg_millis();
    memcpy(&previous, c->data + 8, sizeof(previous));
    if (now - previous < 250 || c->send.len > 1024 * 1024) return;
    memcpy(c->data + 8, &now, sizeof(now));
    UIImage *image = capture_screen(CGRectZero);
    if (!image) { c->is_closing = 1; return; }
    NSData *jpeg = UIImageJPEGRepresentation(image, 0.5);
    if (!jpeg || jpeg.length > 4 * 1024 * 1024) { c->is_closing = 1; return; }
    mg_printf(c, "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %lu\r\n\r\n", (unsigned long)jpeg.length);
    mg_send(c, jpeg.bytes, jpeg.length);
    mg_send(c, "\r\n", 2);
}
static void handle_http(struct mg_connection *c, int event, void *event_data) {
    if (event == MG_EV_POLL && c->data[0] == 'S') { stream_frame(c); return; }
    if (event == MG_EV_CLOSE) {
        for (int i = 0; i < MAX_WS_CLIENTS; i++) if (log_clients[i] == c) log_clients[i] = NULL;
        return;
    }
    if (event != MG_EV_HTTP_MSG) return;
    struct mg_http_message *hm = event_data;
    if (iat_handle_session(c, hm)) return;
    if (mg_match(hm->uri, mg_str("/login"), NULL)) {
        NSString *path = [@(web_root) stringByAppendingPathComponent:@"login.html"];
        struct mg_http_serve_opts options = {.root_dir = web_root, .extra_headers = "Cache-Control: no-store\r\n"};
        mg_http_serve_file(c, hm, path.fileSystemRepresentation, &options);
        return;
    }
    if (!iat_request_authorized(hm)) {
        if (mg_match(hm->uri, mg_str("/"), NULL)) mg_http_reply(c, 302, "Location: /login\r\nCache-Control: no-store\r\n", "");
        else mg_http_reply(c, 401, "Content-Type: application/json\r\nCache-Control: no-store\r\n", "{\"error\":\"authentication required\"}");
        return;
    }
    if (mg_match(hm->uri, mg_str("/ws/logs"), NULL)) {
        for (int i = 0; i < MAX_WS_CLIENTS; i++) if (!log_clients[i]) {
            mg_ws_upgrade(c, hm, NULL); log_clients[i] = c; return;
        }
        mg_http_reply(c, 429, "", "Too many log viewers"); return;
    }
    if (mg_match(hm->uri, mg_str("/api/stream"), NULL)) {
        if (!mg_match(hm->method, mg_str("GET"), NULL)) { mg_http_reply(c, 405, "Allow: GET\r\n", ""); return; }
        int viewers = 0;
        for (struct mg_connection *it = manager.conns; it; it = it->next) if (it->data[0] == 'S') viewers++;
        if (viewers >= 4) { mg_http_reply(c, 429, "", "Too many stream viewers"); return; }
        mg_printf(c, "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n");
        c->data[0] = 'S'; c->is_resp = 1; return;
    }
    if (mg_match(hm->uri, mg_str("/api/#"), NULL)) { api_handle(c, hm, scripts_directory); return; }
    struct mg_http_serve_opts options = {.root_dir = web_root,
        .extra_headers = "X-Content-Type-Options: nosniff\r\nCache-Control: no-store\r\n"};
    mg_http_serve_dir(c, hm, &options);
}
static void *server_thread(void *argument) {
    for (;;) { @autoreleasepool { mg_mgr_poll(&manager, 50); flush_logs(); } }
    return NULL;
}
void webide_server_start(int port, const char *scripts_dir, const char *root) {
    scripts_directory = scripts_dir; web_root = root;
    mg_mgr_init(&manager);
    char address[64];
    snprintf(address, sizeof(address), "http://0.0.0.0:%d", port);
    if (!mg_http_listen(&manager, address, handle_http, NULL)) {
        log_error("Cannot listen on Web IDE port %d", port); exit(1);
    }
    pthread_t thread;
    if (pthread_create(&thread, NULL, server_thread, NULL) != 0) exit(1);
    pthread_detach(thread);
}
