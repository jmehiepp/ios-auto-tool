#import "api-handler.h"
#import "claude-handler.h"
#import "../../daemon/scheduler.h"
#import "../../daemon/script-runner.h"
#import "../../deps/mongoose.h"
#import "../../engine/screen/ocr.h"
#import "../../engine/screen/screenshot.h"
#import "../../engine/touch/recorder.h"
#import "../../mcp/mcp-tools.h"
#import "../../spoof/spoof-config.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>

// Private API forward declarations for app listing
@interface LSApplicationProxy : NSObject
- (NSString *)applicationIdentifier;
- (NSString *)localizedName;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
@end

static void json_reply(struct mg_connection *c, int status,
                       const char *json_body) {
    mg_http_reply(c, status,
                  "Content-Type: application/json\r\n"
                  "Access-Control-Allow-Origin: *\r\n",
                  "%s", json_body);
}

// Extract filename from URI like /api/files/hello.lua → "hello.lua"
static void extract_filename(const struct mg_str *uri, char *out, size_t sz) {
    const char *prefix = "/api/files/";
    size_t plen = strlen(prefix);
    if (uri->len > plen) {
        size_t n = uri->len - plen;
        if (n >= sz) n = sz - 1;
        memcpy(out, uri->buf + plen, n);
        out[n] = '\0';
    } else {
        out[0] = '\0';
    }
}

// GET /api/files → JSON array of filenames
static void handle_list_files(struct mg_connection *c, const char *scripts_dir) {
    NSMutableString *json = [NSMutableString stringWithString:@"["];
    DIR *dir = opendir(scripts_dir);
    if (dir) {
        struct dirent *entry;
        BOOL first = YES;
        while ((entry = readdir(dir)) != NULL) {
            if (entry->d_name[0] == '.') continue;
            if (!first) [json appendString:@","];
            NSString *name = [NSString stringWithUTF8String:entry->d_name];
            [json appendFormat:@"\"%@\"", name];
            first = NO;
        }
        closedir(dir);
    }
    [json appendString:@"]"];
    json_reply(c, 200, json.UTF8String);
}

// GET /api/files/:name → {"content":"..."}
static void handle_read_file(struct mg_connection *c, const char *scripts_dir,
                             const char *name) {
    NSString *path = [[NSString stringWithUTF8String:scripts_dir]
                      stringByAppendingPathComponent:
                      [NSString stringWithUTF8String:name]];
    NSString *content = [NSString stringWithContentsOfFile:path
                         encoding:NSUTF8StringEncoding error:nil];
    if (!content) {
        json_reply(c, 404, "{\"error\":\"not found\"}");
        return;
    }
    // Escape JSON string minimally
    NSString *escaped = [content stringByReplacingOccurrencesOfString:@"\\"
                                                           withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    NSString *json = [NSString stringWithFormat:@"{\"content\":\"%@\"}", escaped];
    json_reply(c, 200, json.UTF8String);
}

// POST /api/files/:name body: {"content":"..."}
static void handle_save_file(struct mg_connection *c, const char *scripts_dir,
                             const char *name, struct mg_http_message *hm) {
    char *content = mg_json_get_str(hm->body, "$.content");
    if (!content) {
        json_reply(c, 400, "{\"error\":\"missing content\"}");
        return;
    }
    NSString *raw = [NSString stringWithUTF8String:content];
    free(content);
    NSString *path = [[NSString stringWithUTF8String:scripts_dir]
                      stringByAppendingPathComponent:
                      [NSString stringWithUTF8String:name]];
    BOOL ok = [raw writeToFile:path atomically:YES encoding:NSUTF8StringEncoding
                         error:nil];
    json_reply(c, ok ? 200 : 500, ok ? "{\"ok\":true}" : "{\"error\":\"write failed\"}");
}

// DELETE /api/files/:name
static void handle_delete_file(struct mg_connection *c, const char *scripts_dir,
                               const char *name) {
    NSString *path = [[NSString stringWithUTF8String:scripts_dir]
                      stringByAppendingPathComponent:
                      [NSString stringWithUTF8String:name]];
    NSError *err = nil;
    BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:path error:&err];
    json_reply(c, ok ? 200 : 404, ok ? "{\"ok\":true}" : "{\"error\":\"not found\"}");
}

