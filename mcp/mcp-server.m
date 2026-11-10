#import "mcp-server.h"
#import "mcp-tools.h"
#import "../webide/server/access-control.h"
#import "../deps/mongoose.h"
#import <Foundation/Foundation.h>
#import <pthread.h>
#include <string.h>
#include <stdlib.h>

#define MCP_PROTOCOL_VERSION "2024-11-05"
#define MCP_SERVER_NAME      "ios-auto-tool"
#define MCP_SERVER_VERSION   "1.2.0-beta4"

// ---------- Tool registry ----------

typedef struct { const char *name; McpToolHandler fn; } ToolEntry;

static ToolEntry s_tools[] = {
    {"lua_run",       tool_lua_run},
    {"screenshot",    tool_screenshot},
    {"ocr_screen",    tool_ocr_screen},
    {"tap",           tool_tap},
    {"double_tap",    tool_double_tap},
    {"long_press",    tool_long_press},
    {"swipe",         tool_swipe},
    {"type_text",     tool_type_text},
    {"press_key",     tool_press_key},
    {"shell_exec",    tool_shell_exec},
    {"read_file",     tool_read_file},
    {"write_file",    tool_write_file},
    {"find_color",    tool_find_color},
    {"find_image",    tool_find_image},
    {"get_color",     tool_get_color},
    {"app_run",       tool_app_run},
    {"app_kill",      tool_app_kill},
    {"get_front_app", tool_get_front_app},
    {"device_info",   tool_device_info},
    {"device_configuration_get", tool_device_configuration_get},
    {"device_configuration_set", tool_device_configuration_set},
    {"script_status", tool_script_status},
    {"script_stop", tool_script_stop},
    {"set_clipboard", tool_set_clipboard},
    {"get_clipboard", tool_get_clipboard},
    {"http_request",  tool_http_request},
};
#define TOOL_COUNT (sizeof(s_tools)/sizeof(s_tools[0]))

// Serial queue — prevents concurrent Lua/engine execution
static dispatch_queue_t s_tool_q;

// ---------- Tool schema definitions ----------

static NSDictionary *prop_str(NSString *desc) {
    return @{@"type": @"string", @"description": desc};
}
static NSDictionary *prop_num(NSString *desc) {
    return @{@"type": @"number", @"description": desc};
}
static NSDictionary *region_prop(void) {
    return @{@"type": @"object",
             @"description": @"Optional search region {x,y,w,h}",
             @"properties": @{
                 @"x": prop_num(@"left"), @"y": prop_num(@"top"),
                 @"w": prop_num(@"width"), @"h": prop_num(@"height"),
             }};
}

