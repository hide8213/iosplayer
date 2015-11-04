#include "CdmHost.h"
#include "CdmIncludes.h"
#include "CdmWrapper.h"
#include "iOSDeviceCert.h"

using cdm::Buffer;
using cdm::MediaKeyError;

// Default values for testing content. Can be modified dynamically or here.
static int kNumSamples = 1;
static int kTimeStamp = 10;
static int kLoopTimer = 1000.0;

static const char kWidevineKeySystem[] = "com.widevine.alpha";

iOSCdmHost iOSCdmHost::s_host;

namespace {
  NSString *kCertFilename = @"cert.bin";

  void* host_callback(int host_interface_version, void* user_data) {
    if (host_interface_version == cdm::Host_4::kVersion) {
      return iOSCdmHost::GetHost();
    } else {
      return NULL;
    }
  }
}

void iOSCdmHost::Initialize() {
  iOSCdmHandler_ = NULL;
  INITIALIZE_CDM_MODULE();
  cdm_ = reinterpret_cast<cdm::ContentDecryptionModule_4*>(
      CreateCdmInstance(cdm::ContentDecryptionModule_4::kVersion,
      kWidevineKeySystem,
      static_cast<uint32_t>(strlen(kWidevineKeySystem)), host_callback, 0));
}

void iOSCdmHost::Deinitialize() {
  cdm_->Destroy();
  DeinitializeCdmModule();
}

void iOSCdmHost::SetiOSCdmHandler(id<iOSCdmHandler> handler) {
  assert((!iOSCdmHandler_ || !handler) &&
         "iOSCdmHost::setCdmHandler cdmHandler already exists.");
  iOSCdmHandler_ = handler;
}

void iOSCdmHost::CreateSession(uint32_t sessionId,
                               NSString *mimeType,
                               NSData* pssh,
                               cdm::SessionType sessionType) {
  cdm_->CreateSession(sessionId,
                      [mimeType UTF8String],
                      (uint32_t)[mimeType length],
                      reinterpret_cast<const uint8_t*>([pssh bytes]),
                      (uint32_t)[pssh length],
                      sessionType);
}

void iOSCdmHost::LoadSession(uint32_t sessionId,
                             NSString *webSessionId) {
  cdm_->LoadSession(sessionId, [webSessionId UTF8String],
                    static_cast<uint32_t>([webSessionId length]));
}

void iOSCdmHost::RemoveSession(uint32_t sessionId,
                               NSString *webSessionId) {
  cdm_->RemoveSession(sessionId, [webSessionId UTF8String],
                      static_cast<uint32_t>([webSessionId length]));
}

void iOSCdmHost::CloseSessions(NSArray *sessionIds) {
  for (NSNumber *sessionId in sessionIds) {
    cdm_->ReleaseSession((uint32_t)sessionId.integerValue);
  }
}

NSData* iOSCdmHost::Decrypt(NSData *encrypted, NSData *key_id, NSData *iv) {
  cdm::InputBuffer input;
  input.data = reinterpret_cast<const uint8_t*>([encrypted bytes]);
  input.data_size = (uint32_t)[encrypted length];
  input.key_id = reinterpret_cast<const uint8_t*>([key_id bytes]);
  input.key_id_size = (uint32_t)[key_id length];
  input.iv = reinterpret_cast<const uint8_t*>([iv bytes]);
  input.iv_size = (uint32_t)[iv length];
  input.data_offset = 0;
  cdm::SubsampleEntry sub(0, static_cast<uint32_t>([encrypted length]));
  input.subsamples = &sub;
  input.num_subsamples = kNumSamples;
  input.timestamp = kTimeStamp;
  DecryptedBlock decrypted;
  cdm_->Decrypt(input, &decrypted);
  return [NSData dataWithBytes:decrypted.DecryptedBuffer()->Data()
                        length:decrypted.DecryptedBuffer()->Size()];
}

Buffer* iOSCdmHost::Allocate(uint32_t capacity) {
  return new MediaBuffer(capacity);
}

struct iOSCdmHostTimerInfo {
  void* context_;
  iOSCdmHost* host_;
};

