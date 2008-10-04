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

#import "GPSyncController.h"
#import "GPSharedPreferences.h"
#import "GPSourceStatus.h"
#import "SharedConstants.h"
#import "GTMGarbageCollection.h"
#import "GTMNSFileManager+Path.h"

#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
#include <dlfcn.h>
typedef CFTypeRef (*LSSharedFileListCreateFPtr)(
  CFAllocatorRef inAllocator,
  CFStringRef inListType,
  CFTypeRef listOptions
);
typedef CFTypeRef (*LSSharedFileListInsertItemURLFPtr)(
  CFTypeRef inList,
  CFTypeRef insertAfterThisItem,
  CFStringRef inDisplayName,
  IconRef inIconRef,
  CFURLRef inURL,
  CFDictionaryRef inPropertiesToSet,
  CFArrayRef inPropertiesToClear
);
#endif

static NSString* const kIDSlashReplacementToken = @":SLASH:";

static NSString* const kDistributedKillNotification = @"GPSyncControllerKillNotification";

static NSString* const kDefaultCacheExtension = @"precipitate";

@interface GPSyncController (Private)

- (void)ensureAutoLaunch;
- (NSString*)identifierForSource:(id<GPSyncSource>)source;
- (NSString*)cachePathForSource:(id<GPSyncSource>)source;
- (void)loadSources;
- (void)syncAllSources;
- (void)updateSources;
- (void)finishedSource:(id<GPSyncSource>)source withError:(NSError*)error;

@end

@implementation GPSyncController

- (void)awakeFromNib {
  [self ensureAutoLaunch];

  // Send out the kill notification, then start listening for it ourselves.
  // This makes it possible for to update simply by launching the new version.
  NSDistributedNotificationCenter* dnc = [NSDistributedNotificationCenter defaultCenter];
  int selfPID = [[NSProcessInfo processInfo] processIdentifier];
  [dnc postNotificationName:kDistributedKillNotification
                     object:nil
                   userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:selfPID]
                                                        forKey:@"pid"]];
  [dnc addObserver:self
          selector:@selector(recievedKillNotification:)
              name:kDistributedKillNotification
            object:nil];
  [dnc addObserver:self
          selector:@selector(recievedReSyncNotification:)
              name:kPrecipitateReSyncNeededNotification
            object:nil];

  currentlySyncingSources_ = [[NSMutableSet alloc] init];
  syncStatus_ = [[GPSourceStatus sharedSourceStatus] retain];
  [self updateSources];
}

