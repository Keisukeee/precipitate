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

#import "GPDocsSync.h"
#import "DocsInfoKeys.h"
#import "SharedConstants.h"
#import "GPKeychainItem.h"

@interface GPDocsSync (Private)

- (NSArray*)peopleStringsForGDataPeople:(NSArray*)people;
- (NSDictionary*)dictionaryForDoc:(GDataEntryDocBase*)doc;
- (NSString*)contentForDoc:(NSDictionary*)docInfo;
- (void)inflateDocuments:(NSArray*)documents;

@end

@implementation GPDocsSync

- (id)initWithManager:(id<GPSyncManager>)manager
{
  if ((self = [super init])) {
    manager_ = manager;
  }
  return self;
}

- (void)fetchAllItemsBasicInfo
{
  GPKeychainItem* loginCredentials =
    [GPKeychainItem keychainItemForService:kPrecipitateGoogleAccountKeychainServiceName];
  if (!loginCredentials) {
    NSString* errorString =
      [[NSBundle bundleForClass:[self class]] localizedStringForKey:@"NoLoginInfo"
                                                              value:@"NoLoginInfo"
                                                              table:@"GoogleDocs"];
    NSDictionary* errorInfo = [NSDictionary dictionaryWithObject:errorString
                                                          forKey:NSLocalizedDescriptionKey];
    [manager_ infoFetchFailedForSource:self withError:[NSError errorWithDomain:@"LoginFailure"
                                                                          code:403
                                                                      userInfo:errorInfo]];
    return;
  }

  NSString* username = [loginCredentials username];
  NSString* password = [loginCredentials password];

  [docService_ autorelease];
  docService_ = [[GDataServiceGoogleDocs alloc] init];
  [docService_ setUserAgent:@"Google-Precipitate-1.0.0"];
  [docService_ setUserCredentialsWithUsername:username password:password];

  [spreadsheetService_ autorelease];
  spreadsheetService_ = [[GDataServiceGoogleSpreadsheet alloc] init];
  [spreadsheetService_ setUserAgent:@"Google-Precipitate-1.0.0"];
  [spreadsheetService_ setUserCredentialsWithUsername:username password:password];

  // We don't need this information, but we need to call a fetch method to
  // ensure that the service is primed with the authorization ticket for later
  // requests.
  [spreadsheetService_ fetchSpreadsheetFeedWithURL:[NSURL URLWithString:kGDataGoogleSpreadsheetsPrivateFullFeed]
                                          delegate:self
                                 didFinishSelector:@selector(dummySpreadsheetFetch:finishedWithObject:)
                                   didFailSelector:@selector(dummySpreadsheetFetch:finishedWithObject:)];

  // Get the data we actually want. The callbacks will report to the manager
  NSURL* docURL = [NSURL URLWithString:kGDataGoogleDocsDefaultPrivateFullFeed];
  [docService_ fetchDocsFeedWithURL:docURL
                           delegate:self
                  didFinishSelector:@selector(serviceTicket:finishedWithObject:)
                    didFailSelector:@selector(serviceTicket:failedWithError:)];
}

- (void)fetchFullInfoForItems:(NSArray*)items
{
  [self inflateDocuments:items];
}

- (NSString*)cacheFileExtensionForItem:(NSDictionary*)item {
  NSArray* categories = [item objectForKey:kDocDictionaryCategoriesKey];
  if ([categories containsObject:kDocCategoryDocument])
    return @"gdocdocument";
  else if ([categories containsObject:kDocCategorySpreadsheet])
    return @"gdocspreadsheet";
  else if ([categories containsObject:kDocCategoryPresentation])
    return @"gdocpresentation";
  return @"gdoc";
}

- (NSArray*)itemExtensions {
  return [NSArray arrayWithObjects:@"gdocdocument", @"gdocspreadsheet", @"gdocpresentation", @"gdoc", nil];
}

- (NSString*)displayName {
  return @"Google Docs";
}

#pragma mark -

- (void)dealloc {
  [docService_ release];
  [spreadsheetService_ release];
  [super dealloc];
}

