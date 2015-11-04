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
class iOSCdmHost : public cdm::Host_4 {
 public:
  // Make the cdm::Buffer concrete.
  class MediaBuffer : public cdm::Buffer {
   public:
    MediaBuffer(size_t size) {
      media_buffer_.resize(size);
    }
    virtual void Destroy() {delete this;}
    virtual int32_t Capacity() const {return (int32_t)media_buffer_.capacity();}
    virtual uint8_t* Data() {return media_buffer_.data();}
    virtual void SetSize(int32_t size) {media_buffer_.resize(size);}
    virtual int32_t Size() const {return (int32_t)media_buffer_.size();}

   protected:
    MediaBuffer() {}
    virtual ~MediaBuffer() {}

   private:
    MediaBuffer(const MediaBuffer&);
    void operator=(const MediaBuffer&);
    std::vector<uint8_t> media_buffer_;
  };

  // Make the DecryptedBlock concrete from decrypted media chunk.
  class DecryptedBlock : public cdm::DecryptedBlock {
   public:
    DecryptedBlock() {}
    virtual ~DecryptedBlock() {
      if (media_buffer_) {
        media_buffer_->Destroy();
      }
    }
    virtual void SetDecryptedBuffer(cdm::Buffer* buffer) {media_buffer_ = buffer;}
    virtual cdm::Buffer* DecryptedBuffer() {return media_buffer_;}

    virtual void SetTimestamp(int64_t timestamp) {timestamp_ = timestamp;}
    virtual int64_t Timestamp() const {return timestamp_;}

   private:
    cdm::Buffer *media_buffer_;
    int64_t timestamp_;
  };

  // API
  static iOSCdmHost* GetHost() {
    static dispatch_once_t token;
    static iOSCdmHost* s_host;
    dispatch_once(&token, ^{
      s_host = new iOSCdmHost;
    });
    return s_host;
  }

  // Initalize/Deinitialize should be called once for the lifetime of the app.
  void Initialize();
  void Deinitialize();

  // Set the callback object to handle responses from the CDM. Since CdmHost
  // is a static class, seting the cdmHandler can overwrite the previous
  // handler.
  void SetiOSCdmHandler(id<iOSCdmHandler> handler);

  // Creates the session for a |sessionId| and |pssh| key. Caller must generate
  // a unique |sessionId| for each unique |pssh| key. |mimetype| enables the host
  // to identify if the file type is supported.
  // Valid |sessionType| are defined in the spec: http://goo.gl/vmc3pd
  void CreateSession(uint32_t sessionId,
                     NSString *mimeType,
                     NSData *pssh,
                     cdm::SessionType sessionType);

  // Loads the session for a |sessionId| and continues the |webSessionId|.
  // The |sessionId| is unique for each run of the application and is not
  // preserved between sessions.  The |webSessionId| is the prior |webSessionId|
  // from OnSessionCreated.
  // It is up to the user application to know if LoadSession can be called and
  // what |webSessionId|s the application can continue.
  void LoadSession(uint32_t sessionId,
                   NSString *webSessionId);

  // Remove the session for a |sessionId| and delete the records of |webSessionId|.
  // The |sessionId| is unique for each run of the application, which is only an
  // identification of this remove behavior. It can be different from the |sessionId|
  // that was passed to CreateSession().
  void RemoveSession(uint32_t sessionId,
                     NSString *webSessionId);

  // Closes the |sessionIds| from previous calls to CreateSession.
  // TODO (seawardt): Add Support for Multiple Calls to error out gracefully.
  void CloseSessions(NSArray *sessionIds);

  // Decrypts the |encypted| blob with |key_id| and |iv|.
  NSData* Decrypt(NSData *encrypted, NSData* key_id, NSData* iv);

  // Host Implementation.  See go/wvcdm for documentation.
  virtual cdm::Buffer* Allocate(uint32_t capacity);

  virtual void SetTimer(int64_t delay_ms, void* context);

  virtual double GetCurrentWallTimeInSeconds();

  virtual void OnSessionCreated(uint32_t session_id,
                                const char* web_session_id,
                                uint32_t web_session_id_length);

  virtual void OnSessionMessage(uint32_t session_id,
                                const char* message,
                                uint32_t message_length,
                                const char* destination_url,
                                uint32_t destination_url_length);

  virtual void OnSessionUpdated(uint32_t session_id);

  virtual void OnSessionClosed(uint32_t session_id);

  virtual void OnSessionError(uint32_t session_id,
                              cdm::Status error_code,
                              uint32_t system_code);

  virtual cdm::FileIO* CreateFileIO(cdm::FileIOClient* client);

 private:
  static iOSCdmHost s_host;
  cdm::ContentDecryptionModule_4* cdm_;
  id<iOSCdmHandler> iOSCdmHandler_;
};

class iOSCdmHost_FileIO : public cdm::FileIO {
 public:
  iOSCdmHost_FileIO(cdm::FileIOClient* client,
                    id<iOSCdmHandler> iOSCdmHandler)
      : client_(client), iOSCdmHandler_(iOSCdmHandler) {}
  virtual ~iOSCdmHost_FileIO() {}

  virtual void Open(const char* file_name, uint32_t file_name_size);
  virtual void Read();
  virtual void Write(const uint8_t* data, uint32_t data_size);
  virtual void Close();

 private:
  cdm::FileIOClient* client_;
  NSString *file_name_;
  id<iOSCdmHandler> iOSCdmHandler_;
};

#endif // WIDEVINE_BASE_CDM_HOST_IOS_CDMHOST_H_

