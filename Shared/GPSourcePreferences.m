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

#import "GPSourcePreferences.h"
#import "GTMGarbageCollection.h"
#import "GTMObjectSingleton.h"

static CFStringRef kGPSourcePrefIdentifier = CFSTR("com.google.precipitate");
static CFStringRef kGPSourcePrefSourceListKey = CFSTR("AvailableSources");

NSString* const kGPSourcePrefDisplayNameKey = @"DisplayName";
NSString* const kGPSourcePrefEnabledKey = @"Enabled";

@implementation GPSourcePreferences

GTMOBJECT_SINGLETON_BOILERPLATE(GPSourcePreferences, sharedSourcePreferences)

- (void)setAvailableSources:(NSDictionary*)sourceInfo {
  CFPreferencesAppSynchronize(kGPSourcePrefIdentifier);
  NSDictionary* oldSourceInfo =
    [GTMNSMakeCollectable(CFPreferencesCopyAppValue(kGPSourcePrefSourceListKey,
                                                    kGPSourcePrefIdentifier)) autorelease];
  NSMutableDictionary* newSourceInfo = [[sourceInfo mutableCopy] autorelease];
  // Don't use keyEnumerator, since we'll be modifying the dictionary
  NSEnumerator* newSourceKeyEnumerator = [[newSourceInfo allKeys] objectEnumerator];
  NSString* sourceId;
  while ((sourceId = [newSourceKeyEnumerator nextObject])) {
    NSMutableDictionary* newInfo = [[[newSourceInfo objectForKey:sourceId] mutableCopy] autorelease];
    // Default new sources to disabled
    BOOL enabled = [[[oldSourceInfo objectForKey:sourceId] objectForKey:kGPSourcePrefEnabledKey] boolValue];
    [newInfo setObject:[NSNumber numberWithBool:enabled] forKey:kGPSourcePrefEnabledKey];
    [newSourceInfo setObject:newInfo forKey:sourceId];
  }
  CFPreferencesSetAppValue(kGPSourcePrefSourceListKey, newSourceInfo, kGPSourcePrefIdentifier);
  CFPreferencesAppSynchronize(kGPSourcePrefIdentifier);
}

- (NSDictionary*)availableSources {
  CFPreferencesAppSynchronize(kGPSourcePrefIdentifier);
  return [GTMNSMakeCollectable(CFPreferencesCopyAppValue(kGPSourcePrefSourceListKey,
                                                         kGPSourcePrefIdentifier)) autorelease];
}

- (void)setEnabled:(BOOL)enabled forSource:(NSString*)sourceId {
  CFPreferencesAppSynchronize(kGPSourcePrefIdentifier);
  NSDictionary* oldAllSourceInfo =
    [GTMNSMakeCollectable(CFPreferencesCopyAppValue(kGPSourcePrefSourceListKey,
                                                    kGPSourcePrefIdentifier)) autorelease];
  NSMutableDictionary* newAllSourceInfo = [[oldAllSourceInfo mutableCopy] autorelease];

  NSMutableDictionary* newInfo = [[[newAllSourceInfo objectForKey:sourceId] mutableCopy] autorelease];
  [newInfo setObject:[NSNumber numberWithBool:enabled] forKey:kGPSourcePrefEnabledKey];
  [newAllSourceInfo setObject:newInfo forKey:sourceId];

  CFPreferencesSetAppValue(kGPSourcePrefSourceListKey, newAllSourceInfo, kGPSourcePrefIdentifier);
  CFPreferencesAppSynchronize(kGPSourcePrefIdentifier);
}

- (BOOL)sourceIsEnabled:(NSString*)sourceId {
  CFPreferencesAppSynchronize(kGPSourcePrefIdentifier);
  NSDictionary* allSourceInfo =
    [GTMNSMakeCollectable(CFPreferencesCopyAppValue(kGPSourcePrefSourceListKey,
                                                    kGPSourcePrefIdentifier)) autorelease];
  NSDictionary* sourceInfo = [allSourceInfo objectForKey:sourceId];
  if (!sourceInfo)
    return NO;
  return [[sourceInfo objectForKey:kGPSourcePrefEnabledKey] boolValue];
}

@end
