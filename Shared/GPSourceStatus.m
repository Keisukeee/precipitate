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

#import "GPSourceStatus.h"
#import "GTMObjectSingleton.h"

static NSString* const kGPPrecipitateStatusFile = @"SyncStatus";

// TODO: replace with a kqueue?
static NSString* const kGPPrecipitateStatusChanged = @"PrecipitateStatusChanged";

NSString* const kGPStatusLastSuccessfulSyncKey = @"LastSuccessfulSync";
NSString* const kGPStatusLastAttemptedSyncKey = @"LastAttemptedSync";
NSString* const kGPStatusErrorMessageKey = @"LastError";


@interface GPSourceStatus (Private)

- (NSString*)processIdString;
- (NSString*)statusFilePath;
- (void)persistStatus;
- (void)loadStatus;
- (void)backingFileChanged:(NSNotification*)notification;

@end

@implementation GPSourceStatus

GTMOBJECT_SINGLETON_BOILERPLATE(GPSourceStatus, sharedSourceStatus)

- (id)init {
  if ((self = [super init])) {
    [self loadStatus];
    [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                        selector:@selector(backingFileChanged:)
                                                            name:kGPPrecipitateStatusChanged
                                                          object:nil];
  }
  return self;
}

- (void)dealloc {
  [status_ release];
  [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];

  [super dealloc];
}

- (void)backingFileChanged:(NSNotification*)notification {
  if (![[notification object] isEqualToString:[self processIdString]])
    [self loadStatus];
}

- (NSString*)processIdString {
  return [NSString stringWithFormat:@"%d", [[NSProcessInfo processInfo] processIdentifier]];
}

- (NSString*)statusFilePath {
  static NSString* sStatusFilePath = nil;
  if (!sStatusFilePath) {
    sStatusFilePath = [[[@"~/Library/Caches/Metadata/Precipitate" stringByExpandingTildeInPath]
                        stringByAppendingPathComponent:kGPPrecipitateStatusFile] retain];
  }
  return sStatusFilePath;
}

- (void)loadStatus {
  NSString* statusFilePath = [self statusFilePath];
  NSMutableDictionary* newStatus = nil;
  if ([[NSFileManager defaultManager] fileExistsAtPath:statusFilePath])
    newStatus = [[NSMutableDictionary alloc] initWithContentsOfFile:statusFilePath];
  if (!newStatus)
    newStatus = [[NSMutableDictionary alloc] init];
  [self willChangeValueForKey:@"allStatuses"];
  [status_ release];
  status_ = newStatus;
  [self didChangeValueForKey:@"allStatuses"];
}

- (void)persistStatus {
  NSString* filePath = [self statusFilePath];
  [[NSFileManager defaultManager] createDirectoryAtPath:[filePath stringByDeletingLastPathComponent]
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
  [status_ writeToFile:filePath atomically:YES];
  [[NSDistributedNotificationCenter defaultCenter] postNotificationName:kGPPrecipitateStatusChanged
                                                                 object:[self processIdString]];
}

- (void)setLastSyncTime:(NSDate*)time
                  error:(NSError*)error
              forSource:(NSString*)sourceId {
  NSMutableDictionary* sourceStatus = [[[status_ objectForKey:sourceId] mutableCopy] autorelease];
  if (!sourceStatus)
    sourceStatus = [NSMutableDictionary dictionary];
  [sourceStatus setObject:time forKey:kGPStatusLastAttemptedSyncKey];
  if (error) {
    [sourceStatus setObject:[error localizedDescription] forKey:kGPStatusErrorMessageKey];
  } else {
    [sourceStatus setObject:time forKey:kGPStatusLastSuccessfulSyncKey];
    [sourceStatus removeObjectForKey:kGPStatusErrorMessageKey];
  }

  [self willChangeValueForKey:@"allStatuses"];
  [status_ setObject:sourceStatus forKey:sourceId];
  [self didChangeValueForKey:@"allStatuses"];
  [self persistStatus];
}

- (void)clearSyncStatusForSource:(NSString*)sourceId {
  [self willChangeValueForKey:@"allStatuses"];
  [status_ removeObjectForKey:sourceId];
  [self didChangeValueForKey:@"allStatuses"];
  [self persistStatus];
}

- (NSDictionary*)statusForSource:(NSString*)sourceId {
  return [status_ objectForKey:sourceId];
}

- (NSDictionary*)allStatuses {
  return [[status_ copy] autorelease];
}

@end