- (void)dealloc {
  [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
  [sources_ release];
  [extensionToSourceMapping_ release];
  [syncStatus_ release];
  [currentlySyncingSources_ release];
  [super dealloc];
}

// Makes sure that this background app is in the login items, so that it will
// stay running in the future.
- (void)ensureAutoLaunch {
  NSString* appPath = [[NSBundle mainBundle] bundlePath];
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
  LSSharedFileListCreateFPtr dLSSharedFileListCreate =
    dlsym(RTLD_DEFAULT, "LSSharedFileListCreate");
  LSSharedFileListInsertItemURLFPtr dLSSharedFileListInsertItemURL =
    dlsym(RTLD_DEFAULT, "LSSharedFileListInsertItemURL");
  CFStringRef dkLSSharedFileListSessionLoginItems =
    (CFStringRef)*((int*)dlsym(RTLD_DEFAULT, "kLSSharedFileListSessionLoginItems"));
  CFTypeRef dkLSSharedFileListItemLast =
    (CFTypeRef)*((int*)dlsym(RTLD_DEFAULT, "kLSSharedFileListItemLast"));
  NSLog(@"Lookup: %x %x %@ %x", dLSSharedFileListCreate, dLSSharedFileListInsertItemURL,
        (NSString*)dkLSSharedFileListSessionLoginItems, dkLSSharedFileListItemLast);
  // They should be all-or-nothing, but check everything in case something goes
  // wrong with the dlsym lookup.
  if (dLSSharedFileListCreate != NULL &&
      dLSSharedFileListInsertItemURL != NULL &&
      dkLSSharedFileListSessionLoginItems != NULL &&
      dkLSSharedFileListItemLast != NULL)
#else
  if (LSSharedFileListCreate != NULL)
#endif
  {
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
    CFTypeRef loginList =
      dLSSharedFileListCreate(NULL, dkLSSharedFileListSessionLoginItems, NULL);
#else
    LSSharedFileListRef loginList =
      LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
#endif
    if (!loginList) {
      NSLog(@"Could not get a reference to login items list");
      return;
    }
    // No need to check if it's already there, since the LSSharedFileList API
    // handles de-duping for us.
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
    dLSSharedFileListInsertItemURL(loginList, dkLSSharedFileListItemLast,
                                   NULL, NULL,
                                   (CFURLRef)[NSURL fileURLWithPath:appPath],
                                   NULL, NULL);
#else
    LSSharedFileListInsertItemURL(loginList, kLSSharedFileListItemLast,
                                  NULL, NULL,
                                  (CFURLRef)[NSURL fileURLWithPath:appPath],
                                  NULL, NULL);
#endif
    CFRelease(loginList);
  } else {
    CFStringRef prefDomain = CFSTR("loginwindow");
    CFStringRef autoLaunchKey = CFSTR("AutoLaunchedApplicationDictionary");
    NSString* pathKey = @"Path";
    
    NSArray* loginItems = [GTMNSMakeCollectable(CFPreferencesCopyValue(autoLaunchKey,
                                                                       prefDomain,
                                                                       kCFPreferencesCurrentUser, 
                                                                       kCFPreferencesAnyHost)) autorelease];
    // Check if it's already there; don't bother with the alias data, since
    // this isn't an app that will be relocated by the user.
    if (![[loginItems valueForKey:pathKey] containsObject:appPath]) {
      NSMutableArray* newLoginItems = [[loginItems mutableCopy] autorelease];
      [newLoginItems addObject:[NSDictionary dictionaryWithObject:appPath forKey:pathKey]];
      CFPreferencesSetValue(autoLaunchKey,
                            (CFTypeRef)newLoginItems,
                            prefDomain,
                            kCFPreferencesCurrentUser, 
                            kCFPreferencesAnyHost);
      CFPreferencesSynchronize(prefDomain,
                               kCFPreferencesCurrentUser, 
                               kCFPreferencesAnyHost);
    }
  }
}

- (void)recievedKillNotification:(NSNotification*)notification {
  int selfPID = [[NSProcessInfo processInfo] processIdentifier];
  int senderPID = [[[notification userInfo] objectForKey:@"pid"] intValue];
  if (senderPID != selfPID)
    [NSApp terminate:nil];
}

- (void)recievedReSyncNotification:(NSNotification*)notification {
  [self syncAllSources];
}

- (void)syncAllSources {
  NSDistributedNotificationCenter* dnc = [NSDistributedNotificationCenter defaultCenter];
  [dnc postNotificationName:kPrecipitateSyncStartedNotification object:nil userInfo:nil];
  GPSharedPreferences* sourcePrefs = [GPSharedPreferences sharedPreferences];
  NSEnumerator* sourceEnumerator = [sources_ objectEnumerator];
  id<GPSyncSource> source;
  while ((source = [sourceEnumerator nextObject])) {
    if ([sourcePrefs sourceIsEnabled:[self identifierForSource:source]]) {
      if (![currentlySyncingSources_ containsObject:source]) {
        @try {
          [source fetchAllItemsBasicInfo];
          [currentlySyncingSources_ addObject:source];
        } @catch (id exception) {
          NSLog(@"Failed to sync source '%@': %@", source, exception);
        }
      }
    } else {
      NSString* sourceCachePath = [self cachePathForSource:source];
      NSFileManager* fm = [NSFileManager defaultManager];
      if ([fm fileExistsAtPath:sourceCachePath]) {
        [fm removeFileAtPath:sourceCachePath handler:NULL];
        [syncStatus_ clearSyncStatusForSource:[self identifierForSource:source]];
      }
    }
  }
  if ([currentlySyncingSources_ count] == 0)
    [dnc postNotificationName:kPrecipitateSyncFinishedNotification object:nil userInfo:nil];
}

- (NSString*)sourcePluginDirectory {
  return [[NSBundle mainBundle] builtInPlugInsPath];
}

- (void)loadSources {
  if (!sources_)
    sources_ = [[NSMutableArray alloc] init];
  if (!extensionToSourceMapping_)
    extensionToSourceMapping_ = [[NSMutableDictionary alloc] init];

  NSString* sourcePluginDirectory = [self sourcePluginDirectory];
  NSArray* plugins = [[NSFileManager defaultManager] directoryContentsAtPath:sourcePluginDirectory];
  NSEnumerator* pluginEnumerator = [plugins objectEnumerator];
  NSString* plugin;
  while ((plugin = [pluginEnumerator nextObject])) {
    NSBundle* pluginBundle = [NSBundle bundleWithPath:[sourcePluginDirectory stringByAppendingPathComponent:plugin]];
    if ([pluginBundle isLoaded])
      continue;
    if (!pluginBundle || ![pluginBundle load]) {
      NSLog(@"Unable to load source '%@'; it does not appear to be a plugin", plugin);
      continue;
    }
    Class pluginClass = [pluginBundle principalClass];
    if (![pluginClass conformsToProtocol:@protocol(GPSyncSource)]) {
      NSLog(@"Unable to load source '%@'; principal class is not a GPSyncSource", plugin);
      continue;
    }

    @try {
      id<GPSyncSource> source = [[[pluginClass alloc] initWithManager:self] autorelease];
      [sources_ addObject:source];
      NSEnumerator* extensionEnumerator = [[source itemExtensions] objectEnumerator];
      NSString* extension;
      while ((extension = [extensionEnumerator nextObject]))
        [extensionToSourceMapping_ setObject:source forKey:extension];
    } @catch (id exception) {
      NSLog(@"Failed to load source '%@': %@", plugin, exception);
    }
  }
  NSMutableDictionary* availableSources = [NSMutableDictionary dictionary];
  NSEnumerator* sourceEnumerator = [sources_ objectEnumerator];
  id<GPSyncSource> source;
  while ((source = [sourceEnumerator nextObject])) {
    [availableSources setObject:[NSDictionary dictionaryWithObject:[source displayName]
                                                            forKey:kGPSourcePrefDisplayNameKey]
                         forKey:[self identifierForSource:source]];
  }
  [[GPSharedPreferences sharedPreferences] setAvailableSources:availableSources];
}

- (void)updateSources {
  // Schedule the next update up front, so that a slow source won't delay everything
  [[self class] cancelPreviousPerformRequestsWithTarget:self
                                               selector:@selector(updateSources)
                                                 object:nil];
  NSTimeInterval updateInterval = [[GPSharedPreferences sharedPreferences] updateInterval];
  [self performSelector:@selector(updateSources) withObject:nil afterDelay:updateInterval];

  [self loadSources];
  [self syncAllSources];
}

- (void)finishedSource:(id<GPSyncSource>)source withError:(NSError*)error {
  [currentlySyncingSources_ removeObject:source];
  [syncStatus_ setLastSyncTime:[NSDate date] error:error forSource:[self identifierForSource:source]];
  if ([currentlySyncingSources_ count] == 0) {
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:kPrecipitateSyncFinishedNotification
                                                                   object:nil
                                                                 userInfo:nil];
  }
}

