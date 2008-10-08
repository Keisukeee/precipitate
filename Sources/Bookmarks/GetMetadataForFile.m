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

#include <Foundation/Foundation.h>
#include <CoreServices/CoreServices.h>
#include "GPSyncProtocol.h"

Boolean GetMetadataForFile(void* thisInterface, 
			   CFMutableDictionaryRef attributes, 
			   CFStringRef contentTypeUTI,
			   CFStringRef pathToFile)
{
  NSMutableDictionary* outDict = (NSMutableDictionary*)attributes;
  NSDictionary* fileInfo = [NSDictionary dictionaryWithContentsOfFile:(NSString*)pathToFile];
  if (!fileInfo)
    return FALSE;

  // Push any kMDItem* values directly into the output dictionary.
  NSEnumerator* keyEnumerator = [fileInfo keyEnumerator];
  NSString* metadataKey;
  while ((metadataKey = [keyEnumerator nextObject])) {
    if ([metadataKey hasPrefix:@"kMDItem"]) {
      [outDict setObject:[fileInfo objectForKey:metadataKey]
                  forKey:metadataKey];
    }
  }

  // Handle a few custom mappings.
  [outDict setObject:[NSDictionary dictionaryWithObject:[fileInfo objectForKey:(NSString*)kMDItemTitle]
                                                 forKey:@""]
              forKey:(NSString*)kMDItemDisplayName];
  
  return TRUE;
}
