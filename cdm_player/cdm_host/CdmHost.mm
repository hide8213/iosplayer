#include "CdmHost.h"
#include "CdmIncludes.h"
#include "CdmWrapper.h"
#include "iOSDeviceCert.h"

using widevine::Cdm;

// Default values for testing content. Can be modified dynamically or here.
static int kLoopTimer = 1000.0;

@interface NSString (StdStringHelpers)
+ (NSString*)stringWithStdString:(const std::string&)str;
- (std::string)stdString;
@end

@implementation NSString (StdStringHelpers)
+ (NSString*)stringWithStdString:(const std::string&)str {
  return [[NSString alloc] initWithBytes:str.c_str()
                                  length:str.length()
                                encoding:NSUTF8StringEncoding];
}

- (std::string)stdString {
  std::string ret([self UTF8String],
      [self lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
  return ret;
}
@end

namespace {

static NSString *kCertFilename = @"cert.bin";

// Creates an NSError object from the given Status
NSError* GetErrorFromStatus(Cdm::Status status, NSString *desc) {
  if (status == Cdm::kSuccess) {
    return nil;
  } else {
    NSMutableDictionary* details = [NSMutableDictionary dictionary];
    [details setValue:desc forKey:NSLocalizedDescriptionKey];
    return [NSError errorWithDomain:@"cdm" code:status userInfo:details];
  }
}

}  // namespace

iOSCdmHost::iOSCdmHost()
: cdm_(NULL), timers_([[NSMutableDictionary alloc] init]) {}

NSError* iOSCdmHost::Initialize(const Cdm::ClientInfo& clientInfo,
    Cdm::LogLevel verbosity) {
  iOSCdmHandler_ = NULL;

  Cdm::DeviceCertificateRequest request;
  Cdm::Status ret = Cdm::initialize(
      Cdm::kNoSecureOutput, clientInfo, this, this, this,
      &request, verbosity);
  if (ret != Cdm::kSuccess) {
    return GetErrorFromStatus(ret, @"Error initializing the CDM.");
  }
  if (request.needed) {
    return GetErrorFromStatus(Cdm::kUnexpectedError,
        @"Error initializing the CDM.");
  }

  cdm_ = Cdm::create(this, true /* privacy_mode */);
  return nil;
}

void iOSCdmHost::Deinitialize() {
  if (cdm_) {
    delete cdm_;
    cdm_ = NULL;
  }
}

void iOSCdmHost::SetiOSCdmHandler(id<iOSCdmHandler> handler) {
  assert((!iOSCdmHandler_ || !handler) &&
         "iOSCdmHost::setCdmHandler cdmHandler already exists.");
  iOSCdmHandler_ = handler;
}

NSError *iOSCdmHost::CreateSession(Cdm::SessionType sessionType,
                                   NSString **sessionIdStr) {
  std::string sessionId;
  Cdm::Status code = cdm_->createSession(sessionType, &sessionId);
  if (code != Cdm::kSuccess) {
    return GetErrorFromStatus(code, @"Error creating session.");
  }
  *sessionIdStr = [NSString stringWithStdString:sessionId];
  return nil;
}

NSError *iOSCdmHost::GetLicenseInfo(NSString *sessionId, int64_t *expiration) {
  int64_t expirationData;
  Cdm::Status cdmStatus =
      cdm_->getExpiration([sessionId stdString], &expirationData);
  if (cdmStatus != Cdm::kSuccess) {
    return GetErrorFromStatus(cdmStatus, @"Error Getting Expiration.");
  }
  if (expirationData > 0) {
    *expiration = expirationData;
  } else {
    *expiration = 0;
    NSLog(@"::INFO::No Expiration Data found");
  }
  widevine::Cdm::KeyStatusMap map;
  cdmStatus = cdm_->getKeyStatuses([sessionId stdString], &map);
  if (cdmStatus != Cdm::kSuccess) {
    return GetErrorFromStatus(cdmStatus, @"Error Getting Key Status.");
  }
  widevine::Cdm::KeyStatus keyStatus = map.begin()->second;
  if (!(keyStatus == widevine::Cdm::KeyStatus::kUsable)) {
    NSLog(@"::ERROR::License Status: %u", map.begin()->second);
    return GetErrorFromStatus(cdmStatus, @"License Error.");
  }
  NSLog(@"::INFO::License Status is Valid (Usable)");
  return nil;
}

NSError *iOSCdmHost::LoadSession(NSString *sessionId) {
  return GetErrorFromStatus(cdm_->load([sessionId stdString]),
      @"Error loading session.");
}

NSError *iOSCdmHost::RemoveSession(NSString *sessionId) {
  return GetErrorFromStatus(cdm_->remove([sessionId stdString]),
      @"Error removing session.");
}

void iOSCdmHost::CloseSessions(NSArray *sessionIds) {
  for (NSString *sessionId in sessionIds) {
    cdm_->close([sessionId stdString]);
  }
}

NSData* iOSCdmHost::Decrypt(NSData *encrypted, NSData *key_id, NSData *iv) {
  Cdm::InputBuffer input;
  input.data = reinterpret_cast<const uint8_t*>([encrypted bytes]);
  input.data_length = (uint32_t)[encrypted length];
  input.key_id = reinterpret_cast<const uint8_t*>([key_id bytes]);
  input.key_id_length = (uint32_t)[key_id length];
  input.iv = reinterpret_cast<const uint8_t*>([iv bytes]);
  input.iv_length = (uint32_t)[iv length];
  input.block_offset = 0;

  Cdm::OutputBuffer decrypted;
  decrypted.data = (uint8_t*)malloc(sizeof(uint8_t) * input.data_length);
  decrypted.data_length = input.data_length;
  if (cdm_->decrypt(input, decrypted)) {
    return nil;
  }
  return [NSData dataWithBytesNoCopy:decrypted.data
                              length:decrypted.data_length];
}

NSError *iOSCdmHost::GenerateRequest(NSString *sessionId, NSData *initData) {
  std::string sessionStr = [sessionId stdString];
  std::string strData(
      reinterpret_cast<const char*>([initData bytes]), [initData length]);
  return GetErrorFromStatus(
      cdm_->generateRequest(sessionStr, Cdm::kCenc, strData),
      @"Error generating the request.");
}

void iOSCdmHost::setTimeout(int64_t delay_ms,
                            Cdm::ITimer::IClient* client,
                            void* context) {
  NSValue* clientValue = [NSValue valueWithPointer:client];
  __weak NSMutableDictionary* weakTimers = timers_;
  CFRunLoopTimerRef timer = CFRunLoopTimerCreateWithHandler(
      NULL,
      CFAbsoluteTimeGetCurrent() + static_cast<uint32_t>(delay_ms) / kLoopTimer,
      0,
      0,
      0,
      ^(CFRunLoopTimerRef runloop_timer) {
        NSValue* timerValue = [NSValue valueWithPointer:runloop_timer];
        client->onTimerExpired(context);
        [[weakTimers objectForKey:clientValue] removeObject:timerValue];
        CFRelease(runloop_timer);
      });
  CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopCommonModes);

  NSValue* timerValue = [NSValue valueWithPointer:timer];
  NSMutableArray* array = [timers_ objectForKey:clientValue];
  if (!array) {
    array = [[NSMutableArray alloc] init];
    [timers_ setObject:array forKey:clientValue];
  }

  [array addObject:timerValue];
}

void iOSCdmHost::cancel(Cdm::ITimer::IClient* client) {
  NSValue* clientValue = [NSValue valueWithPointer:client];
  NSMutableArray* array = [timers_ objectForKey:clientValue];
  for (NSValue* value in array) {
    CFRunLoopTimerRef timer = reinterpret_cast<CFRunLoopTimerRef>(
        [value pointerValue]);
    CFRunLoopRemoveTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopCommonModes);
  }
  [array removeAllObjects];
}

