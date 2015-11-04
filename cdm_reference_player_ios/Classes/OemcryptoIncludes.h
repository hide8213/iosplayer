// Copyright 2015 Google Inc. All rights reserved.
// Handles the importing of UDT and OEMCrypto headers based on Library type.


#if OEMCRYPTO_DYLIB
# if TARGET_IPHONE_SIMULATOR
# import "oemcrypto_tfit2_dev_dylib_sim/DashToHlsApi.h"
# import "oemcrypto_tfit2_dev_dylib_sim/DashToHlsApiAVFramework.h"
# import "oemcrypto_tfit2_dev_dylib_sim/OEMCryptoCENC.h"
# else
# import "oemcrypto_tfit2-eit_dev_dylib/DashToHlsApi.h"
# import "oemcrypto_tfit2-eit_dev_dylib/DashToHlsApiAVFramework.h"
# import "oemcrypto_tfit2-eit_dev_dylib/OEMCryptoCENC.h"
# endif  // TARGET_IPHONE_SIMULATOR
#else
#import "DashToHlsApi.h"
#import "DashToHlsApiAVFramework.h"
#import "OEMCryptoCENC.h"
#endif  // OEMCRYPTO_DYLIB

