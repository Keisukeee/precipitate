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

static NSString* const kDocumentExportURLFormat =
  @"https://docs.google.com/feeds/download/documents/Export?docID=%@&exportFormat=txt";
static NSString* const kSpreadsheetExportURLFormat =
  @"https://spreadsheets.google.com/feeds/download/spreadsheets/Export?key=%@&fmcmd=23&gid=%d";

@interface GPDocsSync (Private)

- (NSArray*)peopleStringsForGDataPeople:(NSArray*)people;
- (NSDictionary*)dictionaryForEntry:(GDataEntryBase*)doc;
- (void)inflateNextDoc;
- (void)fetchContentForNextDoc;
- (void)retrievedContentForNextDoc:(NSString*)content;
// Returns the Google Docs identifier (used as a key in URLs) for the doc.
- (NSString*)documentIdForDoc:(NSDictionary*)docInfo;

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

  if ([categories containsObject:kDocCategoryDocument] ||
      [categories containsObject:kDocCategoryPresentation]) {
    NSString* docId = [self documentIdForDoc:docInfo];
    if (!docId) {
      [self retrievedContentForNextDoc:@""];
      return;
    }
    NSString* textContentURI = [NSString stringWithFormat:kDocumentExportURLFormat, docId];
    NSURLRequest* request = [docService_ requestForURL:[NSURL URLWithString:textContentURI]
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
    NSString* docId = [self documentIdForDoc:docInfo];
    if (!docId) {
      [self retrievedContentForNextDoc:@""];
      return;
    }
    NSString* worksheetFeedURI =
      [NSString stringWithFormat:@"https://spreadsheets.google.com/feeds/worksheets/%@/private/full", docId];
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
    for (int worksheetIndex = 0; worksheetIndex < worksheetCount; ++worksheetIndex) {
      NSString* contentFeedURI =
      [NSString stringWithFormat:kSpreadsheetExportURLFormat, docId, worksheetIndex];
      request = [spreadsheetService_ requestForURL:[NSURL URLWithString:contentFeedURI]
                                              ETag:nil
                                        httpMethod:nil];
      NSData *sheetData = [NSURLConnection sendSynchronousRequest:request
                                                returningResponse:&response
                                                            error:&error];
      if (!sheetData)
        continue;
      NSString* content = [[[NSString alloc] initWithData:sheetData
                                                 encoding:NSUTF8StringEncoding] autorelease];
      if (!content)
        continue;
      // Add some space between pages
      if (worksheetCount > 0)
        [contentAccumulator appendString:@"\n\n\n\n\n"];
      [contentAccumulator appendString:content];
    }

    [self retrievedContentForNextDoc:contentAccumulator];
  } else if ([categories containsObject:kDocCategoryPDF]) {
    // TODO: there doesn't seem to be a way to get the text content without
    // downloading the entire PDF, which is potentially very costly.
    [self retrievedContentForNextDoc:@""];
  } else {
    NSLog(@"Unknown document type: %@", categories);
    [self retrievedContentForNextDoc:@""];
  }
}

- (NSString*)documentIdForDoc:(NSDictionary*)docInfo {
  NSString* docUUID = [docInfo objectForKey:kGPMDItemUID];
  // Our UUID is the last part of the doc's path, so it will be something like
  // "document%3Aabc123" or "spreadsheet%3Aabc123". We need to strip off the
  // "type%3A" part (where %3A is a URL-encoded ':')
  NSRange colonRange = [docUUID rangeOfString:@"%3A" options:NSCaseInsensitiveSearch];
  if (colonRange.location != NSNotFound) {
    return [docUUID substringFromIndex:(colonRange.location + colonRange.length)];
  } else {
    NSLog(@"Unable to extract an ID from '%@'", docUUID);
    return nil;
  }
}

- (void)documentContentFetcher:(GDataHTTPFetcher *)fetcher
              finishedWithData:(NSData *)data {
  NSString* content = [[[NSString alloc] initWithData:data
                                             encoding:NSUTF8StringEncoding] autorelease];
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