- (NSString*)identifierForSource:(id<GPSyncSource>)source {
  NSBundle* sourceBundle = [NSBundle bundleForClass:[source class]];
  return [[sourceBundle infoDictionary] objectForKey:@"CFBundleIdentifier"];
}

- (NSString*)cachePathForSource:(id<GPSyncSource>)source {
  static NSString* sPathBase = nil;
  if (!sPathBase) {
    sPathBase = [@"~/Library/Caches/Metadata" stringByExpandingTildeInPath];
    sPathBase = [[sPathBase stringByAppendingPathComponent:@"Precipitate"] retain];
  }
  return [sPathBase stringByAppendingPathComponent:[self identifierForSource:source]];
}

// Returns the path for an item, relative to the cache base.
+ (NSString*)cacheFilenameForItem:(NSDictionary*)item
                       fromSource:(id<GPSyncSource>)source {
  NSString* fileName = [item objectForKey:(NSString*)kMDItemTitle];
  fileName = [[fileName componentsSeparatedByString:@"/"] componentsJoinedByString:@":"];

  NSString* extension = nil;
  @try {
    extension = [source cacheFileExtensionForItem:item];
  } @catch (id exception) {
    NSLog(@"Failed to get extension for '%@' from '%@': %@", item, source, exception);
    extension = @"unknown";
  }
  return [fileName stringByAppendingPathExtension:extension];
}

