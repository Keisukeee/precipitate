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
- (NSDictionary*)dictionaryForEntry:(GDataEntryBase*)doc;
- (void)inflateNextDoc;
- (void)fetchContentForNextDoc;
- (void)retrievedContentForNextDoc:(NSString*)content;

@end

@implementation GPDocsSync

- (id)initWithManager:(id<GPSyncManager>)manager
{
  if ((self = [super init])) {
    manager_ = manager;
  }
  return self;
}

- (void)dealloc {
  [docService_ release];
  [spreadsheetService_ release];
  [docsToInflate_ release];
  [super dealloc];
}

- (void)fetchAllItemsBasicInfo
{
  GPKeychainItem* loginCredentials =
    [GPKeychainItem keychainItemForService:kPrecipitateGoogleAccountKeychainServiceName];
  if (!loginCredentials) {
    NSString* errorString = NSLocalizedString(@"NoLoginInfo", nil);
    NSDictionary* errorInfo = [NSDictionary dictionaryWithObject:errorString
                                                          forKey:NSLocalizedDescriptionKey];
    [manager_ infoFetchFailedForSource:self withError:[NSError errorWithDomain:@"LoginFailure"
                                                                          code:403
                                                                      userInfo:errorInfo]];
    return;
  }

  NSString* username = [loginCredentials username];
  NSString* password = [loginCredentials password];

  // If the debugging flag to enable logging is set, do so.
  if ([[[NSUserDefaults standardUserDefaults] objectForKey:@"EnableGDataHTTPLogging"] boolValue])
    [GDataHTTPFetcher setIsLoggingEnabled:YES];
  
  [docService_ autorelease];
  docService_ = [[GDataServiceGoogleDocs alloc] init];
  [docService_ setUserAgent:kPrecipitateUserAgent];
  [docService_ setUserCredentialsWithUsername:username password:password];
  [docService_ setIsServiceRetryEnabled:YES];
  [docService_ setServiceShouldFollowNextLinks:YES];

  [spreadsheetService_ autorelease];
  spreadsheetService_ = [[GDataServiceGoogleSpreadsheet alloc] init];
  [spreadsheetService_ setUserAgent:kPrecipitateUserAgent];
  [spreadsheetService_ setUserCredentialsWithUsername:username password:password];
  [spreadsheetService_ setIsServiceRetryEnabled:YES];

  // We don't need this information, but we need to call a fetch method to
  // ensure that the service is primed with the authorization ticket for later
  // requests.
  NSString* spreadsheetFeedURI = kGDataGoogleSpreadsheetsPrivateFullFeed;
  if ([spreadsheetFeedURI hasPrefix:@"http:"])
    spreadsheetFeedURI = [@"https:" stringByAppendingString:[spreadsheetFeedURI substringFromIndex:5]];
  [spreadsheetService_ fetchSpreadsheetFeedWithURL:[NSURL URLWithString:spreadsheetFeedURI]
                                          delegate:self
                                 didFinishSelector:nil
                                   didFailSelector:nil];

  // Get the data we actually want. The callbacks will report to the manager
  NSString* docsFeedURI = kGDataGoogleDocsDefaultPrivateFullFeed;
  if ([docsFeedURI hasPrefix:@"http:"])
    docsFeedURI = [@"https:" stringByAppendingString:[docsFeedURI substringFromIndex:5]];
  [docService_ fetchDocsFeedWithURL:[NSURL URLWithString:docsFeedURI]
                           delegate:self
                  didFinishSelector:@selector(serviceTicket:finishedWithObject:)
                    didFailSelector:@selector(serviceTicket:failedWithError:)];
}

- (void)fetchFullInfoForItems:(NSArray*)items
{
  // We don't want to block the runloop for the whole time we are fetching
  // content, so we work through the list one entry at a time. Each time we
  // finish fetching one we'll start another (or report completion), so all we
  // have to do here is kick off the process.
  [docsToInflate_ release];
  docsToInflate_ = [items mutableCopy];
  [self inflateNextDoc];
}