// POST /api/run body: {"name":"...","code":"..."}
static void handle_run(struct mg_connection *c, struct mg_http_message *hm) {
    char *code = mg_json_get_str(hm->body, "$.code");
    if (!code) {
        json_reply(c, 400, "{\"error\":\"missing code\"}");
        return;
    }

    script_run(-1, "webide", code);
    free(code);
    json_reply(c, 200, "{\"ok\":true}");
}

// POST /api/stop
static void handle_stop(struct mg_connection *c) {
    script_stop_current();
    json_reply(c, 200, "{\"ok\":true}");
}

// GET /api/device-info
static void handle_device_info(struct mg_connection *c) {
    NSString *version = [[UIDevice currentDevice] systemVersion];
    NSString *model   = [[UIDevice currentDevice] model];
    NSString *json = [NSString stringWithFormat:
        @"{\"ios\":\"%@\",\"model\":\"%@\"}", version, model];
    json_reply(c, 200, json.UTF8String);
}

// Parse JSON body via NSJSONSerialization (handles all value types)
static NSDictionary *parse_json_body(struct mg_http_message *hm) {
    if (!hm->body.len) return nil;
    NSData *data = [NSData dataWithBytes:hm->body.buf length:hm->body.len];
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

// GET /api/screenshot → {"image":"<base64-PNG>","width":N,"height":N}
static void handle_screenshot(struct mg_connection *c) {
    NSDictionary *result = tool_screenshot(@{});
    if ([result[@"isError"] boolValue]) {
        json_reply(c, 500, "{\"error\":\"screenshot failed\"}");
        return;
    }
    NSString *b64 = result[@"content"][0][@"data"];
    CGSize sz    = UIScreen.mainScreen.bounds.size;
    CGFloat sc   = UIScreen.mainScreen.scale;
    int w = (int)(sz.width * sc);
    int h = (int)(sz.height * sc);
    NSString *json = [NSString stringWithFormat:
        @"{\"image\":\"%@\",\"width\":%d,\"height\":%d}", b64, w, h];
    json_reply(c, 200, json.UTF8String);
}

// GET /api/apps → sorted [{bundleId, name}]
static void handle_apps_list(struct mg_connection *c) {
    NSArray *all = [[LSApplicationWorkspace defaultWorkspace] allInstalledApplications];
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:all.count];
    for (LSApplicationProxy *p in all) {
        NSString *bid  = [p applicationIdentifier];
        NSString *name = [p localizedName];
        if (bid.length && name.length)
            [list addObject:@{@"bundleId": bid, @"name": name}];
    }
    [list sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    NSData *data = [NSJSONSerialization dataWithJSONObject:list options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    json_reply(c, 200, json.UTF8String);
}

// POST /api/apps/launch {"bundleId":"..."}
static void handle_apps_launch(struct mg_connection *c, struct mg_http_message *hm) {
    NSDictionary *body = parse_json_body(hm);
    NSString *bid = body[@"bundleId"];
    if (!bid.length) { json_reply(c, 400, "{\"error\":\"missing bundleId\"}"); return; }
    NSDictionary *r = tool_app_run(@{@"bundle_id": bid});
    json_reply(c, [r[@"isError"] boolValue] ? 500 : 200,
               [r[@"isError"] boolValue] ? "{\"error\":\"launch failed\"}" : "{\"ok\":true}");
}

// POST /api/apps/kill {"bundleId":"..."}
static void handle_apps_kill(struct mg_connection *c, struct mg_http_message *hm) {
    NSDictionary *body = parse_json_body(hm);
    NSString *bid = body[@"bundleId"];
    if (!bid.length) { json_reply(c, 400, "{\"error\":\"missing bundleId\"}"); return; }
    NSDictionary *r = tool_app_kill(@{@"bundle_id": bid});
    json_reply(c, [r[@"isError"] boolValue] ? 500 : 200,
               [r[@"isError"] boolValue] ? "{\"error\":\"kill failed\"}" : "{\"ok\":true}");
}

// POST /api/touch {"x":N,"y":N,"type":"tap"|"swipe","dx":N,"dy":N}
static void handle_touch(struct mg_connection *c, struct mg_http_message *hm) {
    NSDictionary *body = parse_json_body(hm);
    double x = [body[@"x"] doubleValue];
    double y = [body[@"y"] doubleValue];
    NSString *type = body[@"type"] ?: @"tap";
    NSDictionary *r;
    if ([type isEqualToString:@"swipe"]) {
        double dx = [body[@"dx"] doubleValue];
        double dy = [body[@"dy"] doubleValue];
        if (recorder_is_recording()) recorder_log_swipe(x, y, x + dx, y + dy);
        r = tool_swipe(@{@"x1": @(x), @"y1": @(y), @"x2": @(x + dx), @"y2": @(y + dy)});
    } else {
        if (recorder_is_recording()) recorder_log_tap(x, y);
        r = tool_tap(@{@"x": @(x), @"y": @(y)});
    }
    json_reply(c, [r[@"isError"] boolValue] ? 500 : 200,
               [r[@"isError"] boolValue] ? "{\"error\":\"touch failed\"}" : "{\"ok\":true}");
}

static void handle_recorder_start(struct mg_connection *c) {
    recorder_start();
    json_reply(c, 200, "{\"ok\":true,\"recording\":true}");
}

static void handle_recorder_stop(struct mg_connection *c) {
    NSString *code = recorder_stop_and_codegen();
    NSArray *events = recorder_get_events();
    recorder_clear();
    NSDictionary *body = @{@"ok": @YES, @"code": code ?: @"", @"count": @(events.count)};
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    json_reply(c, 200, json.UTF8String);
}

static void handle_recorder_events(struct mg_connection *c) {
    NSDictionary *body = @{
        @"recording": @(recorder_is_recording()),
        @"events":    recorder_get_events(),
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    json_reply(c, 200, json.UTF8String);
}

static void handle_schedule_list(struct mg_connection *c) {
    NSArray *list = scheduler_list();
    NSData *data = [NSJSONSerialization dataWithJSONObject:list options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    json_reply(c, 200, json.UTF8String);
}

static void handle_schedule_add(struct mg_connection *c, struct mg_http_message *hm) {
    NSDictionary *body = parse_json_body(hm);
    if (!body) { json_reply(c, 400, "{\"error\":\"invalid body\"}"); return; }
    NSString *jid = scheduler_add(body);
    if (!jid) { json_reply(c, 400, "{\"error\":\"invalid job spec\"}"); return; }
    NSString *json = [NSString stringWithFormat:@"{\"ok\":true,\"id\":\"%@\"}", jid];
    json_reply(c, 200, json.UTF8String);
}

static void handle_schedule_delete(struct mg_connection *c, struct mg_http_message *hm) {
    NSDictionary *body = parse_json_body(hm);
    BOOL ok = scheduler_delete(body[@"id"]);
    json_reply(c, ok ? 200 : 404, ok ? "{\"ok\":true}" : "{\"error\":\"not found\"}");
}

static void handle_schedule_toggle(struct mg_connection *c, struct mg_http_message *hm) {
    NSDictionary *body = parse_json_body(hm);
    BOOL ok = scheduler_toggle(body[@"id"]);
    json_reply(c, ok ? 200 : 404, ok ? "{\"ok\":true}" : "{\"error\":\"not found\"}");
}

static void handle_inspect(struct mg_connection *c) {
    UIImage *img = capture_screen(CGRectZero);
    if (!img) { json_reply(c, 500, "{\"error\":\"screenshot failed\"}"); return; }

    int count = 0;
    OcrObservation *obs = ocr_image_detailed(img, NULL, &count);
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:count];
    for (int i = 0; i < count; i++) {
        NSString *text = obs[i].text ? [NSString stringWithUTF8String:obs[i].text] : @"";
        [items addObject:@{
            @"text":       text,
            @"confidence": @(obs[i].confidence),
            @"x":          @((int)obs[i].x),
            @"y":          @((int)obs[i].y),
            @"w":          @((int)obs[i].w),
            @"h":          @((int)obs[i].h),
        }];
        free(obs[i].text);
    }
    free(obs);

    CGSize sz = img.size;
    NSDictionary *body = @{
        @"width":  @((int)sz.width),
        @"height": @((int)sz.height),
        @"items":  items,
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    json_reply(c, 200, json.UTF8String);
}

// POST /api/key {"key":"home"|"lock"|"volume_up"|"volume_down"|"mute"}
static void handle_key(struct mg_connection *c, struct mg_http_message *hm) {
    NSDictionary *body = parse_json_body(hm);
    NSString *key = body[@"key"];
    if (!key.length) { json_reply(c, 400, "{\"error\":\"missing key\"}"); return; }
    NSDictionary *r = tool_press_key(@{@"key": key});
    json_reply(c, [r[@"isError"] boolValue] ? 400 : 200,
               [r[@"isError"] boolValue] ? "{\"error\":\"unknown key\"}" : "{\"ok\":true}");
}

// GET /api/spoof → raw spoof.json content (or {})
static void handle_spoof_get(struct mg_connection *c) {
    NSData *data = [NSData dataWithContentsOfFile:SPOOF_CONFIG_PATH];
    if (!data) { json_reply(c, 200, "{}"); return; }
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    json_reply(c, 200, json.UTF8String);
}

// POST /api/spoof {"key":"...","value":any}  (null value = disable)
static void handle_spoof_post(struct mg_connection *c, struct mg_http_message *hm) {
    NSDictionary *body = parse_json_body(hm);
    NSString *key = body[@"key"];
    if (!key.length) { json_reply(c, 400, "{\"error\":\"missing key\"}"); return; }
    id value = body[@"value"];
    if (!value || [value isKindOfClass:[NSNull class]])
        [[SpoofConfig shared] setEnabled:NO forModule:key];
    else
        [[SpoofConfig shared] setValue:value forModule:key];
    json_reply(c, 200, "{\"ok\":true}");
}

// POST /api/spoof/preset {"name":"iphone14_pro_max"|"iphone13"}
static void handle_spoof_preset(struct mg_connection *c, struct mg_http_message *hm) {
    NSDictionary *body = parse_json_body(hm);
    NSString *name = body[@"name"];
    static NSDictionary *presets = nil;
    static dispatch_once_t tok;
    dispatch_once(&tok, ^{
        presets = @{
            @"iphone14_pro_max": @{
                @"device_model": @"iPhone15,2",
                @"ios_version":  @"17.4.1",
                @"screen_width": @430,
                @"screen_height":@932,
                @"screen_scale": @3,
                @"locale":       @"en_US",
                @"timezone":     @"America/Los_Angeles",
            },
            @"iphone13": @{
                @"device_model": @"iPhone14,5",
                @"ios_version":  @"16.7.8",
                @"screen_width": @390,
                @"screen_height":@844,
                @"screen_scale": @3,
                @"locale":       @"en_US",
                @"timezone":     @"America/New_York",
            },
        };
    });
    NSDictionary *preset = presets[name];
    if (!preset) { json_reply(c, 400, "{\"error\":\"unknown preset\"}"); return; }
    SpoofConfig *sc = [SpoofConfig shared];
    [preset enumerateKeysAndObjectsUsingBlock:^(NSString *k, id v, BOOL *stop) {
        [sc setValue:v forModule:k];
    }];
    json_reply(c, 200, "{\"ok\":true}");
}

// DELETE /api/spoof → reset all spoof fields
static void handle_spoof_reset(struct mg_connection *c) {
    [[SpoofConfig shared] reset];
    json_reply(c, 200, "{\"ok\":true}");
}

void api_handle(struct mg_connection *c, struct mg_http_message *hm,
                const char *scripts_dir) {
    char filename[256] = {0};

    // Handle OPTIONS preflight (CORS)
    if (mg_match(hm->method, mg_str("OPTIONS"), NULL)) {
        mg_http_reply(c, 204,
                      "Access-Control-Allow-Origin: *\r\n"
                      "Access-Control-Allow-Methods: GET,POST,DELETE,OPTIONS\r\n"
                      "Access-Control-Allow-Headers: Content-Type\r\n", "");
        return;
    }

    if (mg_match(hm->uri, mg_str("/api/files"), NULL) &&
        mg_match(hm->method, mg_str("GET"), NULL)) {
        handle_list_files(c, scripts_dir);

    } else if (mg_match(hm->uri, mg_str("/api/files/*"), NULL)) {
        extract_filename(&hm->uri, filename, sizeof(filename));
        if (mg_match(hm->method, mg_str("GET"), NULL))
            handle_read_file(c, scripts_dir, filename);
        else if (mg_match(hm->method, mg_str("POST"), NULL))
            handle_save_file(c, scripts_dir, filename, hm);
        else if (mg_match(hm->method, mg_str("DELETE"), NULL))
            handle_delete_file(c, scripts_dir, filename);
        else
            json_reply(c, 405, "{\"error\":\"method not allowed\"}");

    } else if (mg_match(hm->uri, mg_str("/api/chat"), NULL) &&
               mg_match(hm->method, mg_str("POST"), NULL)) {
        claude_handle_chat(c, hm);

    } else if (mg_match(hm->uri, mg_str("/api/run"), NULL)) {
        handle_run(c, hm);

    } else if (mg_match(hm->uri, mg_str("/api/stop"), NULL)) {
        handle_stop(c);

    } else if (mg_match(hm->uri, mg_str("/api/device-info"), NULL)) {
        handle_device_info(c);

    } else if (mg_match(hm->uri, mg_str("/api/screenshot"), NULL) &&
               mg_match(hm->method, mg_str("GET"), NULL)) {
        handle_screenshot(c);

    // App routes — specific paths before /api/apps generic
    } else if (mg_match(hm->uri, mg_str("/api/apps/launch"), NULL) &&
               mg_match(hm->method, mg_str("POST"), NULL)) {
        handle_apps_launch(c, hm);

    } else if (mg_match(hm->uri, mg_str("/api/apps/kill"), NULL) &&
               mg_match(hm->method, mg_str("POST"), NULL)) {
        handle_apps_kill(c, hm);

    } else if (mg_match(hm->uri, mg_str("/api/apps"), NULL) &&
               mg_match(hm->method, mg_str("GET"), NULL)) {
        handle_apps_list(c);

    } else if (mg_match(hm->uri, mg_str("/api/touch"), NULL) &&
               mg_match(hm->method, mg_str("POST"), NULL)) {
        handle_touch(c, hm);

    } else if (mg_match(hm->uri, mg_str("/api/recorder/start"), NULL) &&
               mg_match(hm->method, mg_str("POST"), NULL)) {
        handle_recorder_start(c);

    } else if (mg_match(hm->uri, mg_str("/api/recorder/stop"), NULL) &&
               mg_match(hm->method, mg_str("POST"), NULL)) {
        handle_recorder_stop(c);

    } else if (mg_match(hm->uri, mg_str("/api/recorder/events"), NULL) &&
               mg_match(hm->method, mg_str("GET"), NULL)) {
        handle_recorder_events(c);

    } else if (mg_match(hm->uri, mg_str("/api/schedule"), NULL) &&
               mg_match(hm->method, mg_str("GET"), NULL)) {
        handle_schedule_list(c);

    } else if (mg_match(hm->uri, mg_str("/api/schedule/add"), NULL) &&
               mg_match(hm->method, mg_str("POST"), NULL)) {
        handle_schedule_add(c, hm);

    } else if (mg_match(hm->uri, mg_str("/api/schedule/delete"), NULL) &&
               mg_match(hm->method, mg_str("POST"), NULL)) {
        handle_schedule_delete(c, hm);

    } else if (mg_match(hm->uri, mg_str("/api/schedule/toggle"), NULL) &&
               mg_match(hm->method, mg_str("POST"), NULL)) {
        handle_schedule_toggle(c, hm);

    } else if (mg_match(hm->uri, mg_str("/api/inspect"), NULL) &&
               mg_match(hm->method, mg_str("GET"), NULL)) {
        handle_inspect(c);

    } else if (mg_match(hm->uri, mg_str("/api/key"), NULL) &&
               mg_match(hm->method, mg_str("POST"), NULL)) {
        handle_key(c, hm);

    // Spoof routes — preset before generic /api/spoof
    } else if (mg_match(hm->uri, mg_str("/api/spoof/preset"), NULL) &&
               mg_match(hm->method, mg_str("POST"), NULL)) {
        handle_spoof_preset(c, hm);

    } else if (mg_match(hm->uri, mg_str("/api/spoof"), NULL) &&
               mg_match(hm->method, mg_str("GET"), NULL)) {
        handle_spoof_get(c);

    } else if (mg_match(hm->uri, mg_str("/api/spoof"), NULL) &&
               mg_match(hm->method, mg_str("POST"), NULL)) {
        handle_spoof_post(c, hm);

    } else if (mg_match(hm->uri, mg_str("/api/spoof"), NULL) &&
               mg_match(hm->method, mg_str("DELETE"), NULL)) {
        handle_spoof_reset(c);

    } else {
        json_reply(c, 404, "{\"error\":\"not found\"}");
    }
}