// The structure of each source's cache is:
// <name of source's cache folder>/
//   <item1UID>/
//     <item1Title>.<item1Extension>
//   <item2UID>/
//     <item2Title>.<item2Extension>
//   ...
- (void)reconcileCacheAtPath:(NSString*)cacheBase
                   withItems:(NSArray*)items
                  fromSource:(id<GPSyncSource>)source {

  NSMutableDictionary* itemsById = [NSMutableDictionary dictionary];
  NSEnumerator* itemEnumerator = [items objectEnumerator];
  NSDictionary* item;
  while ((item = [itemEnumerator nextObject])) {
    [itemsById setObject:item forKey:[item objectForKey:kGPMDItemUID]];
  }

  NSFileManager* fileManager = [NSFileManager defaultManager];

  // First,  remove anything that exists locally but is gone from the source.
  NSArray* cacheIds = [fileManager directoryContentsAtPath:cacheBase];
  NSEnumerator* localFileEnumerator = [cacheIds objectEnumerator];
  NSString* cacheId;
  while ((cacheId = [localFileEnumerator nextObject])) {
    NSString* sourceId = [[cacheId componentsSeparatedByString:kIDSlashReplacementToken] componentsJoinedByString:@"/"];
    if (![itemsById objectForKey:sourceId]) {
      NSString* path = [cacheBase stringByAppendingPathComponent:cacheId];
      [fileManager removeFileAtPath:path handler:nil];
    }
  }

  // Find the missing/out-of-date items.
  NSMutableArray* itemsToRefresh = [NSMutableArray array];
  NSEnumerator* sourceEnumerator = [items objectEnumerator];
  while ((item = [sourceEnumerator nextObject])) {
    NSString* itemId = [item objectForKey:kGPMDItemUID];
    NSString* cacheId = [[itemId componentsSeparatedByString:@"/"] componentsJoinedByString:kIDSlashReplacementToken];
    NSString* directoryPath = [cacheBase stringByAppendingPathComponent:cacheId];
    NSString* filename = [[self class] cacheFilenameForItem:item fromSource:source];
    NSString* itemPath = [directoryPath stringByAppendingPathComponent:filename];
    if ([fileManager fileExistsAtPath:itemPath]) {
      NSDate* fileModDate = [[fileManager fileAttributesAtPath:itemPath traverseLink:NO] fileModificationDate];
      NSDate* sourceModDate = [item objectForKey:kGPMDItemModificationDate];
      if (fileModDate && sourceModDate && ([fileModDate compare:sourceModDate] != NSOrderedAscending))
        continue;
    } else if ([fileManager fileExistsAtPath:directoryPath]) {
      // If the directory exists without the file, the item was probably renamed,
      // meaning there is a stale file in the directory with a different name,
      // so remove it.
      [fileManager removeFileAtPath:directoryPath handler:nil];
    }

    // If we got here, either we don't have a cache of the item, or it's stale.
    [itemsToRefresh addObject:item];
  }

  // Fetch the full info for the items we need to update.
  if ([itemsToRefresh count] > 0) {
    @try {
      [source fetchFullInfoForItems:itemsToRefresh];
    } @catch (id exception) {
      NSLog(@"Failed to fully sync source '%@': %@", source, exception);
      NSDictionary* errorInfo = [NSDictionary dictionaryWithObject:[exception reason]
                                                            forKey:NSLocalizedDescriptionKey];
      NSError* error = [NSError errorWithDomain:@"SourceException"
                                           code:1
                                       userInfo:errorInfo];
      [self finishedSource:source withError:error];
    }
  } else {
    // If there's nothing else to do, just mark the source as up-to-date.
    [self finishedSource:source withError:nil];
  }
}

