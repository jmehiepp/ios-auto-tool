#import "http-client.h"
#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <string.h>

void http_response_free(HttpResponse *r) {
    if (!r) return;
    free(r->body);         r->body         = NULL;
    free(r->content_type); r->content_type = NULL;
}

HttpResponse c_http_request(NSDictionary *options) {
    NSString *url_str  = options[@"url"];
    NSString *method   = options[@"method"] ?: @"GET";
    NSString *body_str = options[@"body"];
    NSDictionary *hdrs = options[@"headers"];
    NSTimeInterval timeout = [options[@"timeout"] doubleValue];
    if (timeout <= 0) timeout = 30.0;

    HttpResponse result = {NULL, 0, NULL};

    NSURL *url = [NSURL URLWithString:url_str];
    if (!url) { result.body = strdup("invalid url"); return result; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:timeout];
    req.HTTPMethod = method;
    if (body_str)
        req.HTTPBody = [body_str dataUsingEncoding:NSUTF8StringEncoding];
    [hdrs enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *_) {
        [req setValue:v forHTTPHeaderField:k];
    }];

    __block NSData   *resp_data    = nil;
    __block NSInteger resp_status  = 0;
    __block NSString *resp_ct      = nil;
    __block NSError  *resp_err     = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    [[[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
            resp_data   = data;
            resp_status = http.statusCode;
            resp_ct     = http.allHeaderFields[@"Content-Type"];
            resp_err    = err;
            dispatch_semaphore_signal(sem);
        }] resume];

    dispatch_semaphore_wait(sem,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)((timeout + 2) * NSEC_PER_SEC)));

    result.status_code = (int)resp_status;
    if (resp_err) {
        result.body = strdup(resp_err.localizedDescription.UTF8String ?: "error");
    } else {
        NSString *s = resp_data
            ? [[NSString alloc] initWithData:resp_data encoding:NSUTF8StringEncoding]
            : @"";
        result.body = strdup(s.UTF8String ?: "");
    }
    result.content_type = strdup(resp_ct.UTF8String ?: "");
    return result;
}

HttpResponse c_http_get(const char *url, NSTimeInterval timeout) {
    return c_http_request(@{
        @"url":     @(url ?: ""),
        @"method":  @"GET",
        @"timeout": @(timeout > 0 ? timeout : 30.0),
    });
}

HttpResponse c_http_post_json(const char *url, const char *json_body,
                              NSTimeInterval timeout) {
    return c_http_request(@{
        @"url":     @(url ?: ""),
        @"method":  @"POST",
        @"body":    @(json_body ?: ""),
        @"timeout": @(timeout > 0 ? timeout : 30.0),
        @"headers": @{@"Content-Type": @"application/json"},
    });
}

HttpResponse c_http_post_form(const char *url, NSDictionary *fields,
                              NSTimeInterval timeout) {
    NSMutableArray *parts = [NSMutableArray array];
    [fields enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *_) {
        NSString *enc_k = [k stringByAddingPercentEncodingWithAllowedCharacters:
                           [NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *enc_v = [v stringByAddingPercentEncodingWithAllowedCharacters:
                           [NSCharacterSet URLQueryAllowedCharacterSet]];
        [parts addObject:[NSString stringWithFormat:@"%@=%@", enc_k, enc_v]];
    }];
    NSString *form = [parts componentsJoinedByString:@"&"];
    return c_http_request(@{
        @"url":     @(url ?: ""),
        @"method":  @"POST",
        @"body":    form,
        @"timeout": @(timeout > 0 ? timeout : 30.0),
        @"headers": @{@"Content-Type": @"application/x-www-form-urlencoded"},
    });
}

int c_download_file(const char *url, const char *dest_path, NSTimeInterval timeout) {
    if (!url || !dest_path) return -1;
    if (timeout <= 0) timeout = 60.0;

    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:@(url)]
                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                     timeoutInterval:timeout];
    __block NSURL  *tmp_url  = nil;
    __block NSError *err     = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    [[[NSURLSession sharedSession] downloadTaskWithRequest:req
        completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *e) {
            tmp_url = loc;
            err     = e;
            dispatch_semaphore_signal(sem);
        }] resume];

    dispatch_semaphore_wait(sem,
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)((timeout + 5) * NSEC_PER_SEC)));

    if (err || !tmp_url) return -1;

    NSError *mv_err = nil;
    NSString *dst = @(dest_path);
    [[NSFileManager defaultManager] createDirectoryAtPath:
        [dst stringByDeletingLastPathComponent]
        withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:dst error:nil];
    [[NSFileManager defaultManager] moveItemAtURL:tmp_url
                                            toURL:[NSURL fileURLWithPath:dst]
                                            error:&mv_err];
    return mv_err ? -1 : 0;
}