static NSArray *build_tools_list(void) {
    return @[
      @{@"name": @"lua_run",
        @"description": @"Execute Lua script on the iOS device",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"code": prop_str(@"Lua code to execute")},
          @"required": @[@"code"]}},

      @{@"name": @"screenshot",
        @"description": @"Capture screen, return base64 PNG",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"region": region_prop()}}},

      @{@"name": @"ocr_screen",
        @"description": @"OCR text recognition on screen",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"region": region_prop()}}},

      @{@"name": @"tap",
        @"description": @"Tap at (x, y)",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"x": prop_num(@"X coordinate"),
                           @"y": prop_num(@"Y coordinate")},
          @"required": @[@"x",@"y"]}},

      @{@"name": @"double_tap",
        @"description": @"Double-tap at (x, y)",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"x": prop_num(@"X"), @"y": prop_num(@"Y")},
          @"required": @[@"x",@"y"]}},

      @{@"name": @"long_press",
        @"description": @"Long press at (x, y) for duration_ms milliseconds",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"x": prop_num(@"X"), @"y": prop_num(@"Y"),
                           @"duration_ms": prop_num(@"Hold duration in ms")},
          @"required": @[@"x",@"y"]}},

      @{@"name": @"swipe",
        @"description": @"Swipe from (x1,y1) to (x2,y2)",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"x1": prop_num(@"Start X"), @"y1": prop_num(@"Start Y"),
                           @"x2": prop_num(@"End X"),   @"y2": prop_num(@"End Y"),
                           @"duration_ms": prop_num(@"Duration in ms")},
          @"required": @[@"x1",@"y1",@"x2",@"y2"]}},

      @{@"name": @"type_text",
        @"description": @"Type text into the focused input field",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"text": prop_str(@"Text to type")},
          @"required": @[@"text"]}},

      @{@"name": @"press_key",
        @"description": @"Press system key: home, lock, volume_up, volume_down, mute",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"key": prop_str(@"Key name")},
          @"required": @[@"key"]}},

      @{@"name": @"shell_exec",
        @"description": @"Run a shell command, return stdout and exit code",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"cmd": prop_str(@"Shell command")},
          @"required": @[@"cmd"]}},

      @{@"name": @"read_file",
        @"description": @"Read a file and return its content",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"path": prop_str(@"File path")},
          @"required": @[@"path"]}},

      @{@"name": @"write_file",
        @"description": @"Write content to a file",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"path":    prop_str(@"File path"),
                           @"content": prop_str(@"Content to write")},
          @"required": @[@"path",@"content"]}},

      @{@"name": @"find_color",
        @"description": @"Find pixel by color on screen, return {x,y} or null",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"color":     prop_num(@"0xRRGGBB"),
                           @"tolerance": prop_num(@"Per-channel tolerance 0-255"),
                           @"region":    region_prop()},
          @"required": @[@"color"]}},

      @{@"name": @"find_image",
        @"description": @"Template match base64 PNG on screen, return {x,y,score} or null",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"image_b64": prop_str(@"Base64-encoded PNG template"),
                           @"threshold": prop_num(@"Match threshold 0.0-1.0"),
                           @"region":    region_prop()},
          @"required": @[@"image_b64"]}},

      @{@"name": @"get_color",
        @"description": @"Get pixel color at (x, y), return {r,g,b,a}",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"x": prop_num(@"X"), @"y": prop_num(@"Y")},
          @"required": @[@"x",@"y"]}},

      @{@"name": @"app_run",
        @"description": @"Launch app by bundle ID",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"bundle_id": prop_str(@"App bundle identifier")},
          @"required": @[@"bundle_id"]}},

      @{@"name": @"app_kill",
        @"description": @"Kill app by bundle ID",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"bundle_id": prop_str(@"App bundle identifier")},
          @"required": @[@"bundle_id"]}},

      @{@"name": @"get_front_app",
        @"description": @"Get the foreground app bundle ID",
        @"inputSchema": @{@"type":@"object", @"properties": @{}}},

      @{@"name": @"device_info",
        @"description": @"Get device model, iOS version, screen size and IP",
        @"inputSchema": @{@"type":@"object", @"properties": @{}}},

      @{@"name": @"set_clipboard",
        @"description": @"Set clipboard text",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"text": prop_str(@"Text to set")},
          @"required": @[@"text"]}},

      @{@"name": @"device_configuration_get",
        @"description": @"Read the complete app-scoped device configuration",
        @"inputSchema": @{@"type":@"object", @"properties":@{}}},
      @{@"name": @"device_configuration_set",
        @"description": @"Replace device profile. Selected apps must be reopened to apply enabled hooks.",
        @"inputSchema": @{@"type":@"object", @"required":@[@"configuration"], @"properties":@{
          @"configuration":@{@"type":@"object", @"required":@[@"enabled",@"selectedApps",@"modules"], @"properties":@{
            @"enabled":@{@"type":@"boolean"}, @"selectedApps":@{@"type":@"array", @"items":@{@"type":@"string"}},
            @"modules":@{@"type":@"object"}}}}}},
      @{@"name": @"script_status", @"description": @"Read whether a Lua script is running",
        @"inputSchema": @{@"type":@"object", @"properties":@{}}},
      @{@"name": @"script_stop", @"description": @"Request cancellation; use script_status to confirm completion",
        @"inputSchema": @{@"type":@"object", @"properties":@{}}},

      @{@"name": @"get_clipboard",
        @"description": @"Get current clipboard text",
        @"inputSchema": @{@"type":@"object", @"properties": @{}}},

      @{@"name": @"http_request",
        @"description": @"Perform HTTP request from device",
        @"inputSchema": @{@"type":@"object",
          @"properties": @{@"url":     prop_str(@"Request URL"),
                           @"method":  prop_str(@"HTTP method (GET/POST/...)"),
                           @"headers": @{@"type": @"object"},
                           @"body":    prop_str(@"Request body")},
          @"required": @[@"url"]}},
    ];
}

// ---------- JSON-RPC helpers ----------

static NSData *jsonrpc_response(id req_id, id result, id error) {
    NSMutableDictionary *resp = [NSMutableDictionary dictionary];
    resp[@"jsonrpc"] = @"2.0";
    if (req_id) resp[@"id"] = req_id;
    if (result) resp[@"result"] = result;
    if (error)  resp[@"error"]  = error;
    return [NSJSONSerialization dataWithJSONObject:resp options:0 error:nil];
}

