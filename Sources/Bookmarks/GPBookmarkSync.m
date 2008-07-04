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

#import "GPBookmarkSync.h"
#import "GPKeychainItem.h"
#import "SharedConstants.h"

@interface GPBookmarkSync (Private)

- (void)parseBookmarksFromData:(NSData*)data;

@end

@implementation GPBookmarkSync

- (id)initWithManager:(id<GPSyncManager>)manager {
  if ((self = [super init])) {
    manager_ = manager;
  }
  return self;
}

- (void)dealloc {
  [bookmarkData_ release];
  [super dealloc];
}

- (void)fetchAllItemsBasicInfo {
  NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.google.com/bookmarks/lookup?output=rss"]];
  [NSURLConnection connectionWithRequest:request delegate:self];
}

- (void)fetchFullInfoForItems:(NSArray*)items {
  // All the data is already present, so nothing to do.
  [manager_ fullItemsInfo:items fetchedForSource:self];
  [manager_ fullItemsInfoFetchCompletedForSource:self];
}

- (NSString*)cacheFileExtensionForItem:(NSDictionary*)item {
  return @"webbookmark"; // so we go in through the OS bookmark importer
}

- (NSArray*)itemExtensions {
  return [NSArray arrayWithObject:@"webbookmark"];
}

- (NSString*)displayName {
  return @"Google Bookmarks";
}

#pragma mark -

- (void)parseBookmarksFromData:(NSData*)data {
  NSXMLDocument* bookmarksXML = [[[NSXMLDocument alloc] initWithData:data
                                                             options:0
                                                               error:nil] autorelease];
  NSArray* bookmarkNodes = [bookmarksXML nodesForXPath:@"//item" error:NULL];
  NSMutableArray* bookmarkItems = [NSMutableArray array];
  NSEnumerator* nodeEnumerator = [bookmarkNodes objectEnumerator];
  NSXMLNode* bookmark;
  while ((bookmark = [nodeEnumerator nextObject])) {
    NSMutableDictionary* bookmarkInfo = [NSMutableDictionary dictionary];
    NSEnumerator* infoNodeEnumerator = [[bookmark children] objectEnumerator];
    NSXMLNode* infoNode;
    while ((infoNode = [infoNodeEnumerator nextObject])) {
      if ([[infoNode name] isEqualToString:@"title"]) {
        [bookmarkInfo setObject:[infoNode stringValue] forKey:(NSString*)kMDItemTitle];
        [bookmarkInfo setObject:[infoNode stringValue] forKey:@"Name"]; // for the webbookmark importer
      } else if ([[infoNode name] isEqualToString:@"link"]) {
        [bookmarkInfo setObject:[infoNode stringValue] forKey:(NSString*)kGPMDItemURL];
        [bookmarkInfo setObject:[infoNode stringValue] forKey:@"URL"]; // for the webbookmark importer
      } else if ([[infoNode name] isEqualToString:@"pubDate"]) {
        [bookmarkInfo setObject:[NSDate dateWithNaturalLanguageString:[infoNode stringValue]]
                         forKey:kGPMDItemModificationDate];
      } else if ([[infoNode name] isEqualToString:@"guid"]) {
        [bookmarkInfo setObject:[infoNode stringValue] forKey:kGPMDItemUID];
      }
    }
    [bookmarkItems addObject:bookmarkInfo];
  }
  [manager_ basicItemsInfo:bookmarkItems fetchedForSource:self];
}

#pragma mark -

- (void)connection:(NSURLConnection*)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge*)challenge {
  GPKeychainItem* loginCredentials = [GPKeychainItem keychainItemForService:kPrecipitateGoogleAccountKeychainServiceName];
  if (!loginCredentials || [challenge previousFailureCount] > 1) {
    [[challenge sender] cancelAuthenticationChallenge:challenge];
  } else {
    [[challenge sender] useCredential:[NSURLCredential credentialWithUser:[loginCredentials username]
                                                                 password:[loginCredentials password]
                                                              persistence:NSURLCredentialPersistenceForSession]
           forAuthenticationChallenge:challenge];
  }
}

- (void)connection:(NSURLConnection*)connection didReceiveResponse:(NSURLResponse*)response {
  [bookmarkData_ release];
  bookmarkData_ = [[NSMutableData alloc] init];
}

- (void)connection:(NSURLConnection*)connection didReceiveData:(NSData*)data {
  [bookmarkData_ appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection*)connection {
  [self parseBookmarksFromData:bookmarkData_];
  [bookmarkData_ release];
  bookmarkData_ = nil;
}

- (void)connection:(NSURLConnection*)connection didFailWithError:(NSError*)error {
  [bookmarkData_ release];
  bookmarkData_ = nil;
  [manager_ infoFetchFailedForSource:self withError:error];
}

@end
