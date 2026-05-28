#pragma once
#import <Foundation/Foundation.h>

typedef struct {
    int    slot;
    char   name[128];
    double saved_at;  // Unix timestamp
} AccountSlot;

// Returns container data directory for the app. Returns nil if not found.
NSString *get_container_path(NSString *bundle_id);

void save_account(const char *bundle_id, int slot);
void switch_account(const char *bundle_id, int slot);
void delete_account(const char *bundle_id, int slot);
void name_account(const char *bundle_id, int slot, const char *label);

// Returns heap-allocated array; caller frees. count set to length.
AccountSlot *list_accounts(const char *bundle_id, int *count);

// Clear Keychain entries stored under bundle_id service
void clear_keychain_for_app(const char *bundle_id);
