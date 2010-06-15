//
// Copyright (c) 2008 Google Inc.
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
#import <Security/Security.h>

// A very simple API for interacting with service passwords stored in Keychain.
@interface GPKeychainItem : NSObject
{
 @private
  __strong SecKeychainItemRef mKeychainItemRef;
  BOOL mDataLoaded;
  NSString* mService;
  NSString* mUsername;
  NSString* mPassword;
}

// Returns the first keychain item matching the given criteria.
+ (GPKeychainItem*)keychainItemForService:(NSString*)service;

// Creates and returns a new keychain item
+ (GPKeychainItem*)addKeychainItemForService:(NSString*)service
                              withUsername:(NSString*)username
                                  password:(NSString*)password;

- (NSString*)username;
- (NSString*)password;
- (void)setUsername:(NSString*)username password:(NSString*)password;
- (NSString*)service;
- (void)setService:(NSString*)service;

- (void)removeFromKeychain;

@end
