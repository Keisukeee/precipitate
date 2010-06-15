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

#import "GPKeychainItem.h"

@interface GPKeychainItem(Private)
- (GPKeychainItem*)initWithRef:(SecKeychainItemRef)ref;
- (void)loadKeychainData;
- (BOOL)setAttributeType:(SecKeychainAttrType)type toString:(NSString*)value;
- (BOOL)setAttributeType:(SecKeychainAttrType)type toValue:(void*)valuePtr withLength:(UInt32)length;
@end

@implementation GPKeychainItem

+ (GPKeychainItem*)keychainItemForService:(NSString*)service {
  SecKeychainItemRef itemRef;
  const char* serviceName = [service UTF8String];
  UInt32 serviceNameLength = serviceName ? (UInt32)strlen(serviceName) : 0;
  OSStatus result = SecKeychainFindGenericPassword(NULL,
                                                   serviceNameLength, serviceName,
                                                   0, NULL, 0, NULL,
                                                   &itemRef);
  if (result != noErr)
      return nil;

  return [[[GPKeychainItem alloc] initWithRef:itemRef] autorelease];
}

+ (GPKeychainItem*)addKeychainItemForService:(NSString*)service
                              withUsername:(NSString*)username
                                  password:(NSString*)password {
  const char* serviceName = [service UTF8String];
  UInt32 serviceLength = serviceName ? (UInt32)strlen(serviceName) : 0;
  const char* accountName = [username UTF8String];
  UInt32 accountLength = accountName ? (UInt32)strlen(accountName) : 0;
  const char* passwordData = [password UTF8String];
  UInt32 passwordLength = passwordData ? (UInt32)strlen(passwordData) : 0;
  SecKeychainItemRef keychainItemRef;
  OSStatus result = SecKeychainAddGenericPassword(NULL, serviceLength, serviceName,
                                                  accountLength, accountName,
                                                  passwordLength, passwordData,
                                                  &keychainItemRef);
  if (result != noErr) {
    NSLog(@"Couldn't add keychain item");
    return nil;
  }

  CFMakeCollectable(keychainItemRef);
  GPKeychainItem* item = [[[GPKeychainItem alloc] initWithRef:keychainItemRef] autorelease];
  return item;
}

- (GPKeychainItem*)initWithRef:(SecKeychainItemRef)ref {
  if ((self = [super init])) {
    mKeychainItemRef = ref;
    mDataLoaded = NO;
  }
  return self;
}

- (void)dealloc {
  if (mKeychainItemRef)
    CFRelease(mKeychainItemRef);
  [mUsername release];
  [mPassword release];
  [mService release];
  [super dealloc];
}

- (void)loadKeychainData {
  if (!mKeychainItemRef)
    return;
  SecKeychainAttributeInfo attrInfo;
  UInt32 tags[2];
  tags[0] = kSecAccountItemAttr;
  tags[1] = kSecServiceItemAttr;
  attrInfo.count = (UInt32)(sizeof(tags)/sizeof(UInt32));
  attrInfo.tag = tags;
  attrInfo.format = NULL;

  SecKeychainAttributeList *attrList;
  UInt32 passwordLength;
  char* passwordData;
  OSStatus result = SecKeychainItemCopyAttributesAndData(mKeychainItemRef,
                                                         &attrInfo,
                                                         NULL,
                                                         &attrList,
                                                         &passwordLength,
                                                         (void**)(&passwordData));

  [mUsername autorelease];
  mUsername = nil;
  [mService autorelease];
  mService = nil;
  [mPassword autorelease];
  mPassword = nil;

  if (result != noErr) {
    NSLog(@"Couldn't load keychain data (error %d)", (int)result);
    mUsername = [[NSString alloc] init];
    mService = [[NSString alloc] init];
    mPassword = [[NSString alloc] init];
    return;
  }

  for (unsigned int i = 0; i < attrList->count; i++) {
    SecKeychainAttribute attr = attrList->attr[i];
    if (attr.tag == kSecAccountItemAttr) {
      mUsername = [[NSString alloc] initWithBytes:(char*)(attr.data)
                                           length:attr.length
                                         encoding:NSUTF8StringEncoding];
    } else if (attr.tag == kSecServiceItemAttr) {
      mService = [[NSString alloc] initWithBytes:(char*)(attr.data)
                                          length:attr.length
                                        encoding:NSUTF8StringEncoding];
    }
  }
  mPassword = [[NSString alloc] initWithBytes:passwordData
                                       length:passwordLength
                                     encoding:NSUTF8StringEncoding];
  SecKeychainItemFreeAttributesAndData(attrList, (void*)passwordData);
  mDataLoaded = YES;
}

- (NSString*)username {
  if (!mDataLoaded)
    [self loadKeychainData];
  return mUsername;
}

- (NSString*)password {
  if (!mDataLoaded)
    [self loadKeychainData];
  return mPassword;
}

- (void)setUsername:(NSString*)username password:(NSString*)password {
  SecKeychainAttribute user;
  user.tag = kSecAccountItemAttr;
  const char* usernameString = [username UTF8String];
  user.data = (void*)usernameString;
  user.length = user.data ? (UInt32)strlen(user.data) : 0;
  SecKeychainAttributeList attrList;
  attrList.count = 1;
  attrList.attr = &user;
  const char* passwordData = [password UTF8String];
  UInt32 passwordLength = passwordData ? (UInt32)strlen(passwordData) : 0;
  if (SecKeychainItemModifyAttributesAndData(mKeychainItemRef,
                                             &attrList,
                                             passwordLength,
                                             passwordData) != noErr) {
    NSLog(@"Couldn't update keychain item user and password for %@", username);
  } else {
    [mUsername autorelease];
    mUsername = [username copy];
    [mPassword autorelease];
    mPassword = [password copy];
  }
}

- (NSString*)service {
  if (!mDataLoaded)
    [self loadKeychainData];
  return mService;
}

- (void)setService:(NSString*)service {
  if ([self setAttributeType:kSecServiceItemAttr toString:service]) {
    [mService autorelease];
    mService = [service copy];
  }
  else {
    NSLog(@"Couldn't update keychain item host");
  }
}

- (BOOL)setAttributeType:(SecKeychainAttrType)type toString:(NSString*)value {
  const char* cString = [value UTF8String];
  UInt32 length = cString ? (UInt32)strlen(cString) : 0;
  return [self setAttributeType:type toValue:(void*)cString withLength:length];
}

- (BOOL)setAttributeType:(SecKeychainAttrType)type
                 toValue:(void*)valuePtr
              withLength:(UInt32)length {
  SecKeychainAttribute attr;
  attr.tag = type;
  attr.data = valuePtr;
  attr.length = length;
  SecKeychainAttributeList attrList;
  attrList.count = 1;
  attrList.attr = &attr;
  return (SecKeychainItemModifyAttributesAndData(mKeychainItemRef, &attrList, 0, NULL) == noErr);
}

- (void)removeFromKeychain {
  SecKeychainItemDelete(mKeychainItemRef);
}

@end
