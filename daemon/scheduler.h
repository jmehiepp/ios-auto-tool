#pragma once
#import <Foundation/Foundation.h>

void scheduler_start(const char *scripts_dir);
NSArray *scheduler_list(void);
NSString *scheduler_add(NSDictionary *job);
BOOL scheduler_delete(NSString *job_id);
BOOL scheduler_toggle(NSString *job_id);
