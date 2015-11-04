#import <Foundation/Foundation.h>

@class iOSCdm;

extern NSString *const kiOSCdmError;

@protocol iOSCdmDelegate <NSObject>
// Returns the dispatch_queue the delegate desires to be called back on.
- (dispatch_queue_t)iOSCdmDispatchQueue:(iOSCdm *)iOSCdm;

// Called from the CDM back to the host delegate.
// The host delegate must call it's license server
// with the |data| in the HTTP body and call |completionBlock| with the results.
- (void)iOSCdm:(iOSCdm *)iOSCdm
    fetchLicenseWithData:(NSData *)data
         completionBlock:(void(^)(NSData *, NSError *))completionBlock;

@optional
// Called from the CDM back to the host delegate.
// This API is more general and gives the delegate richer information than
// iOSCdm:fetchLicenseWithData:completionBlock:. It can be used to fetch license,
// send heartbeat, renew license and release license.
// The host delegate must call to either the given |destinationUrl| or its license
// server URL (if |destinationUrl| is nil) with the |data| in the HTTP body and call
// |completionBlock| with the results.
- (void)iOSCdm:(iOSCdm *)iOSCdm
           sendData:(NSData *)data
            offline:(BOOL)isOffline
              toURL:(NSString *)destinationUrl
    completionBlock:(void (^)(NSData *, NSError *))completionBlock;

// Called when a session is created.  The |webId| can be stored and associated
// with the |pssh|.  Future sessions will call webSessionForPssh with the same
// |pssh|.
- (void)onSessionCreatedWithPssh:(NSData *)pssh webId:(NSString *)webId;

// Reads a file saved with writeData.
- (NSData *)readFile:(NSString *)fileName;

// Asks the application to save |data| to |fileName| to persist it for a later
// invokation of the application.
- (void)writeData:(NSData *)data file:(NSString *)fileName;

// Gets the webId previously stored in onSessionCreatedWithPssh:webId:.  Should
// return nil if no webId exists for that |pssh|.
- (NSString *)webSessionForPssh:(NSData *)pssh;
@end

// This class is the ObjectiveC wrapper around the C++ interface.
// Its responsible for tracking
// whether or not the psshKey has been added to the CDM.
@interface iOSCdm : NSObject
// Returns an instance of WvCdmIos.
+ (iOSCdm *)sharedInstance;
- (void)setupCdmWithDelegate:(id<iOSCdmDelegate>)delegate;
- (void)shutdownCdm;

// Begin/Ends playback session.
// This frees any allocated resources that were created
// for the current playback session.
- (void)beginPlaybackWithDelegate:(id<iOSCdmDelegate>)delegate __attribute__((deprecated));
- (void)endPlayback __attribute__((deprecated));

// Given a |psshKey|, |completionBlock| will be called
// once the license data has been added.
- (void)processPsshKey:(NSData *)psshKey
              mimeType:(NSString *)mimeType
          isOfflineVod:(BOOL)isOfflineVod
       completionBlock:(void(^)(NSError *))completionBlock;

// The offline license for |psshKey| will be removed and
// then call the |completionBlock|.
- (void)removeOfflineLicenseForPsshKey:(NSData *)psshKey
                       completionBlock:(void(^)(NSError *))completionBlock;

// Decrypts the sepcified |encrypted| data with |keyId| and |iv|.
- (NSData *)decrypt:(NSData *)encrypted keyId:(NSData *)keyId IV:(NSData *)iv;

// iOSCdmHandler methods forwarded to the iOSCdmDelegate.
- (NSData *)readFile:(NSString *)fileName;
- (void)writeData:(NSData *)data file:(NSString *)fileName;
- (void)onSessionCreated:(uint32_t)sessionId webId:(NSString *)webId;

@end