- (NSString*)cacheFileExtensionForItem:(NSDictionary*)item {
  NSArray* categories = [item objectForKey:kDocDictionaryCategoriesKey];
  if ([categories containsObject:kDocCategoryDocument])
    return @"gdocdocument";
  else if ([categories containsObject:kDocCategorySpreadsheet])
    return @"gdocspreadsheet";
  else if ([categories containsObject:kDocCategoryPresentation])
    return @"gdocpresentation";
  else if ([categories containsObject:kDocCategoryPDF])
    return @"gdocpdf";
  return @"gdoc";
}

- (NSArray*)itemExtensions {
  return [NSArray arrayWithObjects:
            @"gdocdocument",
            @"gdocspreadsheet",
            @"gdocpresentation",
            @"gdocpdf",
            @"gdoc",
            nil];
}

- (NSString*)displayName {
  return @"Google Docs";
}

#pragma mark Basic Info Fetching

- (void)serviceTicket:(GDataServiceTicket *)ticket
   finishedWithObject:(GDataFeedDocList *)docList {
  NSMutableDictionary* docsById = [NSMutableDictionary dictionary];
  for (GDataEntryBase* entry in [docList entries]) {
    @try {
      NSDictionary* docInfo = [self dictionaryForEntry:entry];
      if (docInfo)
        [docsById setObject:docInfo forKey:[docInfo objectForKey:kGPMDItemUID]];
      else
        NSLog(@"Couldn't get info for Docs entry: %@", entry);
    } @catch (id exception) {
      NSLog(@"Caught exception while processing base Docs info: %@", exception);
    }
  }

  [manager_ basicItemsInfo:[docsById allValues] fetchedForSource:self];
}

- (void)serviceTicket:(GDataServiceTicket *)ticket
      failedWithError:(NSError *)error {
  if ([error code] == 403) {
    NSString* errorString = NSLocalizedString(@"LoginFailed", nil);
    NSDictionary* errorInfo = [NSDictionary dictionaryWithObject:errorString
                                                          forKey:NSLocalizedDescriptionKey];
    [manager_ infoFetchFailedForSource:self withError:[NSError errorWithDomain:@"LoginFailure"
                                                                          code:403
                                                                      userInfo:errorInfo]];
  } else {
    [manager_ infoFetchFailedForSource:self withError:error];
  }
}

- (NSArray*)peopleStringsForGDataPeople:(NSArray*)people {
  NSMutableArray* peopleStrings = [NSMutableArray arrayWithCapacity:[people count]];
  for (GDataPerson* person in people) {
    [peopleStrings addObject:[NSString stringWithFormat:@"%@ <%@>",
                              [person name], [person email]]];
  }
  return peopleStrings;
}

- (NSDictionary*)dictionaryForEntry:(GDataEntryBase*)entry {
  NSString* title = [[entry title] stringValue];
  if ([title hasSuffix:@".pdf"])
    title = [title substringToIndex:([title length] - 4)];
  NSMutableDictionary* info = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                          [entry identifier], kDocDictionaryIdentifierPathKey,
                      [[entry identifier] lastPathComponent], kGPMDItemUID,
                                                       title, (NSString*)kMDItemTitle,
                                  [[entry updatedDate] date], kGPMDItemModificationDate,
          [self peopleStringsForGDataPeople:[entry authors]], (NSString*)kMDItemAuthors,
                                     [[entry HTMLLink] href], (NSString*)kGPMDItemURL,
                                 [[entry content] sourceURI], kDocDictionarySourceURIKey,
                   [[entry categories] valueForKey:@"label"], kDocDictionaryCategoriesKey,
                                                              nil];
  if ([entry isKindOfClass:[GDataEntryDocBase class]]) {
    GDataEntryDocBase* doc = (GDataEntryDocBase*)entry;
    [info setObject:[NSNumber numberWithBool:[doc isStarred]]
             forKey:kDocDictionaryStarredKey];
  }
  return info;
}

