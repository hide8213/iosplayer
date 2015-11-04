// Copyright 2015 Google Inc. All rights reserved.
// Handles the importing of CDM headers based on OEMCrypto Library type.

#ifndef IPHONE_WIDEVINE_CDM_HOST_IOS_CDMINCLUDES_H_
#define IPHONE_WIDEVINE_CDM_HOST_IOS_CDMINCLUDES_H_

#ifdef __cplusplus
# if OEMCRYPTO_DYLIB
#  if TARGET_IPHONE_SIMULATOR
#  import "oemcrypto_tfit2_dev_dylib_sim/content_decryption_module.h"
#  else
#  import "oemcrypto_tfit2-eit_dev_dylib/content_decryption_module.h"
#  endif
# else
# import "content_decryption_module.h"
# endif
#endif  // __cplusplus

#endif  // IPHONE_WIDEVINE_CDM_HOST_IOS_CDMINCLUDES_H_

