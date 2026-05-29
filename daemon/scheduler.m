#import "scheduler.h"
#import "script-runner.h"
#import "logger.h"

#define SCHEDULES_PATH @"/Library/IOSAutoTool/schedules.json"
#define TICK_SECONDS 30.0

static NSMutableArray *g_jobs = nil;
static NSString *g_scripts_dir = nil;
static dispatch_queue_t g_queue = nil;
static NSTimer *g_timer = nil;

static void ensure_queue(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_queue = dispatch_queue_create("io.iosautotool.scheduler", DISPATCH_QUEUE_SERIAL);
    });
}

static void save_jobs(void) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:g_jobs ?: @[]
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:nil];
    [data writeToFile:SCHEDULES_PATH atomically:YES];
}

static void load_jobs(void) {
    NSData *data = [NSData dataWithContentsOfFile:SCHEDULES_PATH];
    if (!data) { g_jobs = [NSMutableArray array]; return; }
    NSArray *arr = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    g_jobs = arr ? [arr mutableCopy] : [NSMutableArray array];
}

static NSTimeInterval compute_next_run(NSDictionary *job, NSTimeInterval after) {
    NSString *type = job[@"type"];
    if ([type isEqualToString:@"once"]) {
        NSTimeInterval at = [job[@"at"] doubleValue];
        return (at > after) ? at : 0;
    }
    if ([type isEqualToString:@"interval"]) {
        int mins = [job[@"interval_minutes"] intValue];
        if (mins < 1) mins = 1;
        return after + mins * 60.0;
    }
    if ([type isEqualToString:@"daily"]) {
        int h = [job[@"hour"] intValue];
        int m = [job[@"minute"] intValue];
        NSCalendar *cal = [NSCalendar currentCalendar];
        NSDate *afterDate = [NSDate dateWithTimeIntervalSince1970:after];
        NSDateComponents *comps = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay
                                         fromDate:afterDate];
        comps.hour = h;
        comps.minute = m;
        comps.second = 0;
        NSDate *candidate = [cal dateFromComponents:comps];
        if ([candidate timeIntervalSince1970] <= after) {
            candidate = [candidate dateByAddingTimeInterval:86400];
        }
        return [candidate timeIntervalSince1970];
    }
    return 0;
}

static void run_script_file(NSString *script_name) {
    NSString *path = [g_scripts_dir stringByAppendingPathComponent:script_name];
    NSString *code = [NSString stringWithContentsOfFile:path
                                               encoding:NSUTF8StringEncoding error:nil];
    if (!code.length) {
        log_warn("scheduler: script file not found: %s", script_name.UTF8String);
        return;
    }
    log_info("scheduler: running %s", script_name.UTF8String);
    script_run(-1, "scheduler", code.UTF8String);
}

static void tick(void) {
    ensure_queue();
    dispatch_async(g_queue, ^{
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        BOOL changed = NO;
        for (NSUInteger i = 0; i < g_jobs.count; i++) {
            NSMutableDictionary *job = [g_jobs[i] mutableCopy];
            if (![job[@"enabled"] boolValue]) continue;
            NSTimeInterval next = [job[@"next_run"] doubleValue];
            if (next <= 0 || next > now) continue;

            run_script_file(job[@"script"]);
            job[@"last_run"] = @(now);

            if ([job[@"type"] isEqualToString:@"once"]) {
                job[@"enabled"] = @NO;
                job[@"next_run"] = @0;
            } else {
                job[@"next_run"] = @(compute_next_run(job, now));
            }
            g_jobs[i] = job;
            changed = YES;
        }
        if (changed) save_jobs();
    });
}

void scheduler_start(const char *scripts_dir) {
    ensure_queue();
    g_scripts_dir = [NSString stringWithUTF8String:scripts_dir];
    dispatch_sync(g_queue, ^{ load_jobs(); });

    dispatch_async(dispatch_get_main_queue(), ^{
        g_timer = [NSTimer scheduledTimerWithTimeInterval:TICK_SECONDS
                                                  repeats:YES
                                                    block:^(NSTimer *t) { tick(); }];
        tick();
    });
}

NSArray *scheduler_list(void) {
    ensure_queue();
    __block NSArray *snap;
    dispatch_sync(g_queue, ^{ snap = g_jobs ? [g_jobs copy] : @[]; });
    return snap;
}

NSString *scheduler_add(NSDictionary *job) {
    NSString *script = job[@"script"];
    NSString *type   = job[@"type"];
    if (!script.length || !type.length) return nil;
    if (![type isEqualToString:@"once"] &&
        ![type isEqualToString:@"interval"] &&
        ![type isEqualToString:@"daily"]) return nil;

    NSString *jid = [[NSUUID UUID] UUIDString];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableDictionary *entry = [job mutableCopy];
    entry[@"id"]       = jid;
    entry[@"enabled"]  = @YES;
    entry[@"last_run"] = @0;
    entry[@"next_run"] = @(compute_next_run(entry, now));

    ensure_queue();
    dispatch_sync(g_queue, ^{
        [g_jobs addObject:entry];
        save_jobs();
    });
    return jid;
}

BOOL scheduler_delete(NSString *job_id) {
    if (!job_id.length) return NO;
    ensure_queue();
    __block BOOL ok = NO;
    dispatch_sync(g_queue, ^{
        NSUInteger idx = NSNotFound;
        for (NSUInteger i = 0; i < g_jobs.count; i++) {
            if ([g_jobs[i][@"id"] isEqualToString:job_id]) { idx = i; break; }
        }
        if (idx != NSNotFound) {
            [g_jobs removeObjectAtIndex:idx];
            save_jobs();
            ok = YES;
        }
    });
    return ok;
}

BOOL scheduler_toggle(NSString *job_id) {
    if (!job_id.length) return NO;
    ensure_queue();
    __block BOOL ok = NO;
    dispatch_sync(g_queue, ^{
        for (NSUInteger i = 0; i < g_jobs.count; i++) {
            NSMutableDictionary *job = [g_jobs[i] mutableCopy];
            if (![job[@"id"] isEqualToString:job_id]) continue;
            BOOL was = [job[@"enabled"] boolValue];
            job[@"enabled"] = @(!was);
            if (!was) {
                NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
                job[@"next_run"] = @(compute_next_run(job, now));
            }
            g_jobs[i] = job;
            save_jobs();
            ok = YES;
            break;
        }
    });
    return ok;
}
