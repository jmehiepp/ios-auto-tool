#pragma once
#import <Foundation/Foundation.h>
NSString *iat_resource_path(NSString *relative);
NSString *iat_data_directory(void);
NSString *iat_temporary_directory(void);
NSString *iat_create_temporary_file(void);
NSString *iat_access_token(void);
void iat_prepare_storage(void);