static void send_json(struct mg_connection *c, NSData *data) {
    if (!data) return;
    mg_http_reply(c, 200,
                  "Content-Type: application/json\r\n"
                  "Access-Control-Allow-Origin: *\r\n",
                  "%.*s", (int)data.length, (const char *)data.bytes);
}

// ---------- Request handler ----------

static void handle_mcp(struct mg_connection *c, struct mg_http_message *hm) {
    // CORS preflight
    if (mg_match(hm->method, mg_str("OPTIONS"), NULL)) {
        mg_http_reply(c, 204,
                      "Access-Control-Allow-Origin: *\r\n"
                      "Access-Control-Allow-Methods: POST,OPTIONS\r\n"
                      "Access-Control-Allow-Headers: Content-Type\r\n", "");
        return;
    }

    if (!mg_match(hm->uri, mg_str("/mcp"), NULL)) {
        mg_http_reply(c, 404, "", "Not found");
        return;
    }

    NSData *body_data = [NSData dataWithBytes:hm->body.buf length:hm->body.len];
    NSDictionary *req = [NSJSONSerialization JSONObjectWithData:body_data
                                                       options:0 error:nil];
    if (!req) {
        NSData *r = jsonrpc_response(nil,
            nil, @{@"code": @(-32700), @"message": @"Parse error"});
        send_json(c, r);
        return;
    }

    id req_id     = req[@"id"];
    NSString *method = req[@"method"];
    NSDictionary *params = req[@"params"];

    if ([method isEqualToString:@"initialize"]) {
        NSDictionary *result = @{
            @"protocolVersion": @MCP_PROTOCOL_VERSION,
            @"capabilities":    @{@"tools": @{@"listChanged": @NO}},
            @"serverInfo":      @{@"name": @MCP_SERVER_NAME,
                                  @"version": @MCP_SERVER_VERSION},
        };
        send_json(c, jsonrpc_response(req_id, result, nil));

    } else if ([method isEqualToString:@"notifications/initialized"]) {
        // No response needed for notifications
        mg_http_reply(c, 204, "", "");

    } else if ([method isEqualToString:@"tools/list"]) {
        NSDictionary *result = @{@"tools": build_tools_list()};
        send_json(c, jsonrpc_response(req_id, result, nil));

    } else if ([method isEqualToString:@"tools/call"]) {
        NSString *tool_name = params[@"name"];
        NSDictionary *args  = params[@"arguments"] ?: @{};

        McpToolHandler handler = NULL;
        for (size_t i = 0; i < TOOL_COUNT; i++) {
            if ([tool_name isEqualToString:@(s_tools[i].name)]) {
                handler = s_tools[i].fn;
                break;
            }
        }

        if (!handler) {
            send_json(c, jsonrpc_response(req_id, nil,
                @{@"code": @(-32601), @"message": @"Tool not found"}));
            return;
        }

        __block NSDictionary *result = nil;
        dispatch_sync(s_tool_q, ^{
            result = handler(args);
        });
        send_json(c, jsonrpc_response(req_id,
                                      result ?: mcp_error_result(@"Tool error"), nil));

    } else {
        send_json(c, jsonrpc_response(req_id, nil,
            @{@"code": @(-32601), @"message": @"Method not found"}));
    }
}

// ---------- Mongoose event loop ----------

static struct mg_mgr s_mgr;

static void ev_handler(struct mg_connection *c, int ev, void *ev_data) {
    if (ev == MG_EV_HTTP_MSG) {
        struct mg_http_message *hm = ev_data;
        if (!iat_request_authorized(hm)) { mg_http_reply(c, 401, "Content-Type: application/json\r\n", "{\"error\":\"authentication required\"}"); return; }
        if (!mg_match(hm->method, mg_str("POST"), NULL)) { mg_http_reply(c, 405, "Allow: POST\r\n", ""); return; }
        handle_mcp(c, hm);
    }
}

static void *mcp_thread(void *arg) {
    (void)arg;
    for (;;) { @autoreleasepool { mg_mgr_poll(&s_mgr, 50); } }
    return NULL;
}

void mcp_server_start(int port) {
    s_tool_q = dispatch_queue_create("com.iosautotool.mcp", DISPATCH_QUEUE_SERIAL);
    mg_mgr_init(&s_mgr);

    char addr[48];
    snprintf(addr, sizeof(addr), "127.0.0.1:%d", port);
    mg_http_listen(&s_mgr, addr, ev_handler, NULL);

    pthread_t tid;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_create(&tid, &attr, mcp_thread, NULL);
    pthread_attr_destroy(&attr);
}