void iOSCdmHost::SetTimer(int64_t delay_ms, void* context) {
  CFRunLoopTimerRef timer = CFRunLoopTimerCreateWithHandler(
      NULL,
      CFAbsoluteTimeGetCurrent() + static_cast<uint32_t>(delay_ms) / kLoopTimer,
      0,
      0,
      0,
      ^(CFRunLoopTimerRef runloop_timer) {
        cdm_->TimerExpired(context);
        CFRelease(runloop_timer);
      });
  CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopCommonModes);
}

double iOSCdmHost::GetCurrentWallTimeInSeconds() {
  return [[NSDate date] timeIntervalSince1970];
}

void iOSCdmHost::OnSessionCreated(uint32_t session_id,
                                  const char* web_session_id,
                                  uint32_t web_session_id_length) {
  [iOSCdmHandler_ onSessionCreated:session_id webId:[NSString stringWithUTF8String:web_session_id]];
}

void iOSCdmHost::OnSessionMessage(
    uint32_t session_id,
    const char* message, uint32_t message_length,
    const char* destination_url, uint32_t destination_url_length) {

  NSString *requestURL = [[NSString alloc] initWithBytes:destination_url
                                                  length:destination_url_length
                                                encoding:NSUTF8StringEncoding];
  NSData *requestData = [NSData dataWithBytes:message length:message_length];

  id block = ^(NSData *data, NSError *error) {
    if (!error) {
      cdm_->UpdateSession(session_id,
                          reinterpret_cast<const uint8_t*>([data bytes]),
                          (uint32_t)data.length);
    } else {
      [iOSCdmHandler_ onSessionFailed:session_id error:error];
    }
  };

  [iOSCdmHandler_ onSessionMessage:session_id
                   requestWithData:requestData
                             toURL:requestURL
                   completionBlock:block];
}

void iOSCdmHost::OnSessionUpdated(uint32_t session_id) {
  [iOSCdmHandler_ onSessionUpdated:session_id];
}

void iOSCdmHost::OnSessionClosed(uint32_t session_id) {
  [iOSCdmHandler_ onSessionClosed:session_id];
}

void iOSCdmHost::OnSessionError(uint32_t session_id,
                                cdm::Status error_code,
                                uint32_t system_code) {
  NSDictionary *userInfo = @{@"session_id" : @(session_id),
                             @"error_code" : @(error_code),
                             @"system_code" : @(system_code),
                             };
  NSError *error = [NSError errorWithDomain:kiOSCdmError
                                       code:error_code
                                   userInfo:userInfo];
  [iOSCdmHandler_ onSessionFailed:session_id error:error];
}

void iOSCdmHost_FileIO::Open(const char* file_name, uint32_t file_name_size) {
  file_name_ = [NSString stringWithUTF8String:file_name];
  client_->OnOpenComplete(cdm::FileIOClient::kSuccess);
}

void iOSCdmHost_FileIO::Read() {
  if ([file_name_ isEqualToString:kCertFilename]) {
    client_->OnReadComplete(cdm::FileIOClient::kSuccess, kDeviceCert,
                            static_cast<uint32_t>(kDeviceCertSize));
    return;
  }
  if (![iOSCdmHandler_ respondsToSelector:@selector(readFile:)]) {
    return;
  }

  NSData *data = [iOSCdmHandler_ readFile:file_name_];
  if (!data) {
    client_->OnReadComplete(cdm::FileIOClient::kError, nullptr, 0);
  } else {
    client_->OnReadComplete(cdm::FileIOClient::kSuccess,
                            reinterpret_cast<const uint8_t *>([data bytes]),
                            static_cast<uint32_t>([data length]));
  }
}

void iOSCdmHost_FileIO::Write(const uint8_t* data, uint32_t data_size) {
  if (![iOSCdmHandler_ respondsToSelector:@selector(writeData:file:)]) {
    return;
  }
  [iOSCdmHandler_ writeData:[NSData dataWithBytes:data length:data_size] file:file_name_];
  client_->OnWriteComplete(cdm::FileIOClient::kSuccess);
}

void iOSCdmHost_FileIO::Close() {
  delete this;
}

cdm::FileIO* iOSCdmHost::CreateFileIO(cdm::FileIOClient* client) {
  return new iOSCdmHost_FileIO(client, iOSCdmHandler_);
}
