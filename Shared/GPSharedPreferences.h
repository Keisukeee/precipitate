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

#import <Cocoa/Cocoa.h>

NSString* const kGPSourcePrefDisplayNameKey;
NSString* const kGPSourcePrefEnabledKey;

// Provides an interface to the shared preferences domain used by various
// parts of Precipitate. Note that this class does not allow observing any
// pref values for changes made either internally or in another process.
@interface GPSharedPreferences : NSObject {
}

// Returns the shared preferences object
+ (GPSharedPreferences*)sharedPreferences;

// Sets the list of available sources. |sourceInfo| should be a dictionary
// mapping the identifier of each available source to an info dictionary
// containing its display name.
// The enabled state for any source that was previously present will be
// preserved; new sources will default to off.
- (void)setAvailableSources:(NSDictionary*)sourceInfo;

// Returns a dictionary of information about available sources, keyed by
// source identifier.
- (NSDictionary*)availableSources;

// Sets the enabled status for the given source to |enabled|.
- (void)setEnabled:(BOOL)enabled forSource:(NSString*)sourceId;

// Gets the enabled status for the given source
- (BOOL)sourceIsEnabled:(NSString*)sourceId;

// Gets the interval for refreshing all the sources.
// This method internally enforces a sane lower-bound on the interval
- (NSTimeInterval)updateInterval;

// Gets the bundle id of the custom launching application for the given source.
- (NSString*)customLauncherForSource:(NSString*)sourceId;

@end
