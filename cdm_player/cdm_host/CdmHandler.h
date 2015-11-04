#pragma once

// Methods called from the c++ CdmHost object to the objective-c wrapper class.
// These functions must be called async on the main thread.
@protocol iOSCdmHandler <NSObject>

// Occurs after a cdm->CreateSession() call.
- (void)onSessionCreated:(uint32_t)sessionId webId:(NSString *)webId;

// A request from the iOSCdmHost to fetch the
// license data with |data| as the http body.
// If |destinationUrl| is not an empty string (@"") or nil, handler should
// fetch license through that |destinationUrl| (in case of sending a heartbeat).
- (void)onSessionMessage:(uint32_t)sessionId
         requestWithData:(NSData *)data
                   toURL:(NSString *)destinationUrl
         completionBlock:(void(^)(NSData *, NSError *))completionBlock;


// Used to indicate that the license cert has been
// successfully added to the |sessionId|.
- (void)onSessionUpdated:(uint32_t)sessionId;

- (void)onSessionClosed:(uint32_t)sessionId;

- (void)onSessionFailed:(uint32_t)sessionId error:(NSError *)error;

// File Handling
- (NSData *)readFile:(NSString *)fileName;
- (void)writeData:(NSData *)data file:(NSString *)fileName;

@end
