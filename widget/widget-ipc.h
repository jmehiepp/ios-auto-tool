#pragma once
#import <Foundation/Foundation.h>

// Synchronous; call on a background queue. Accepts a saved basename, never code/path.
BOOL widget_ipc_valid_script_name(NSString *name);
NSDictionary *widget_ipc_request(NSString *action, NSString *name, NSError **error);
BOOL widget_ipc_run_script(NSString *name);
BOOL widget_ipc_stop_script(void);
