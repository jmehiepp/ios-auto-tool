#import "../device-profiles.h"
#import "../spoof-config.h"
#import "../../daemon/runtime-paths.h"
#import <Foundation/Foundation.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

// The only fixture is the data-directory provider. Both production profile and
// SpoofConfig implementations use real temporary files; no filesystem is mocked.
NSString *iat_data_directory(void) {
    const char *value=getenv("IAT_DATA_DIR");
    return value ? [NSString stringWithUTF8String:value] : nil;
}
static void Check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr,"FAIL: %s\n",message); exit(1); }
}
static NSDictionary *Config(NSString *deviceName, BOOL enabled) {
    return @{@"enabled":@(enabled),@"selectedApps":@[@"com.example.DeviceProbe"],
             @"modules":@{@"device_name":@{@"enabled":@YES,@"value":deviceName}}};
}
static void WriteFile(NSString *path, id plist) {
    NSError *error=nil;
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:plist
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    Check(data && [data writeToFile:path options:NSDataWritingAtomic error:&error],"write manual test profile");
    Check(chmod(path.fileSystemRepresentation,0600)==0,"set manual profile permissions");
}
int main(void) {
    @autoreleasepool {
        NSString *base=iat_data_directory();
        Check([base containsString:@"iosautotool-device-test."],"isolated IAT_DATA_DIR required");
        Check([SPOOF_CONFIG_PATH containsString:@"iosautotool-device-test."],"isolated config required");
        Check([SPOOF_FILTER_PATH containsString:@"iosautotool-device-test."],"isolated filter required");
        NSString *directory=[base stringByAppendingPathComponent:@"device-profiles"];
        NSString *work=[directory stringByAppendingPathComponent:@"Work.plist"];
        NSError *error=nil;
        SpoofConfig *config=SpoofConfig.shared;
        Check([config setConfiguration:Config(@"Saved Phone",YES) error:&error],"stage real device config");
        Check([[DeviceProfiles namesWithError:&error] isEqual:@[]],"empty list creates secure storage");
        struct stat info;
        Check(lstat(directory.fileSystemRepresentation,&info)==0 && (info.st_mode&0777)==0700,
              "profile directory mode 0700");
        Check([DeviceProfiles saveCurrentAs:@"Work" error:&error],"save full current config");
        Check(lstat(work.fileSystemRepresentation,&info)==0 && (info.st_mode&0777)==0600,
              "profile mode 0600");
        Check(info.st_size>0 && info.st_size<=256*1024,"profile byte bound");
        Check([[DeviceProfiles namesWithError:&error] isEqual:@[@"Work"]],"list saved name");
        NSData *saved=[NSData dataWithContentsOfFile:work];
        NSDictionary *roundtrip=[NSPropertyListSerialization propertyListWithData:saved
            options:NSPropertyListImmutable format:NULL error:&error];
        Check([roundtrip isEqual:Config(@"Saved Phone",YES)],"full schema plist roundtrip");
        Check([config setConfiguration:Config(@"Different Phone",NO) error:&error],"change real config before restore");
        [config reload];
        Check([DeviceProfiles applyNamed:@"Work" error:&error],"apply saved config through real commit");
        [config reload];
        Check([config.getAll isEqual:Config(@"Saved Phone",YES)],"apply restores master, apps and module values");
        NSDictionary *filter=[NSDictionary dictionaryWithContentsOfFile:SPOOF_FILTER_PATH];
        Check([filter[@"Filter"][@"Bundles"] isEqual:@[@"com.example.DeviceProbe"]],"apply also refreshes actual filter");

        NSString *tooLong=[@"a" stringByPaddingToLength:65 withString:@"a" startingAtIndex:0];
        for (NSString *name in @[@"",@"../escape",@"/absolute",@"with/slash",@"with\\slash",@"with space",@"x.plist",@"_hidden",@"tên",tooLong]) {
            error=nil;
            Check(![DeviceProfiles saveCurrentAs:name error:&error] && error,"reject unsafe profile name with error");
            error=nil;
            Check(![DeviceProfiles applyNamed:name error:&error] && error,"reject unsafe apply name");
            error=nil;
            Check(![DeviceProfiles deleteNamed:name error:&error] && error,"reject unsafe delete name");
        }
        error=nil;
        Check(![DeviceProfiles applyNamed:@"Missing" error:&error] && error,"missing profile read reports error");
        Check(![DeviceProfiles deleteNamed:@"Missing" error:&error] && error,"missing delete reports error");

        NSString *bad=[directory stringByAppendingPathComponent:@"Bad.plist"];
        WriteFile(bad,@{@"enabled":@YES,@"selectedApps":@[],@"modules":@{@"unknown":@{@"enabled":@YES}}});
        error=nil;
        Check(![DeviceProfiles applyNamed:@"Bad" error:&error] && error,"invalid schema rejected on load");
        Check([config.getAll isEqual:Config(@"Saved Phone",YES)],"failed schema load preserves current config");
        const unsigned char corruptBytes[]={0xff,0,0xfe,1};
        Check([[NSData dataWithBytes:corruptBytes length:sizeof(corruptBytes)] writeToFile:bad atomically:YES],
              "write unreadable plist format");
        chmod(bad.fileSystemRepresentation,0600);
        error=nil;
        Check(![DeviceProfiles applyNamed:@"Bad" error:&error] && error,"corrupt plist reports parse error");
        Check([DeviceProfiles deleteNamed:@"Bad" error:&error],"delete corrupt regular profile without applying it");

        NSString *large=[directory stringByAppendingPathComponent:@"Large.plist"];
        Check([[NSMutableData dataWithLength:256*1024+1] writeToFile:large atomically:YES],"write oversized file");
        chmod(large.fileSystemRepresentation,0600);
        error=nil;
        Check(![DeviceProfiles applyNamed:@"Large" error:&error] && error.code==EFBIG,"oversized read rejected before parse");
        Check([DeviceProfiles deleteNamed:@"Large" error:&error],"delete oversized owned regular file");

        NSString *external=[[base stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"external.plist"];
        WriteFile(external,Config(@"External",NO));
        NSData *externalBytes=[NSData dataWithContentsOfFile:external];
        NSString *symlinkPath=[directory stringByAppendingPathComponent:@"Linked.plist"];
        Check(symlink(external.fileSystemRepresentation,symlinkPath.fileSystemRepresentation)==0,"create profile symlink fixture");
        error=nil;
        Check(![DeviceProfiles applyNamed:@"Linked" error:&error] && error,"do not read profile symlink");
        error=nil;
        Check(![DeviceProfiles saveCurrentAs:@"Linked" error:&error] && error,"do not overwrite profile symlink");
        error=nil;
        Check(![DeviceProfiles deleteNamed:@"Linked" error:&error] && error,"do not delete profile symlink through named API");
        error=nil;
        Check([DeviceProfiles namesWithError:&error]==nil && error,"list reports symlink problem rather than silently skipping it");
        Check([[NSData dataWithContentsOfFile:external] isEqual:externalBytes],"external symlink target unchanged");
        Check(unlink(symlinkPath.fileSystemRepresentation)==0,"remove own symlink fixture");

        NSString *hardLink=[directory stringByAppendingPathComponent:@"HardLink.plist"];
        Check(link(external.fileSystemRepresentation,hardLink.fileSystemRepresentation)==0,"create hard-link fixture");
        error=nil;
        Check(![DeviceProfiles applyNamed:@"HardLink" error:&error] && error,"do not read hard-linked profile");
        error=nil;
        Check(![DeviceProfiles saveCurrentAs:@"HardLink" error:&error] && error,"do not overwrite hard-linked profile");
        Check(unlink(hardLink.fileSystemRepresentation)==0,"remove own hard-link fixture");
        NSString *fifo=[directory stringByAppendingPathComponent:@"Pipe.plist"];
        Check(mkfifo(fifo.fileSystemRepresentation,0600)==0,"create non-regular FIFO fixture");
        error=nil;
        Check(![DeviceProfiles applyNamed:@"Pipe" error:&error] && error,"reject FIFO without blocking read");
        Check(unlink(fifo.fileSystemRepresentation)==0,"remove own FIFO fixture");

        Check(chmod(work.fileSystemRepresentation,0644)==0,"make test file insecure");
        error=nil;
        Check(![DeviceProfiles applyNamed:@"Work" error:&error] && error,"reject insecure profile mode");
        chmod(work.fileSystemRepresentation,0600);
        NSString *backup=[base stringByAppendingPathComponent:@"profiles-backup"];
        Check(rename(directory.fileSystemRepresentation,backup.fileSystemRepresentation)==0,"move profile directory fixture");
        NSString *outside=[base stringByAppendingPathComponent:@"outside"];
        Check(mkdir(outside.fileSystemRepresentation,0700)==0,"create outside directory fixture");
        Check(symlink(outside.fileSystemRepresentation,directory.fileSystemRepresentation)==0,"create directory symlink fixture");
        error=nil;
        Check([DeviceProfiles namesWithError:&error]==nil && error,"refuse symlink storage directory");
        error=nil;
        Check(![DeviceProfiles saveCurrentAs:@"Escape" error:&error] && error,"refuse save through directory symlink");
        Check([NSFileManager.defaultManager contentsOfDirectoryAtPath:outside error:NULL].count==0,"symlink directory target untouched");
        Check(unlink(directory.fileSystemRepresentation)==0,"remove directory symlink fixture");
        Check(rename(backup.fileSystemRepresentation,directory.fileSystemRepresentation)==0,"restore own storage directory");

        // A valid in-memory config can serialize larger than the profile limit.
        // Saving it must reject without replacing an existing good profile.
        NSMutableArray *selected=[NSMutableArray array],*hidden=[NSMutableArray array];
        NSString *padding=[@"a" stringByPaddingToLength:230 withString:@"a" startingAtIndex:0];
        for (int i=0;i<1000;i++) {
            [selected addObject:[NSString stringWithFormat:@"com.selected.%@%03d",padding,i]];
            [hidden addObject:[NSString stringWithFormat:@"com.hidden.%@%03d",padding,i]];
        }
        NSDictionary *bigConfig=@{@"enabled":@NO,@"selectedApps":selected,
            @"modules":@{@"app_list":@{@"enabled":@YES,@"value":@{@"hide":hidden}}}};
        Check([config setConfiguration:bigConfig error:&error],"stage valid large config");
        error=nil;
        Check(![DeviceProfiles saveCurrentAs:@"Work" error:&error] && error.code==EFBIG,"bound serialized save size");
        Check([[NSData dataWithContentsOfFile:work] isEqual:saved],"oversized save preserves old profile atomically");
        Check([DeviceProfiles applyNamed:@"Work" error:&error],"restore valid profile after rejected oversized save");
        Check([DeviceProfiles deleteNamed:@"Work" error:&error],"delete saved profile");
        Check([[DeviceProfiles namesWithError:&error] isEqual:@[]],"list empty after delete");
        puts("Named Device profile IO tests passed");
    }
    return 0;
}
