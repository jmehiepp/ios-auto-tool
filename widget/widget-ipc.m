#import "widget-ipc.h"
#import "../daemon/platform-paths.h"
#include "widget-ipc-transport.h"

static NSString *const WidgetIPCErrorDomain = @"IOSAutoToolWidgetIPC";

BOOL widget_ipc_valid_script_name(NSString *name) {
    if (![name isKindOfClass:NSString.class] || !name.length ||
        ![name hasSuffix:@".lua"] ||
        [name rangeOfString:@"/"].location != NSNotFound ||
        [name rangeOfString:@"\\"].location != NSNotFound ||
        [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound)
        return NO;
    NSData *utf8 = [name dataUsingEncoding:NSUTF8StringEncoding];
    return utf8.length > 4 && utf8.length <= 255 &&
        [name isEqualToString:name.lastPathComponent];
}

NSDictionary *widget_ipc_request(NSString *action, NSString *name, NSError **error) {
    BOOL run = [action isEqualToString:@"run_saved_script"];
    BOOL known = run || [action isEqualToString:@"stop_script"] ||
        [action isEqualToString:@"list_scripts"] || [action isEqualToString:@"script_status"];
    if (!known || (run && !widget_ipc_valid_script_name(name)) || (!run && name != nil)) {
        if (error) *error = [NSError errorWithDomain:WidgetIPCErrorDomain code:EINVAL
            userInfo:@{NSLocalizedDescriptionKey: @"Tên script hoặc yêu cầu không hợp lệ."}];
        return nil;
    }
    NSString *identifier = NSUUID.UUID.UUIDString;
    NSMutableDictionary *request = [@{@"action": action, @"id": identifier} mutableCopy];
    if (run) request[@"name"] = name;
    NSMutableData *payload = [[NSJSONSerialization dataWithJSONObject:request options:0 error:error] mutableCopy];
    if (!payload) return nil;
    [payload appendBytes:"\n" length:1];
    unsigned char response[WIDGET_IPC_MAX_RESPONSE];
    size_t responseLength = 0;
    int failure = widget_transport_exchange(IAT_PATH(WIDGET_IPC_SOCKET_PATH),
        payload.bytes, payload.length, response, sizeof(response), &responseLength,
        WIDGET_IPC_TIMEOUT_MS);
    if (failure) {
        NSString *message = failure == ETIMEDOUT ? @"Daemon chưa trả lời trong 3 giây." :
            @"Không kết nối được daemon. Kiểm tra dịch vụ iOS Auto Tool.";
        if (error) *error = [NSError errorWithDomain:WidgetIPCErrorDomain code:failure
            userInfo:@{NSLocalizedDescriptionKey: message}];
        return nil;
    }
    NSData *bytes = [NSData dataWithBytes:response length:responseLength];
    id decoded = [NSJSONSerialization JSONObjectWithData:bytes options:0 error:error];
    if (![decoded isKindOfClass:NSDictionary.class] ||
        ![decoded[@"id"] isKindOfClass:NSString.class] ||
        ![decoded[@"id"] isEqualToString:identifier] ||
        ![decoded[@"ok"] isKindOfClass:NSNumber.class]) {
        if (error) *error = [NSError errorWithDomain:WidgetIPCErrorDomain code:EPROTO
            userInfo:@{NSLocalizedDescriptionKey: @"Phản hồi daemon không khớp yêu cầu."}];
        return nil;
    }
    return decoded;
}

BOOL widget_ipc_run_script(NSString *name) {
    return [widget_ipc_request(@"run_saved_script", name, NULL)[@"ok"] boolValue];
}

BOOL widget_ipc_stop_script(void) {
    return [widget_ipc_request(@"stop_script", nil, NULL)[@"ok"] boolValue];
}
