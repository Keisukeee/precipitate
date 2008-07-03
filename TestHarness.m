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

#import "TestHarness.h"


@implementation TestHarness

- (void)awakeFromNib {
  NSArray* arguments = [[NSProcessInfo processInfo] arguments];
  if ([arguments count] < 2) {
    NSLog(@"Usage: %@ <path to source> [<path to another source> ...]", [arguments objectAtIndex:0]);
    [NSApp terminate:self];
  }
  NSEnumerator* argumentEnumerator = [[arguments subarrayWithRange:NSMakeRange(1, [arguments count] - 1)] objectEnumerator];
  NSString* bundlePath;
  while ((bundlePath = [argumentEnumerator nextObject])) {
    NSBundle* pluginBundle = [NSBundle bundleWithPath:bundlePath];
    if ([pluginBundle isLoaded])
      continue;
    if (!pluginBundle || ![pluginBundle load]) {
      NSLog(@"Unable to load source '%@'; it does not appear to be a plugin", bundlePath);
      continue;
    }
    Class pluginClass = [pluginBundle principalClass];
    if (![pluginClass conformsToProtocol:@protocol(GPSyncSource)]) {
      NSLog(@"Unable to load source '%@'; principal class %@ is not a GPSyncSource", bundlePath, NSStringFromClass(pluginClass));
      continue;
    }
    NSLog(@"Loading source '%@'", bundlePath);
    @try {
      [[[pluginClass alloc] initWithManager:self] fetchAllItemsBasicInfo];
    } @catch (id exception) {
      NSLog(@"Failed to load source '%@'; caught exception: %@", bundlePath, exception);
    }
  }
}

- (void)basicItemsInfo:(NSArray*)items
      fetchedForSource:(id<GPSyncSource>)source {
  NSLog(@"Source '%@' returned basic items: %@", source, items);
  [source fetchFullInfoForItems:items];
}

- (void)fullItemsInfo:(NSArray*)items
     fetchedForSource:(id<GPSyncSource>)source {
  NSLog(@"Source '%@' returned full item info: %@", source, items);
}

- (void)fullItemsInfoFetchCompletedForSource:(id<GPSyncSource>)source {
  NSLog(@"Source '%@' reports finished", source);

  [NSApp terminate:self];
}

- (void)infoFetchFailedForSource:(id<GPSyncSource>)source
                       withError:(NSError*)error {
  NSLog(@"Source %@ reported error: %@", source, error);

  [NSApp terminate:self];
}


@end