#pragma mark Full Info Fetching

- (void)inflateNextDoc {
  // First check to see if we are done.
  if ([docsToInflate_ count] == 0) {
    [manager_ fullItemsInfoFetchCompletedForSource:self];
    return;
  }

  // If not, start getting the content for the next doc. Run this as a
  // prerformSelector:... so that we never try to get more than one document
  // per run loop cycle.
  [self performSelector:@selector(fetchContentForNextDoc)
             withObject:nil
             afterDelay:0.01];
}

- (void)retrievedContentForNextDoc:(NSString*)content {
  // Report this complete entry back to the manager.
  NSDictionary* docInfo = [docsToInflate_ objectAtIndex:0];
  NSMutableDictionary* fullDocInfo = [[docInfo mutableCopy] autorelease];
  [fullDocInfo setObject:content forKey:(NSString*)kMDItemTextContent];
  [manager_ fullItemsInfo:[NSArray arrayWithObject:fullDocInfo] fetchedForSource:self];
  [docsToInflate_ removeObjectAtIndex:0];

  // Start the cycle again.
  [self inflateNextDoc];
}

// Starts the process of getting content for the next document in docsToInflate_.
// retrievedContentForNextDoc: will be called when it's finished (with @"" as
// the content if the content couldn't be fetched).
- (void)fetchContentForNextDoc {
  NSDictionary* docInfo = [docsToInflate_ objectAtIndex:0];

  NSArray* categories = [docInfo objectForKey:kDocDictionaryCategoriesKey];
  if ([categories containsObject:kDocCategoryDocument]) {
    NSString* sourceURI = [docInfo objectForKey:kDocDictionarySourceURIKey];
    if ([sourceURI hasPrefix:@"http:"])
      sourceURI = [@"https:" stringByAppendingString:[sourceURI substringFromIndex:5]];
    NSURLRequest* request = [docService_ requestForURL:[NSURL URLWithString:sourceURI]
                                                  ETag:nil
                                            httpMethod:nil];
    GDataHTTPFetcher* fetcher = [GDataHTTPFetcher httpFetcherWithRequest:request];
    [fetcher setIsRetryEnabled:YES];
    [fetcher setMaxRetryInterval:60.0];
    [fetcher beginFetchWithDelegate:self
                  didFinishSelector:@selector(documentContentFetcher:finishedWithData:)
          didFailWithStatusSelector:@selector(documentContentFetcher:failedWithStatus:data:)
           didFailWithErrorSelector:@selector(documentContentFetcher:failedWithError:)];
  }
  else if ([categories containsObject:kDocCategorySpreadsheet]) {
    // TODO: this fetch is still synchronous; it should be made fully async so
    // that we don't block the runloop for however long it takes to get all
    // the worksheets.

    // The HTML view of the spreadsheet at sourceURI doesn't honor the GData
    // auth header, so the document approach of just reading that page results
    // in a login page unless there happens to be a valid cookie in the OS
    // cookie store (e.g., from Safari), so pull the content out of the cells.
    NSString* sourceURI = [docInfo objectForKey:kDocDictionarySourceURIKey];
    NSRange keyLabelRange = [sourceURI rangeOfString:@"key="];
    if (keyLabelRange.location == NSNotFound) {
      [self retrievedContentForNextDoc:@""];
      return;
    }
    NSString* key = [sourceURI substringFromIndex:(keyLabelRange.location + keyLabelRange.length)];
    NSRange ampersandRange = [key rangeOfString:@"&"];
    if (ampersandRange.location != NSNotFound)
      key = [key substringWithRange:NSMakeRange(0, ampersandRange.location - 1)];

    NSString* worksheetFeedURI =
      [NSString stringWithFormat:@"https://spreadsheets.google.com/feeds/worksheets/%@/private/full", key];
    NSURLRequest *request = [spreadsheetService_ requestForURL:[NSURL URLWithString:worksheetFeedURI]
                                                          ETag:nil
                                                    httpMethod:nil];
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *worksheetFeedData = [NSURLConnection sendSynchronousRequest:request
                                                      returningResponse:&response
                                                                  error:&error];
    if (!worksheetFeedData) {
      [self retrievedContentForNextDoc:@""];
      return;
    }
    NSXMLDocument* worksheetFeed = [[[NSXMLDocument alloc] initWithData:worksheetFeedData
                                                                options:0
                                                                  error:nil] autorelease];
    NSUInteger worksheetCount = [[worksheetFeed nodesForXPath:@"//entry" error:NULL] count];

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
      for (NSXMLNode* node in contentNodes) {
        [contentAccumulator appendString:@" "];
        [contentAccumulator appendString:[node stringValue]];
      }
    }

    [self retrievedContentForNextDoc:contentAccumulator];
  } else if ([categories containsObject:kDocCategoryPresentation]) {
    NSString* sourceURI = [docInfo objectForKey:kDocDictionarySourceURIKey];
    if ([sourceURI hasPrefix:@"http:"])
      sourceURI = [@"https:" stringByAppendingString:[sourceURI substringFromIndex:5]];
    // Default export format is PDF, but we just want the raw text.
    sourceURI = [sourceURI stringByAppendingString:@"&exportFormat=txt"];

    NSURLRequest* request = [docService_ requestForURL:[NSURL URLWithString:sourceURI]
                                                  ETag:nil
                                            httpMethod:nil];
    GDataHTTPFetcher* fetcher = [GDataHTTPFetcher httpFetcherWithRequest:request];
    [fetcher setIsRetryEnabled:YES];
    [fetcher setMaxRetryInterval:60.0];
    [fetcher beginFetchWithDelegate:self
                  didFinishSelector:@selector(documentContentFetcher:finishedWithData:)
          didFailWithStatusSelector:@selector(documentContentFetcher:failedWithStatus:data:)
           didFailWithErrorSelector:@selector(documentContentFetcher:failedWithError:)];
  } else if ([categories containsObject:kDocCategoryPDF]) {
    // TODO: there doesn't seem to be a way to get the text content without
    // downloading the entire PDF, which is potentially very costly.
    [self retrievedContentForNextDoc:@""];
  } else {
    NSLog(@"Unknown document type: %@", categories);
    [self retrievedContentForNextDoc:@""];
  }
}

