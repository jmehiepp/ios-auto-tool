#pragma once
#import <Foundation/Foundation.h>

typedef struct {
    int    slot;
    char   name[128];
    double saved_at;  // Unix timestamp
} AccountSlot;

// Returns container data directory for the app. Returns nil if not found.
NSString *get_container_path(NSString *bundle_id);

const char *account_last_error(void); // thread-local; copy before the next account call
BOOL account_valid_slot(int slot);   // 1...9999
BOOL save_account(const char *bundle_id, int slot);
BOOL switch_account(const char *bundle_id, int slot);
BOOL delete_account(const char *bundle_id, int slot);
BOOL name_account(const char *bundle_id, int slot, const char *label);

// Returns heap-allocated array; caller frees. count=-1 on error, 0 if empty.
AccountSlot *list_accounts(const char *bundle_id, int *count);

// Explicit opt-in only: generic service==bundle_id and internet server==bundle_id,
// limited to the daemon's keychain access groups. Never called by save/switch.
BOOL clear_keychain_for_app(const char *bundle_id);
