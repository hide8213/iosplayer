#pragma once

// Methods called from the c++ CdmHost object to the objective-c wrapper class.
// These functions must be called async on the main thread.
@protocol iOSCdmHandler <NSObject>

// A request from the iOSCdmHost to fetch the license data with |message| as
// the http body.
- (void)onSessionMessage:(NSData *)data
               sessionId:(NSString *)sessionId
         completionBlock:(void (^)(NSData *, NSError *))completionBlock;

// Used to indicate that the license cert has been successfully added to the
// |sessionId|.
- (void)onSessionUpdated:(NSString *)sessionId;

- (void)onSessionFailed:(NSString *)sessionId error:(NSError *)error;

// File Handling
- (NSData *)readFile:(NSString *)fileName;
- (BOOL)writeFile:(NSData *)data file:(NSString *)fileName;
- (BOOL)fileExists:(NSString *)fileName;
- (int32_t)fileSize:(NSString *)fileName;
- (BOOL)removeFile:(NSString *)fileName;

@end
