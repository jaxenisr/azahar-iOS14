#import "AZExceptionGuard.h"

static NSString *AZLogFilePath(void) {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                    NSUserDomainMask,
                                                                    YES);
    NSString *documents = paths.firstObject;
    if (documents.length == 0) {
        return nil;
    }
    NSString *directory = [documents stringByAppendingPathComponent:@"Azahar/log"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:NULL];
    return [directory stringByAppendingPathComponent:@"frontend-crash.log"];
}

static void AZAppendLogLine(NSString *line) {
    NSString *path = AZLogFilePath();
    if (path.length == 0) {
        return;
    }
    NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        return;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (handle == nil) {
        [data writeToFile:path atomically:YES];
        return;
    }

    @try {
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    } @catch (NSException *exception) {
        // The log is a convenience; failing to write it must not fail anything else.
    }
}

NSDictionary<NSString *, NSString *> *AZTryCatch(void (^block)(void)) {
    @try {
        if (block != nil) {
            block();
        }
        return nil;
    } @catch (NSException *exception) {
        NSArray<NSString *> *stack = exception.callStackSymbols ?: @[];
        NSUInteger count = MIN((NSUInteger)8, stack.count);
        NSString *frames = [[stack subarrayWithRange:NSMakeRange(0, count)] componentsJoinedByString:@" | "];
        return @{
            @"name": exception.name ?: @"NSException",
            @"reason": exception.reason ?: @"no reason given",
            @"callStack": frames,
        };
    }
}

static void AZUncaughtExceptionHandler(NSException *exception) {
    NSString *line = [NSString stringWithFormat:@"uncaught %@: %@ — %@",
                      exception.name ?: @"exception",
                      exception.reason ?: @"no reason given",
                      (exception.callStackSymbols ?: @[]).firstObject ?: @""];
    NSLog(@"[Azahar] %@", line);
    AZAppendLogLine(line);
}

void AZInstallExceptionHandler(void) {
    NSSetUncaughtExceptionHandler(&AZUncaughtExceptionHandler);
}