- (void)writeItems:(NSArray*)items
        fromSource:(id<GPSyncSource>)source
     toCacheAtPath:(NSString*)cacheBase {
  NSFileManager* fileManager = [NSFileManager defaultManager];

  NSEnumerator* sourceEnumerator = [items objectEnumerator];
  NSDictionary* item;
  while ((item = [sourceEnumerator nextObject])) {
    NSString* itemId = [item objectForKey:kGPMDItemUID];
    NSString* cacheId = [[itemId componentsSeparatedByString:@"/"] componentsJoinedByString:kIDSlashReplacementToken];
    NSString* directoryPath = [cacheBase stringByAppendingPathComponent:cacheId];
    [fileManager gtm_createFullPathToDirectory:directoryPath attributes:nil];

    NSString* filename = [[self class] cacheFilenameForItem:item fromSource:source];
    NSString* itemPath = [directoryPath stringByAppendingPathComponent:filename];
    [item writeToFile:itemPath atomically:YES];
    [fileManager changeFileAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
                                                                  forKey:NSFileExtensionHidden]
                               atPath:itemPath];
  }
}

#pragma mark -

- (void)basicItemsInfo:(NSArray*)items fetchedForSource:(id<GPSyncSource>)source {
  NSString* cachePath = [self cachePathForSource:source];
  [self reconcileCacheAtPath:cachePath withItems:items fromSource:source];
}

- (void)fullItemsInfo:(NSArray*)items fetchedForSource:(id<GPSyncSource>)source {
  NSString* cachePath = [self cachePathForSource:source];
  [self writeItems:items fromSource:source toCacheAtPath:cachePath];
}

- (void)fullItemsInfoFetchCompletedForSource:(id<GPSyncSource>)source {
  [self finishedSource:source withError:nil];
}

- (void)infoFetchFailedForSource:(id<GPSyncSource>)source
                       withError:(NSError*)error
{
  [self finishedSource:source withError:error];
}

#pragma mark -

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename {
  NSDictionary* item = [NSDictionary dictionaryWithContentsOfFile:filename];
  id<GPSyncSource> managingSource = [extensionToSourceMapping_ objectForKey:[filename pathExtension]];
  if (managingSource && [managingSource respondsToSelector:@selector(openPrecipitateItem:)]) {
    return [(id)managingSource openPrecipitateItem:item];
  } else {
    NSString* link = [item objectForKey:(NSString*)kGPMDItemURL];
    if (!link)
      return NO;
    NSURL* url = [NSURL URLWithString:link];
    if (!url)
      return NO;

    NSString* sourceId = [self identifierForSource:managingSource];
    NSString* launcherId = [[GPSharedPreferences sharedPreferences] customLauncherForSource:sourceId];
    if (launcherId) {
      return [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:url]
                             withAppBundleIdentifier:launcherId
                                             options:NSWorkspaceLaunchDefault
                      additionalEventParamDescriptor:nil
                                   launchIdentifiers:nil];
    } else {
      return [[NSWorkspace sharedWorkspace] openURL:url];
    }
  }
}

@end
