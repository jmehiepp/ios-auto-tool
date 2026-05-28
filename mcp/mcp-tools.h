#pragma once
#import <Foundation/Foundation.h>

// All tool handlers share this signature.
// args: NSDictionary parsed from JSON "arguments" field
// Returns MCP result dict: {"content":[...],"isError":bool}
typedef NSDictionary* (*McpToolHandler)(NSDictionary *args);

// Convenience: build a text result
NSDictionary *mcp_text_result(NSString *text, BOOL is_error);

// Convenience: build an error result
NSDictionary *mcp_error_result(NSString *message);

// Tool handler declarations
NSDictionary *tool_lua_run(NSDictionary *args);
NSDictionary *tool_screenshot(NSDictionary *args);
NSDictionary *tool_ocr_screen(NSDictionary *args);
NSDictionary *tool_tap(NSDictionary *args);
NSDictionary *tool_double_tap(NSDictionary *args);
NSDictionary *tool_long_press(NSDictionary *args);
NSDictionary *tool_swipe(NSDictionary *args);
NSDictionary *tool_type_text(NSDictionary *args);
NSDictionary *tool_press_key(NSDictionary *args);
NSDictionary *tool_shell_exec(NSDictionary *args);
NSDictionary *tool_read_file(NSDictionary *args);
NSDictionary *tool_write_file(NSDictionary *args);
NSDictionary *tool_find_color(NSDictionary *args);
NSDictionary *tool_find_image(NSDictionary *args);
NSDictionary *tool_get_color(NSDictionary *args);
NSDictionary *tool_app_run(NSDictionary *args);
NSDictionary *tool_app_kill(NSDictionary *args);
NSDictionary *tool_get_front_app(NSDictionary *args);
NSDictionary *tool_device_info(NSDictionary *args);
NSDictionary *tool_set_clipboard(NSDictionary *args);
NSDictionary *tool_get_clipboard(NSDictionary *args);
NSDictionary *tool_http_request(NSDictionary *args);