- (void)serviceTicket:(GDataServiceTicket *)ticket
   finishedWithObject:(GDataFeedDocList *)docList {
  NSMutableDictionary* docsById = [NSMutableDictionary dictionary];
  NSEnumerator* docEnumerator = [[docList entries] objectEnumerator];
  GDataEntryDocBase* doc;
  while ((doc = [docEnumerator nextObject])) {
    NSDictionary* docInfo = [self dictionaryForDoc:doc];
    [docsById setObject:docInfo forKey:[docInfo objectForKey:kGPMDItemUID]];
  }

  [manager_ basicItemsInfo:[docsById allValues] fetchedForSource:self];
}

- (void)serviceTicket:(GDataServiceTicket *)ticket
      failedWithError:(NSError *)error {
  if ([error code] == 403) {
    NSString* errorString =
      [[NSBundle bundleForClass:[self class]] localizedStringForKey:@"LoginFailed"
                                                              value:@"LoginFailed"
                                                              table:@"GoogleDocs"];
    NSDictionary* errorInfo = [NSDictionary dictionaryWithObject:errorString
                                                          forKey:NSLocalizedDescriptionKey];
    [manager_ infoFetchFailedForSource:self withError:[NSError errorWithDomain:@"LoginFailure"
                                                                          code:403
                                                                      userInfo:errorInfo]];
  } else {
    [manager_ infoFetchFailedForSource:self withError:error];
  }
}

- (void)dummySpreadsheetFetch:(GDataServiceTicket *)ticket
           finishedWithObject:(id)foo {
  // Do nothing; see the comment in fetchAllItemsBasicInfo
}

- (void)inflateDocuments:(NSArray*)docs {
  NSMutableArray* inflatedDocs = [NSMutableArray arrayWithCapacity:[docs count]];
  NSEnumerator* docEnumerator = [docs objectEnumerator];
  NSDictionary* docInfo;
  while ((docInfo = [docEnumerator nextObject])) {
    NSMutableDictionary* fullDocInfo = [[docInfo mutableCopy] autorelease];
    [fullDocInfo setObject:[self contentForDoc:docInfo] forKey:(NSString*)kMDItemTextContent];
    [inflatedDocs addObject:fullDocInfo];
  }
  [manager_ fullItemsInfo:inflatedDocs fetchedForSource:self];
}

- (NSArray*)peopleStringsForGDataPeople:(NSArray*)people {
  NSMutableArray* peopleStrings = [NSMutableArray arrayWithCapacity:[people count]];
  NSEnumerator* enumerator = [people objectEnumerator];
  GDataPerson* person;
  while ((person = [enumerator nextObject])) {
    [peopleStrings addObject:[NSString stringWithFormat:@"%@ <%@>",
                              [person name], [person email]]];
  }
  return peopleStrings;
}

- (NSDictionary*)dictionaryForDoc:(GDataEntryDocBase*)doc {
  return [NSDictionary dictionaryWithObjectsAndKeys:
                                            [doc identifier], kDocDictionaryIdentifierPathKey,
                        [[doc identifier] lastPathComponent], kGPMDItemUID,
                   [NSNumber numberWithBool:[doc isStarred]], kDocDictionaryStarredKey,
                                   [[doc title] stringValue], (NSString*)kMDItemTitle,
                                    [[doc updatedDate] date], kGPMDItemModificationDate,
            [self peopleStringsForGDataPeople:[doc authors]], (NSString*)kMDItemAuthors,
                               [[[doc links] HTMLLink] href], (NSString*)kGPMDItemURL,
                                   [[doc content] sourceURI], kDocDictionarySourceURIKey,
                     [[doc categories] valueForKey:@"label"], kDocDictionaryCategoriesKey,
                                                              nil];
}

