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

// Source status keys:
extern NSString* const kGPStatusLastSuccessfulSyncKey;
extern NSString* const kGPStatusLastAttemptedSyncKey;
extern NSString* const kGPStatusErrorMessageKey;

// Manages access to the shared information about the status of each source's
// last sync. Changes made in other processes will be noticed immediately, and
// can be observed through |allStatuses|.
@interface GPSourceStatus : NSObject {
  NSMutableDictionary* status_;
}

// Returns the shared source status object.
+ (GPSourceStatus*)sharedSourceStatus;

// Set the last sync time and status for a given source. If error is nil, the
// sync is treated as successfull, otherwise it's treated as a failure.
- (void)setLastSyncTime:(NSDate*)time
                  error:(NSError*)error
              forSource:(NSString*)sourceId;

// Clears the sync status for the given source.
- (void)clearSyncStatusForSource:(NSString*)sourceId;

// Returns the status dictionary for the given source (see keys above).
- (NSDictionary*)statusForSource:(NSString*)sourceId;

// Returns all the source status dictionaries, keyed by source identifiers.
// |allStatuses| is KVO-compliant.
- (NSDictionary*)allStatuses;

@end
