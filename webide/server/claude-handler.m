#import "claude-handler.h"
#import "../../engine/system/http-client.h"

static NSString *const kClaudeURL   = @"https://api.anthropic.com/v1/messages";
static NSString *const kClaudeModel = @"claude-sonnet-4-6";


static NSString *kSystemPrompt = @"\
Bạn là trợ lý sinh script Lua cho iOSAutoTool — daemon chạy trên iPhone jailbreak.\n\
\n\
API có sẵn (gọi từ Lua):\n\
- tap(x, y) / swipe(x1,y1,x2,y2,duration) / longPress(x,y,duration)\n\
- screenshot() trả về buffer ảnh / findColor(rgb, tolerance)\n\
- ocr() trả về text / findImage(template_path)\n\
- appRun(bundle_id) / appKill(bundle_id) / frontMostAppId()\n\
- inputText(text) / keyPress(key_name)\n\
- shell(cmd) / sleep(ms) / httpGet(url)\n\
- log(msg) — log ra console Web IDE\n\
\n\
Quy tắc:\n\
1. LUÔN bọc code trong block ```lua ... ```\n\
2. Code phải chạy được ngay, không cần chỉnh sửa\n\
3. Thêm log() ở các bước quan trọng để user theo dõi\n\
4. Tránh hardcode toạ độ tuyệt đối — dùng find_color / find_image / ocr nếu được\n\
5. Có sleep giữa các action (300-800ms) để UI kịp render\n\
6. Trả lời tiếng Việt ngắn gọn rồi mới đến code block\n";

static NSString *extract_code_block(NSString *text) {
    NSRange start = [text rangeOfString:@"```lua"];
    if (start.location == NSNotFound) {
        start = [text rangeOfString:@"```"];
        if (start.location == NSNotFound) return nil;
    }
    NSUInteger code_start = NSMaxRange(start);
    while (code_start < text.length && [text characterAtIndex:code_start] == '\n') code_start++;

    NSRange end_search = NSMakeRange(code_start, text.length - code_start);
    NSRange end = [text rangeOfString:@"```" options:0 range:end_search];
    if (end.location == NSNotFound) return nil;

    return [[text substringWithRange:NSMakeRange(code_start, end.location - code_start)]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static void send_json_reply(struct mg_connection *c, int status, NSDictionary *body) {
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:&err];
    NSString *json = data
        ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
        : @"{\"error\":\"json serialization failed\"}";
    mg_http_reply(c, status,
                  "Content-Type: application/json\r\n"
                  "Cache-Control: no-store\r\n",
                  "%s", json.UTF8String);
}

void claude_handle_chat(struct mg_connection *c, struct mg_http_message *hm) {
    const char *api_key = getenv("ANTHROPIC_API_KEY");
    if (!api_key || !api_key[0]) {
        send_json_reply(c, 503, @{@"error": @"AI chat is not configured on this device"});
        return;
    }

    NSData *body_data = [NSData dataWithBytes:hm->body.buf length:hm->body.len];
    NSError *parse_err = nil;
    NSDictionary *req = [NSJSONSerialization JSONObjectWithData:body_data options:0
                                                          error:&parse_err];
    if (!req || ![req isKindOfClass:[NSDictionary class]]) {
        send_json_reply(c, 400, @{@"error": @"invalid json body"});
        return;
    }

    NSString *message = req[@"message"];
    NSArray *history  = req[@"history"] ?: @[];
    if (!message.length) {
        send_json_reply(c, 400, @{@"error": @"missing message"});
        return;
    }

    NSMutableArray *messages = [NSMutableArray array];
    for (NSDictionary *m in history) {
        if ([m isKindOfClass:[NSDictionary class]] && m[@"role"] && m[@"content"]) {
            [messages addObject:@{@"role": m[@"role"], @"content": m[@"content"]}];
        }
    }
    [messages addObject:@{@"role": @"user", @"content": message}];

    NSDictionary *payload = @{
        @"model":      kClaudeModel,
        @"max_tokens": @2048,
        @"system":     kSystemPrompt,
        @"messages":   messages,
    };
    NSData *payload_data = [NSJSONSerialization dataWithJSONObject:payload options:0
                                                              error:nil];
    NSString *payload_str = [[NSString alloc] initWithData:payload_data
                                                  encoding:NSUTF8StringEncoding];

    HttpResponse resp = c_http_request(@{
        @"url":     kClaudeURL,
        @"method":  @"POST",
        @"body":    payload_str,
        @"timeout": @60.0,
        @"headers": @{
            @"Content-Type":      @"application/json",
            @"x-api-key":         @(api_key),
            @"anthropic-version": @"2023-06-01",
        },
    });

    if (resp.status_code < 200 || resp.status_code >= 300) {
        NSString *err_body = @(resp.body ?: "");
        http_response_free(&resp);
        send_json_reply(c, 502, @{
            @"error":  @"upstream error",
            @"status": @(resp.status_code),
            @"body":   err_body,
        });
        return;
    }

    NSData *resp_data = [@(resp.body ?: "") dataUsingEncoding:NSUTF8StringEncoding];
    http_response_free(&resp);

    NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:resp_data options:0
                                                              error:nil];
    NSArray *content = parsed[@"content"];
    NSString *text = nil;
    for (NSDictionary *block in content) {
        if ([block[@"type"] isEqualToString:@"text"]) {
            text = block[@"text"];
            break;
        }
    }
    if (!text.length) {
        send_json_reply(c, 502, @{@"error": @"empty response from claude"});
        return;
    }

    NSString *code = extract_code_block(text);
    send_json_reply(c, 200, @{
        @"reply": text,
        @"code":  code ?: @"",
    });
}
