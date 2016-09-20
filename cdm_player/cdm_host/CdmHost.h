// All CDM applications expect a Host interface, a singleton object custom
// for a platform.  The Host is a singleton used to to host specific stuff,
// in many cases to just make abstract classed concrete.  Some of this behavior
// only makes sense when it is understood that the cross platform library has
// to work with very strange hosts.
//
// The Host interface interaction with the C++ API for getting keys and
// decrypting to the point that combining the two into one class made more
// sense.
// External Reference Links:
// PSSH: http://www.w3.org/TR/encrypted-media/cenc-format.html#common-system
// Host Interface Reference: see content_decryption_module.h

#ifndef WIDEVINE_BASE_CDM_HOST_IOS_CDMHOST_H_
#define WIDEVINE_BASE_CDM_HOST_IOS_CDMHOST_H_

#include <dispatch/dispatch.h>
#include <map>

#include "CdmHandler.h"
#include "CdmIncludes.h"

// Wrapper for calls to the CDM.
class iOSCdmHost : public widevine::Cdm::IEventListener,
                   public widevine::Cdm::ITimer,
                   public widevine::Cdm::IClock,
                   public widevine::Cdm::IStorage {
 public:
  // API
  static iOSCdmHost* GetHost() {
    static dispatch_once_t token;
    static iOSCdmHost* s_host;
    dispatch_once(&token, ^{
      s_host = new iOSCdmHost;
    });
    return s_host;
  }

  iOSCdmHost();

  // Initalize/Deinitialize should be called once for the lifetime of the app.
  NSError *Initialize(const widevine::Cdm::ClientInfo &clientInfo,
                      widevine::Cdm::LogLevel verbosity);

  void Deinitialize();

  // Set the callback object to handle responses from the CDM. Since CdmHost
  // is a static class, seting the cdmHandler can overwrite the previous
  // handler.
  void SetiOSCdmHandler(id<iOSCdmHandler> handler);

  // Creates a session and returns the |sessionId|.  Valid |sessionType|
  // are defined in the spec: http://goo.gl/vmc3pd
  NSError *CreateSession(widevine::Cdm::SessionType sessionType,
                          NSString **sessionId);

  // Get Status of License and Expiration of Session.
  NSError *GetLicenseInfo(NSString *sessionId, int64_t *expiration);

  // Loads the session for a |sessionId|.
  NSError *LoadSession(NSString *sessionId);

  // Remove the session for a |sessionId|.
  NSError *RemoveSession(NSString *sessionId);

  // Closes the |sessionIds| from previous calls to CreateSession.
  // TODO (seawardt): Add Support for Multiple Calls to error out gracefully.
  void CloseSessions(NSArray *sessionIds);

  // Decrypts the |encypted| blob with |key_id| and |iv|.
  NSData *Decrypt(NSData *encrypted, NSData *key_id, NSData *iv);

  // Generates a request based on |data|.
  NSError *GenerateRequest(NSString *sessionId, NSData *initData);

  virtual void setTimeout(int64_t delay_ms,
                          widevine::Cdm::ITimer::IClient *client,
                          void *context) override final;

  virtual void cancel(widevine::Cdm::ITimer::IClient *client) override final;

  virtual int64_t now() override final;

  virtual void onMessage(const std::string &session_id,
                         widevine::Cdm::MessageType message_type,
                         const std::string &message) override final;

  virtual void onKeyStatusesChange(
      const std::string &session_id) override final;

  virtual void onRemoveComplete(const std::string &session_id) override final;

  virtual bool read(const std::string &name, std::string *data) override final;

  virtual bool write(const std::string &name,
                     const std::string &data) override final;

  virtual bool exists(const std::string &name) override final;

  virtual bool remove(const std::string &name) override final;

  virtual int32_t size(const std::string &name) override final;

 private:
  widevine::Cdm *cdm_;
  id<iOSCdmHandler> iOSCdmHandler_;
  NSMutableDictionary *timers_;
};

#endif // WIDEVINE_BASE_CDM_HOST_IOS_CDMHOST_H_

