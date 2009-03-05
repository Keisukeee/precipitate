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

#import "GPSharedPreferences.h"
#import "GTMGarbageCollection.h"
#import "GTMObjectSingleton.h"

static CFStringRef kOldPrefIdentifier = CFSTR("com.google.precipitate");
static CFStringRef kPrefIdentifier = CFSTR("com.googlecode.precipitate");

static CFStringRef kSourceListKey = CFSTR("AvailableSources");
static CFStringRef kPrefUpdateIntervalKey = CFSTR("UpdateInterval");
static CFStringRef kPrefCustomLanchKey = CFSTR("CustomLaunchers");

NSString* const kGPSourcePrefDisplayNameKey = @"DisplayName";
NSString* const kGPSourcePrefEnabledKey = @"Enabled";

// Update interval default and minimum, in minutes.
static const int kDefaultUpdateInterval = 60;
static const int kMinUpdateInterval = 5;

@implementation GPSharedPreferences

GTMOBJECT_SINGLETON_BOILERPLATE(GPSharedPreferences, sharedPreferences)

- (void)setAvailableSources:(NSDictionary*)sourceInfo {
  NSDictionary* oldSourceInfo = [self availableSources];
  NSMutableDictionary* newSourceInfo = [NSMutableDictionary dictionaryWithCapacity:[sourceInfo count]];
  // Don't use keyEnumerator, since we'll be modifying the dictionary
  for (NSString* sourceId in sourceInfo) {
    NSMutableDictionary* newInfo = [[[sourceInfo objectForKey:sourceId] mutableCopy] autorelease];
    // Default new sources to disabled
    BOOL enabled = [[[oldSourceInfo objectForKey:sourceId] objectForKey:kGPSourcePrefEnabledKey] boolValue];
    [newInfo setObject:[NSNumber numberWithBool:enabled] forKey:kGPSourcePrefEnabledKey];
    [newSourceInfo setObject:newInfo forKey:sourceId];
  }
  CFPreferencesSetAppValue(kSourceListKey, newSourceInfo, kPrefIdentifier);
  CFPreferencesAppSynchronize(kPrefIdentifier);
}

- (NSDictionary*)availableSources {
  CFPreferencesAppSynchronize(kPrefIdentifier);
  NSDictionary* sourcesDict =
    GTMCFAutorelease(CFPreferencesCopyAppValue(kSourceListKey,
                                               kPrefIdentifier));
  if (!sourcesDict) {
    // Do a one-time upgrade if the old prefs are present
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* prefsFolder = [@"~/Library/Preferences/" stringByExpandingTildeInPath];
    NSString* oldPrefsPath = [[prefsFolder stringByAppendingPathComponent:(NSString*)kOldPrefIdentifier]
                                stringByAppendingPathExtension:@"plist"];
    NSString* newPrefsPath = [[prefsFolder stringByAppendingPathComponent:(NSString*)kPrefIdentifier]
                                stringByAppendingPathExtension:@"plist"];
    if ([fileManager fileExistsAtPath:oldPrefsPath] && ![fileManager fileExistsAtPath:newPrefsPath]) {
      // Read again now that we have prefs in the right place. This is safe
      // because we sucessfully removed the old file, so we can't recurse again.
      if ([fileManager movePath:oldPrefsPath toPath:newPrefsPath handler:nil])
        return [self availableSources];
    }
  }
  return sourcesDict;
}

- (void)setEnabled:(BOOL)enabled forSource:(NSString*)sourceId {
  CFPreferencesAppSynchronize(kPrefIdentifier);
  NSDictionary* oldAllSourceInfo =
    GTMCFAutorelease(CFPreferencesCopyAppValue(kSourceListKey,
                                               kPrefIdentifier));
  NSMutableDictionary* newAllSourceInfo = [[oldAllSourceInfo mutableCopy] autorelease];

  NSMutableDictionary* newInfo = [[[newAllSourceInfo objectForKey:sourceId] mutableCopy] autorelease];
  [newInfo setObject:[NSNumber numberWithBool:enabled] forKey:kGPSourcePrefEnabledKey];
  [newAllSourceInfo setObject:newInfo forKey:sourceId];

  CFPreferencesSetAppValue(kSourceListKey, newAllSourceInfo, kPrefIdentifier);
  CFPreferencesAppSynchronize(kPrefIdentifier);
}

- (BOOL)sourceIsEnabled:(NSString*)sourceId {
  CFPreferencesAppSynchronize(kPrefIdentifier);
  NSDictionary* allSourceInfo =
    GTMCFAutorelease(CFPreferencesCopyAppValue(kSourceListKey,
                                               kPrefIdentifier));
  NSDictionary* sourceInfo = [allSourceInfo objectForKey:sourceId];
  if (!sourceInfo)
    return NO;
  return [[sourceInfo objectForKey:kGPSourcePrefEnabledKey] boolValue];
}

- (NSTimeInterval)updateInterval {
  CFPreferencesAppSynchronize(kPrefIdentifier);
  NSNumber* intervalObject =
    GTMCFAutorelease(CFPreferencesCopyAppValue(kPrefUpdateIntervalKey,
                                               kPrefIdentifier));
  double updateMinutes = intervalObject ? [intervalObject intValue]
                                        : kDefaultUpdateInterval;
  if (updateMinutes < kMinUpdateInterval)
    updateMinutes = kMinUpdateInterval;
  return updateMinutes * 60.0;
}

- (NSString*)customLauncherForSource:(NSString*)sourceId {
  CFPreferencesAppSynchronize(kPrefIdentifier);
  NSDictionary* customLaunchDict =
    GTMCFAutorelease(CFPreferencesCopyAppValue(kPrefCustomLanchKey,
                                               kPrefIdentifier));
  return [customLaunchDict objectForKey:sourceId];
}

@end
