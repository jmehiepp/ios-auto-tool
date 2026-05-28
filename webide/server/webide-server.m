#import "webide-server.h"
#import "api-handler.h"
#import "../../deps/mongoose.h"
#import <pthread.h>
#import <string.h>
#import <stdlib.h>
#import <stdio.h>

#define MAX_WS_CLIENTS 16

static struct mg_mgr    s_mgr;
static const char      *s_web_root    = NULL;
static const char      *s_scripts_dir = NULL;
static struct mg_connection *s_ws_clients[MAX_WS_CLIENTS];
static pthread_mutex_t  s_ws_mutex = PTHREAD_MUTEX_INITIALIZER;

static void ws_add(struct mg_connection *c) {
    pthread_mutex_lock(&s_ws_mutex);
    for (int i = 0; i < MAX_WS_CLIENTS; i++) {
        if (!s_ws_clients[i]) { s_ws_clients[i] = c; break; }
    }
    pthread_mutex_unlock(&s_ws_mutex);
}

static void ws_remove(struct mg_connection *c) {
    pthread_mutex_lock(&s_ws_mutex);
    for (int i = 0; i < MAX_WS_CLIENTS; i++) {
        if (s_ws_clients[i] == c) { s_ws_clients[i] = NULL; break; }
    }
    pthread_mutex_unlock(&s_ws_mutex);
}

void webide_ws_broadcast_log(const char *level, const char *message) {
    if (!level || !message) return;

    // Build JSON: {"level":"INFO","data":"message text"}
    char buf[4096];
    snprintf(buf, sizeof(buf),
             "{\"level\":\"%s\",\"data\":\"%s\"}", level, message);

    pthread_mutex_lock(&s_ws_mutex);
    for (int i = 0; i < MAX_WS_CLIENTS; i++) {
        if (s_ws_clients[i]) {
            mg_ws_send(s_ws_clients[i], buf, strlen(buf), WEBSOCKET_OP_TEXT);
        }
    }
    pthread_mutex_unlock(&s_ws_mutex);
}

static void handle_http(struct mg_connection *c, int ev, void *ev_data) {
    if (ev == MG_EV_HTTP_MSG) {
        struct mg_http_message *hm = (struct mg_http_message *)ev_data;

        // WebSocket upgrade
        if (mg_match(hm->uri, mg_str("/ws/logs"), NULL)) {
            mg_ws_upgrade(c, hm, NULL);
            ws_add(c);
            return;
        }

        // API routes
        if (mg_match(hm->uri, mg_str("/api/*"), NULL)) {
            api_handle(c, hm, s_scripts_dir);
            return;
        }

        // Static files
        struct mg_http_serve_opts opts = {.root_dir = s_web_root};
        mg_http_serve_dir(c, hm, &opts);

    } else if (ev == MG_EV_WS_CLOSE) {
        ws_remove(c);
    }
}

static void *server_thread(void *arg) {
    (void)arg;
    for (;;) mg_mgr_poll(&s_mgr, 50);
    return NULL;
}

void webide_server_start(int port, const char *scripts_dir, const char *web_root) {
    s_scripts_dir = scripts_dir;
    s_web_root    = web_root;
    memset(s_ws_clients, 0, sizeof(s_ws_clients));

    mg_mgr_init(&s_mgr);

    char addr[32];
    snprintf(addr, sizeof(addr), "0.0.0.0:%d", port);
    mg_http_listen(&s_mgr, addr, handle_http, NULL);

    pthread_t tid;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_create(&tid, &attr, server_thread, NULL);
    pthread_attr_destroy(&attr);
}
