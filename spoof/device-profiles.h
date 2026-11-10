#pragma once
#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString * const DeviceProfilesErrorDomain;

// Named snapshots of this project's complete Device config, not application
// containers/keychains or profiles belonging to another product.
@interface DeviceProfiles : NSObject
+ (NSArray<NSString *> *)namesWithError:(NSError **)error;
+ (BOOL)saveCurrentAs:(NSString *)name error:(NSError **)error;
+ (BOOL)applyNamed:(NSString *)name error:(NSError **)error;
+ (BOOL)deleteNamed:(NSString *)name error:(NSError **)error;
+ (BOOL)renameNamed:(NSString *)name to:(NSString *)newName error:(NSError **)error;
@end
