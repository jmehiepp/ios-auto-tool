#import "../mcp-tools.h"
#import "../../engine/system/shell-exec.h"
#import "../../engine/system/file-ops.h"
#import "../../engine/system/http-client.h"
#import <Foundation/Foundation.h>

NSDictionary *tool_shell_exec(NSDictionary *args) {
    NSString *cmd = args[@"cmd"];
    if (!cmd.length) return mcp_error_result(@"'cmd' is required");

    int exit_code = 0;
    char *out = c_shell_exec_output(cmd.UTF8String, &exit_code);
    NSString *output = out ? [NSString stringWithUTF8String:out] : @"";
    free(out);

    NSString *text = [NSString stringWithFormat:@"exit: %d\n%@", exit_code, output];
    return mcp_text_result(text, exit_code != 0);
}

NSDictionary *tool_read_file(NSDictionary *args) {
    NSString *path = args[@"path"];
    if (!path.length) return mcp_error_result(@"'path' is required");
    NSString *content = c_read_file(path.UTF8String);
    if (!content) return mcp_error_result(
        [NSString stringWithFormat:@"File not found: %@", path]);
    return mcp_text_result(content, NO);
}

NSDictionary *tool_write_file(NSDictionary *args) {
    NSString *path    = args[@"path"];
    NSString *content = args[@"content"];
    if (!path.length || !content) return mcp_error_result(@"'path' and 'content' required");
    BOOL ok = c_write_file(path.UTF8String, content.UTF8String);
    return mcp_text_result(ok ? @"written" : @"write failed", !ok);
}

NSDictionary *tool_http_request(NSDictionary *args) {
    NSString *url    = args[@"url"];
    if (!url.length) return mcp_error_result(@"'url' is required");

    NSMutableDictionary *opts = [NSMutableDictionary dictionaryWithDictionary:args];
    if (!opts[@"method"]) opts[@"method"] = @"GET";
    if (!opts[@"timeout"]) opts[@"timeout"] = @30;

    HttpResponse r = c_http_request(opts);
    NSString *body = r.body ? [NSString stringWithUTF8String:r.body] : @"";
    NSString *text = [NSString stringWithFormat:@"HTTP %d\n%@", r.status_code, body];
    http_response_free(&r);
    return mcp_text_result(text, r.status_code >= 400);
}
