#pragma once
#import <Foundation/Foundation.h>

typedef struct {
    char   *body;         // heap-allocated, caller frees
    int     status_code;
    char   *content_type; // heap-allocated, caller frees
} HttpResponse;

// Synchronous HTTP requests (safe to call from Lua thread).
// options keys: "url","method","headers"(NSDictionary),"body"(NSString),"timeout"(NSNumber)
HttpResponse c_http_request(NSDictionary *options);

// Convenience wrappers
HttpResponse c_http_get(const char *url, NSTimeInterval timeout);
HttpResponse c_http_post_json(const char *url, const char *json_body,
                              NSTimeInterval timeout);
HttpResponse c_http_post_form(const char *url, NSDictionary *fields,
                              NSTimeInterval timeout);

// Download file to path. Returns 0 on success.
int c_download_file(const char *url, const char *dest_path, NSTimeInterval timeout);

void http_response_free(HttpResponse *r);
