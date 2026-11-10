#import <Foundation/Foundation.h>
#import "../daemon/scheduler.m"
#include <assert.h>
#include <stdlib.h>

static BOOL accept_run = NO;
static unsigned int accepted_runs = 0;
bool script_run(int fd, const char *identifier, const char *source) {
    (void)fd; (void)identifier;
    assert(strcmp(source, "log('fixture')") == 0);
    if (accept_run) accepted_runs++;
    return accept_run;
}
void log_info(const char *format, ...) { (void)format; }
void log_warn(const char *format, ...) { (void)format; }
static void flush_tick(void) { tick(); dispatch_sync(g_queue, ^{}); }
int main(void) {
    @autoreleasepool {
        char folder[] = "/tmp/iat-scheduler-XXXXXX";
        assert(mkdtemp(folder)); setenv("IAT_DATA_DIR", folder, 1);
        NSString *base = @(folder);
        g_scripts_dir = [base stringByAppendingPathComponent:@"scripts"];
        assert([NSFileManager.defaultManager createDirectoryAtPath:g_scripts_dir withIntermediateDirectories:YES attributes:nil error:nil]);
        assert([@"log('fixture')" writeToFile:[g_scripts_dir stringByAppendingPathComponent:@"probe.lua"] atomically:YES encoding:NSUTF8StringEncoding error:nil]);
        assert(!scheduler_add(@{@"type":@"interval", @"script":@"../escape.lua", @"interval_minutes":@1}));
        assert(!scheduler_add(@{@"type":@"interval", @"script":@"probe.lua", @"interval_minutes":@0}));
        assert(!scheduler_add(@{@"type":@"daily", @"script":@"probe.lua", @"hour":@24, @"minute":@0}));
        assert(!scheduler_add(@{@"type":@"daily", @"script":@"probe.lua", @"hour":@1, @"minute":@"00"}));
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        NSString *identifier = scheduler_add(@{@"type":@"once", @"script":@"probe.lua", @"at":@(now+60)});
        assert(identifier && scheduler_list().count == 1);
        dispatch_sync(g_queue, ^{ NSMutableDictionary *job = [g_jobs[0] mutableCopy]; job[@"next_run"] = @(now-1); g_jobs[0] = job; });
        flush_tick();
        assert(accepted_runs == 0 && [scheduler_list()[0][@"enabled"] boolValue]);
        assert([scheduler_list()[0][@"last_run"] doubleValue] == 0);
        accept_run = YES; flush_tick();
        assert(accepted_runs == 1 && ![scheduler_list()[0][@"enabled"] boolValue]);
        flush_tick(); assert(accepted_runs == 1);
        assert(compute_next_run(@{@"type":@"interval", @"interval_minutes":@2}, now) == now+120);
        dispatch_sync(g_queue, ^{ load_jobs(); });
        assert(scheduler_list().count == 1 && ![scheduler_list()[0][@"enabled"] boolValue]);
        assert(scheduler_delete(identifier) && scheduler_list().count == 0);
        assert([NSFileManager.defaultManager removeItemAtPath:base error:nil]);
        puts("Scheduler validation, persistence and busy retry tests passed");
    }
    return 0;
}