- (void)documentContentFetcher:(GDataHTTPFetcher *)fetcher
              finishedWithData:(NSData *)data {
  NSXMLDocument* contentXML = [[[NSXMLDocument alloc] initWithData:data
                                                           options:NSXMLDocumentTidyHTML
                                                             error:NULL] autorelease];
  NSXMLNode* body = [[contentXML nodesForXPath:@"//body" error:NULL] lastObject];
  NSString* content = [body stringValue];
  // Strip off the IE XML namespace block
  if ([content hasPrefix:@"[if IE]>"]) {
    NSRange endTag = [content rangeOfString:@"<![endif]" options:NSLiteralSearch];
    if (endTag.location != NSNotFound) {
      NSUInteger tagEnd = endTag.location + endTag.length;
      content = (tagEnd < [content length]) ? [content substringFromIndex:tagEnd]
                                            : @"";
    }
  }
  if (!content) {
    content = @"";
    NSLog(@"Docs source couldn't get document data. (%x, %x, %x)", data, contentXML, body);
  }
  [self retrievedContentForNextDoc:content];
}

- (void)documentContentFetcher:(GDataHTTPFetcher *)fetcher
              failedWithStatus:(int)status
                          data:(NSData *)data {
  NSLog(@"Docs source received status %d trying to get document data", status);
  [self retrievedContentForNextDoc:@""];
}

- (void)documentContentFetcher:(GDataHTTPFetcher *)fetcher
               failedWithError:(NSError *)error {
  NSLog(@"Docs source failed to get document data: %@", error);
  [self retrievedContentForNextDoc:@""];
}

@end