- (NSString*)contentForDoc:(NSDictionary*)docInfo {
  NSString* content = nil;

  NSArray* categories = [docInfo objectForKey:kDocDictionaryCategoriesKey];
  if ([categories containsObject:kDocCategoryDocument]) {
    NSURL* sourceURL = [NSURL URLWithString:[docInfo objectForKey:kDocDictionarySourceURIKey]];
    NSError* error = nil;
    NSURLResponse* response = nil;
    NSData* data = nil;
    NSURLRequest* request = [docService_ requestForURL:sourceURL
                                                  ETag:nil
                                            httpMethod:nil];
    data = [NSURLConnection sendSynchronousRequest:request
                                 returningResponse:&response
                                             error:&error];
    if (data) {
      NSXMLDocument* contentXML = [[[NSXMLDocument alloc] initWithData:data
                                                               options:NSXMLDocumentTidyHTML
                                                                 error:NULL] autorelease];
      NSXMLNode* body = [[contentXML nodesForXPath:@"//body" error:NULL] lastObject];
      if (body)
        content = [body stringValue];
    } else {
      NSLog(@"Docs source couldn't get data: %@ (%@)", error, response);
    }
  }
  else if ([categories containsObject:kDocCategorySpreadsheet]) {
    // Spreadsheets don't honor the GData auth, so we'll get a login page from
    // the docs method unless there happens to be a valid cookie in the OS
    // cookie store (e.g., from Safari), so pull the content out of the cells.
    NSString* sourceURI = [docInfo objectForKey:kDocDictionarySourceURIKey];
    NSRange keyLabelRange = [sourceURI rangeOfString:@"key="];
    if (keyLabelRange.location == NSNotFound)
      return @"";
    NSString* key = [sourceURI substringFromIndex:(keyLabelRange.location + keyLabelRange.length)];
    NSRange ampersandRange = [key rangeOfString:@"&"];
    if (ampersandRange.location != NSNotFound)
      key = [key substringWithRange:NSMakeRange(0, ampersandRange.location - 1)];

    NSString* worksheetFeedURI =
      [NSString stringWithFormat:@"http://spreadsheets.google.com/feeds/worksheets/%@/private/full", key];
    NSURLRequest *request = [spreadsheetService_ requestForURL:[NSURL URLWithString:worksheetFeedURI]
                                                          ETag:nil
                                                    httpMethod:nil];
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *worksheetFeedData = [NSURLConnection sendSynchronousRequest:request
                                                      returningResponse:&response
                                                                  error:&error];
    if (!worksheetFeedData)
      return @"";
    NSXMLDocument* worksheetFeed = [[[NSXMLDocument alloc] initWithData:worksheetFeedData
                                                                options:0
                                                                  error:nil] autorelease];
    int worksheetCount = [[worksheetFeed nodesForXPath:@"//entry" error:NULL] count];

    NSMutableString* contentAccumulator = [NSMutableString string];
    for (int worksheetIndex = 1; worksheetIndex <= worksheetCount; ++worksheetIndex) {
      NSString* contentFeedURI =
      [NSString stringWithFormat:@"http://spreadsheets.google.com/feeds/cells/%@/%d/private/full",
                                  key,
                                  worksheetIndex];
      request = [spreadsheetService_ requestForURL:[NSURL URLWithString:contentFeedURI]
                                              ETag:nil
                                        httpMethod:nil];
      NSData *contentFeedData = [NSURLConnection sendSynchronousRequest:request
                                                      returningResponse:&response
                                                                  error:&error];
      if (!contentFeedData)
        continue;
      NSXMLDocument* contentFeed = [[[NSXMLDocument alloc] initWithData:contentFeedData
                                                                options:0
                                                                  error:nil] autorelease];
      NSArray* contentNodes = [contentFeed nodesForXPath:@"//content" error:NULL];
      NSEnumerator* nodeEnumerator = [contentNodes objectEnumerator];
      NSXMLNode* node;
      while ((node = [nodeEnumerator nextObject])) {
        [contentAccumulator appendString:@" "];
        [contentAccumulator appendString:[node stringValue]];
      }
    }

    content = contentAccumulator;
  } else {
  // TODO: presentations, which isn't currently possible
  }

  if (!content)
    content = @"";
  return content;
}

@end
