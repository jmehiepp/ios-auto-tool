#pragma once
#import <Foundation/Foundation.h>
NSString *iat_resource_path(NSString *relative);
NSString *iat_data_directory(void);
NSString *iat_access_token(void);
void iat_prepare_storage(void);
