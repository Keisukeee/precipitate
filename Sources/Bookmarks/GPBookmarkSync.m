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
#import "GTMHTTPFetcher.h"
#import "SharedConstants.h"

static NSString* const kBookmarkURLFormat = @"https://www.google.com/bookmarks/lookup?output=rss&start=%d";

@interface GPBookmarkSync (Private)

- (void)requestBookmarksStartingFrom:(int)start;
- (NSArray*)bookmarksFromData:(NSData*)data;

@end

@implementation GPBookmarkSync

- (id)initWithManager:(id<GPSyncManager>)manager {
  if ((self = [super init])) {
    manager_ = manager;
    bookmarks_ = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void)dealloc {
  [bookmarks_ release];
  [super dealloc];
}

- (void)fetchAllItemsBasicInfo {
  [bookmarks_ removeAllObjects];
  [self requestBookmarksStartingFrom:0];
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

- (void)requestBookmarksStartingFrom:(int)start {
  NSString* requestURI = [NSString stringWithFormat:kBookmarkURLFormat, start];
  NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:requestURI]];
  GTMHTTPFetcher* fetcher = [GTMHTTPFetcher httpFetcherWithRequest:request];
  GPKeychainItem* loginCredentials = [GPKeychainItem keychainItemForService:kPrecipitateGoogleAccountKeychainServiceName];
  if (loginCredentials) {
    [fetcher setCredential:[NSURLCredential credentialWithUser:[loginCredentials username]
                                                      password:[loginCredentials password]
                                                   persistence:NSURLCredentialPersistenceForSession]];
  }
  [fetcher setIsRetryEnabled:YES];
  [fetcher setMaxRetryInterval:60.0];
  [fetcher beginFetchWithDelegate:self
                didFinishSelector:@selector(fetch:finishedWithData:)
                  didFailSelector:@selector(fetch:failedWithError:)];
}

- (NSArray*)bookmarksFromData:(NSData*)data {
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
  return bookmarkItems;
}

#pragma mark -

- (void)fetch:(GTMHTTPFetcher *)fetcher finishedWithData:(NSData *)data {
  NSArray* newBookmarks = [self bookmarksFromData:data];
  // The bookmarks feed returns chunks, not everything, so unless there were no
  // bookmarks in the response we assume there are more. Once we hit an empty
  // feed, we can be sure we've walked the entire list.
  if ([newBookmarks count] > 0) {
    [bookmarks_ addObjectsFromArray:newBookmarks];
    [self requestBookmarksStartingFrom:[bookmarks_ count]];
  } else {
    [manager_ basicItemsInfo:bookmarks_ fetchedForSource:self];
    [bookmarks_ removeAllObjects];
  }
}

- (void)fetch:(GTMHTTPFetcher *)fetcher failedWithError:(NSError *)error {
  [manager_ infoFetchFailedForSource:self withError:error];
  [bookmarks_ removeAllObjects];
}

@end
