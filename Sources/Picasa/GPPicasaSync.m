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

#import "GPPicasaSync.h"
#import "GPKeychainItem.h"
#import "SharedConstants.h"
#import "PWAInfoKeys.h"

#define kPWADictionaryTypeKey @"_PWAType"

@interface GPPicasaSync (Private)
- (NSDictionary*)dictionaryForAlbum:(GDataEntryPhotoAlbum*)album;
- (NSArray*)peopleStringsForGDataPeople:(NSArray*)people;
- (NSString*)thumbnailURLForEntry:(GDataEntryPhotoBase*)entry;
@end

@implementation GPPicasaSync

- (id)initWithManager:(id<GPSyncManager>)manager {
  if ((self = [super init])) {
    manager_ = manager;
  }
  return self;
}

- (void)dealloc {
  [picasaService_ release];
  [super dealloc];
}

- (void)fetchAllItemsBasicInfo {
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

  [picasaService_ autorelease];
  picasaService_ = [[GDataServiceGooglePicasaWeb alloc] init];
  [picasaService_ setUserAgent:kPrecipitateUserAgent];
  [picasaService_ setUserCredentialsWithUsername:username password:password];
  [picasaService_ setIsServiceRetryEnabled:YES];
  [picasaService_ setServiceShouldFollowNextLinks:YES];
  
  NSString* albumFeedURI =
    [[GDataServiceGooglePicasaWeb picasaWebFeedURLForUserID:username
                                                    albumID:nil
                                                  albumName:nil
                                                    photoID:nil
                                                       kind:nil
                                                     access:nil] absoluteString];
  // Ideally we would use https, but the album list redirects when accessed that way.
  //if ([albumFeedURI hasPrefix:@"http:"])
  //  albumFeedURI = [@"https:" stringByAppendingString:[albumFeedURI substringFromIndex:5]];
  [picasaService_ fetchPicasaWebFeedWithURL:[NSURL URLWithString:albumFeedURI]
                                   delegate:self
                          didFinishSelector:@selector(serviceTicket:finishedWithObject:)
                            didFailSelector:@selector(serviceTicket:failedWithError:)];
}

- (void)fetchFullInfoForItems:(NSArray*)items {
  [manager_ fullItemsInfo:items fetchedForSource:self];
  [manager_ fullItemsInfoFetchCompletedForSource:self];
}

- (NSString*)cacheFileExtensionForItem:(NSDictionary*)item {
  if ([[item objectForKey:kPWADictionaryTypeKey] isEqual:kPWATypeAlbum])
    return @"pwaalbum";
  return @"pwaphoto";
}

- (NSArray*)itemExtensions {
  return [NSArray arrayWithObjects:@"pwaalbum", @"pwaphoto", nil];
}

- (NSString*)displayName {
  return @"Picasa Web Albums";
}

#pragma mark -

- (void)serviceTicket:(GDataServiceTicket *)ticket
   finishedWithObject:(GDataFeedPhotoAlbum *)albumList {
  NSMutableDictionary* albumsById = [NSMutableDictionary dictionary];
  NSEnumerator* entryEnumerator = [[albumList entries] objectEnumerator];
  GDataEntryBase* entry;
  while ((entry = [entryEnumerator nextObject])) {
    @try {
      if (![entry isKindOfClass:[GDataEntryPhotoAlbum class]]) {
        NSLog(@"Unexpected entry in album list: %@", entry);
        continue;
      }
      NSDictionary* albumInfo = [self dictionaryForAlbum:(GDataEntryPhotoAlbum*)entry];
      if (albumInfo)
        [albumsById setObject:albumInfo forKey:[albumInfo objectForKey:kGPMDItemUID]];
      else
        NSLog(@"Couldn't get info for album: %@", entry);
    } @catch (id exception) {
      NSLog(@"Caught exception while processing basic album info: %@", exception);
    }
  }
  
  [manager_ basicItemsInfo:[albumsById allValues] fetchedForSource:self];
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

- (NSDictionary*)dictionaryForAlbum:(GDataEntryPhotoAlbum*)album {
  return [NSDictionary dictionaryWithObjectsAndKeys:
                                      [album GPhotoID], kGPMDItemUID,
                           [[album title] stringValue], (NSString*)kMDItemTitle,
                         [[album timestamp] dateValue], (NSString*)kMDItemContentCreationDate,
                            [[album updatedDate] date], kGPMDItemModificationDate,
    [self peopleStringsForGDataPeople:[album authors]], (NSString*)kMDItemAuthors,
                               [[album HTMLLink] href], (NSString*)kGPMDItemURL,
                                         kPWATypeAlbum, kPWADictionaryTypeKey,
                [[album photoDescription] stringValue], (NSString*)kMDItemDescription,
                                      [album location], kAlbumDictionaryLocationKey,
                     [self thumbnailURLForEntry:album], kAlbumDictionaryThumbnailURLKey,
                                                        nil];
}

// TODO: refactor this to a shared location.
- (NSArray*)peopleStringsForGDataPeople:(NSArray*)people {
  NSMutableArray* peopleStrings = [NSMutableArray arrayWithCapacity:[people count]];
  NSEnumerator* enumerator = [people objectEnumerator];
  GDataPerson* person;
  while ((person = [enumerator nextObject])) {
    NSString* name = [person name];
    NSString* email = [person email];
    if (name && email)
      [peopleStrings addObject:[NSString stringWithFormat:@"%@ <%@>",
                                  name, email]];
    else if (name)
      [peopleStrings addObject:name];
    else if (email)
      [peopleStrings addObject:email];
  }
  return peopleStrings;
}

- (NSString*)thumbnailURLForEntry:(GDataEntryPhotoBase*)entry {
  if (![entry respondsToSelector:@selector(mediaGroup)])
    return @"";
  NSArray *thumbnails = [[(id)entry mediaGroup] mediaThumbnails];
  if ([thumbnails count] > 0)
    return [[thumbnails objectAtIndex:0] URLString];
  return @"";
}

@end