int64_t iOSCdmHost::now() {
  // NSDate uses seconds, convert to match CDM (milliseconds).
  return [[NSDate date] timeIntervalSince1970] * 1000;
}

void iOSCdmHost::onMessage(
    const std::string& session_id,
    Cdm::MessageType type,
    const std::string& message) {
  std::string local_session_id = session_id;
  NSString *sessionIdStr = [NSString stringWithStdString:session_id];
    [sessionIdStr stringByAppendingString:@"license"];
  NSData *messageData = [NSData dataWithBytes:message.c_str()
                                       length:message.length()];

  id block = ^(NSData *data, NSError *error) {
    if (!error) {
      std::string result(reinterpret_cast<const char*>([data bytes]),
                         [data length]);
      cdm_->update(local_session_id, result);
      if (type != Cdm::kIndividualizationRequest) {
        [iOSCdmHandler_ onSessionUpdated:sessionIdStr];
      }
    } else {
      [iOSCdmHandler_ onSessionFailed:sessionIdStr error:error];
    }
  };

  [iOSCdmHandler_ onSessionMessage:messageData
                         sessionId:sessionIdStr
                   completionBlock:block];
}

void iOSCdmHost::onKeyStatusesChange(const std::string& session_id) {}

void iOSCdmHost::onRemoveComplete(const std::string& session_id) {}

bool iOSCdmHost::read(const std::string& name, std::string* data) {
  NSString *nameStr = [NSString stringWithStdString:name];
  if ([nameStr isEqualToString:kCertFilename]) {
    data->assign(reinterpret_cast<const char*>(kDeviceCert), kDeviceCertSize);
    return true;
  }

  NSData *output = [iOSCdmHandler_ readFile:nameStr];
  if (!output ) {
    return false;
  }

  *data = std::string(reinterpret_cast<const char*>([output bytes]),
                      [output length]);
  return true;
}

bool iOSCdmHost::write(const std::string& name, const std::string& data) {
  NSString *nameStr = [NSString stringWithStdString:name];
  if ([nameStr isEqualToString:kCertFilename]) {
    return false;
  }

  NSData *dataObj = [NSData dataWithBytes:data.c_str()
                                   length:data.length()];
  return [iOSCdmHandler_ writeFile:dataObj file:nameStr];
}

bool iOSCdmHost::exists(const std::string& name) {
  NSString *nameStr = [NSString stringWithStdString:name];
  if ([nameStr isEqualToString:kCertFilename]) {
    return true;
  }

  return [iOSCdmHandler_ fileExists:nameStr];
}

bool iOSCdmHost::remove(const std::string& name) {
  NSString *nameStr = [NSString stringWithStdString:name];
  if ([nameStr isEqualToString:kCertFilename]) {
    return false;
  }
  return [iOSCdmHandler_ removeFile:nameStr];
}

int32_t iOSCdmHost::size(const std::string& name) {
  NSString *nameStr = [NSString stringWithStdString:name];
  if ([nameStr isEqualToString:kCertFilename]) {
    return static_cast<int32_t>(kDeviceCertSize);
  }

  return [iOSCdmHandler_ fileSize:nameStr];
}
