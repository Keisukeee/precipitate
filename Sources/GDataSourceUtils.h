//
// Copyright (c) 2009 Google Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <Foundation/Foundation.h>
#import <GData/GData.h>
#import "GPKeychainItem.h"

@interface GDataServiceGoogle(PrecipitateSourceExtensions)
// Configures the service to use the login information in credentials, have the
// correct user agent string, and a few other useful properties (e.g., retry,
// autofollow).
- (void)gp_configureWithCredentials:(GPKeychainItem*)credentials;
@end

@interface NSError(PrecipitateSourceExtensions)
// Returns an NSError for a login failure described by the localized string
// from the app bundle with the given key.
+ (NSError*)gp_loginErrorWithDescriptionKey:(NSString*)key;
@end

@interface NSArray(PrecipitateSourceExtensions)
// Assumes |self| is an array of GDataPerson objects, and returns a new array
// of stringified versions containing both name and email (if presenent).
- (NSArray*)gp_peopleStringsForGDataPeople;
@end
