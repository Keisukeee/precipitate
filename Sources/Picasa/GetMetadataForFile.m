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
#include "PWAInfoKeys.h"
#include "GPSyncProtocol.h"

Boolean GetMetadataForFile(void* thisInterface, 
			   CFMutableDictionaryRef attributes, 
			   CFStringRef contentTypeUTI,
			   CFStringRef pathToFile)
{
  NSDictionary* fileInfo = [NSDictionary dictionaryWithContentsOfFile:(NSString*)pathToFile];
  if (!fileInfo)
    return FALSE;

  [(NSMutableDictionary*)attributes setObject:[fileInfo objectForKey:(NSString*)kMDItemTitle]
                                       forKey:(NSString*)kMDItemTitle];
  [(NSMutableDictionary*)attributes setObject:[NSDictionary dictionaryWithObject:[fileInfo objectForKey:(NSString*)kMDItemTitle]
                                                                          forKey:@""]
                                       forKey:(NSString*)kMDItemDisplayName];
  [(NSMutableDictionary*)attributes setObject:[fileInfo objectForKey:(NSString*)kMDItemDescription]
                                       forKey:(NSString*)kMDItemDescription];
  [(NSMutableDictionary*)attributes setObject:[fileInfo objectForKey:(NSString*)kMDItemAuthors]
                                       forKey:(NSString*)kMDItemAuthors];
  // There's no generic location field, so just use comment.
  [(NSMutableDictionary*)attributes setObject:[fileInfo objectForKey:kAlbumDictionaryLocationKey]
                                       forKey:(NSString*)kMDItemComment];
  [(NSMutableDictionary*)attributes setObject:[fileInfo objectForKey:kGPMDItemModificationDate]
                                       forKey:(NSString*)kMDItemContentModificationDate];
  [(NSMutableDictionary*)attributes setObject:[fileInfo objectForKey:(NSString*)kMDItemContentCreationDate]
                                       forKey:(NSString*)kMDItemContentCreationDate];
  
  return TRUE;
}
