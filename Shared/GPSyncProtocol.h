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

#define kGPMDItemModificationDate @"PrecipitateModTime"
#define kGPMDItemUID @"PrecipitateUID"
// 10.4 doesn't have kMDItemURL, so define it ourselves. Use a different name
// to avoid conflicts in builds using the 10.5 SDK but targetting 10.4.
#define kGPMDItemURL CFSTR("kMDItemURL")


@protocol GPSyncSource;


// Implemented by an object loading and managing source plugins.
@protocol GPSyncManager <NSObject>

- (void)basicItemsInfo:(NSArray*)items
      fetchedForSource:(id<GPSyncSource>)source;

- (void)fullItemsInfo:(NSArray*)items
     fetchedForSource:(id<GPSyncSource>)source;

- (void)fullItemsInfoFetchCompletedForSource:(id<GPSyncSource>)source;

- (void)infoFetchFailedForSource:(id<GPSyncSource>)source
                       withError:(NSError*)error;

@end


// Implemented by sources.
@protocol GPSyncSource <NSObject>

// Create a source with the given manager. The source should not retain
// the manager (which is guaranteed to outlive the source).
- (id)initWithManager:(id<GPSyncManager>)manager;

// Fetch the basic info of all items currently in the source, and then
// asynchronously return it to the manager as an array of dictionaries using
// basicItemsInfo:fetchedForSource:
// Each dictionary must contain at least kMDItemTitle, kGPMDItemUID, and
// kGPMDItemModificationDate. Anything else which is expensive to fetch can be
// delayed until fetchFullInfoForItems:
//
// The source must either call basicItemsInfo:fetchedForSource: or
// infoFetchFailedForSource:withError: in response to this message.
- (void)fetchAllItemsBasicInfo;

// Fetch the full info (metadata and content) for each of the given items--which
// are dictionaries of basic info--and asynchronously return it to the manager
// as arrays of dictionaries using one or more calls to
// fullItemsInfo:fetchedForSource:. The source may break its results into
// however many calls are convenient for it, anywhere from one call with the
// entire array to one callback per item each with an array containing only that
// item's info.
// 
// The source must call either fullItemsInfoFetchCompletedForSource: or
// infoFetchFailedForSource:withError: exactly once in response to this method.
// No further callbacks should be made once either has been called (e.g., do
// not return an error for each item; once an error occurs, stop processing).
- (void)fetchFullInfoForItems:(NSArray*)items;

// Returns the extension to use for the cache file.
- (NSString*)cacheFileExtensionForItem:(NSDictionary*)item;

// Returns all the extensions handled by the source (i.e., everything that could
// be returned by cacheFileExtensionForItem:).
- (NSArray*)itemExtensions;

// The user-visible display name for the source.
- (NSString*)displayName;

@end

@interface NSObject (PrecipitateSourceOptionalMethods)

// If this is unimplemented, items will be opened by opening their kGPMDItemURL.
// Return YES if opening succeeded, NO otherwise.
- (BOOL)openPrecipitateItem:(NSDictionary*)item;

@end
