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

#import "PrecipitatePreferencePane.h"

#import "GPSourcePreferences.h"
#import "GPSourceStatus.h"
#import "SharedConstants.h"
#import "GPKeychainItem.h"
#import "GTMSystemVersion.h"

@interface ComGooglePrecipitateSourceInfo : NSObject {
  NSString* identifier_;
  NSString* displayName_;
  NSString* errorMessage_;
  NSDate*   lastSyncSuccess_;
  NSDate*   lastSyncAttempt_;
  BOOL      enabled_;
}

+ (id)sourceInfoWithIdentifier:(NSString*)identifier;
- (id)initWithIdentifier:(NSString*)identifier;

- (NSString*)identifier;

- (NSString*)statusMessage;

- (NSString*)displayName;
- (void)setDisplayName:(NSString *)value;

- (NSString*)errorMessage;
- (void)setErrorMessage:(NSString *)value;

- (NSDate*)lastSyncSuccess;
- (void)setLastSyncSuccess:(NSDate *)value;

- (NSDate*)lastSyncAttempt;
- (void)setLastSyncAttempt:(NSDate *)value;

- (BOOL)enabled;
- (void)setEnabled:(BOOL)value;

@end

@implementation ComGooglePrecipitateSourceInfo

+ (void)initialize
{
  if (self == [ComGooglePrecipitateSourceInfo class]) {
    [self setKeys:[NSArray arrayWithObjects:@"errorMessage", @"lastSyncSuccess", @"lastSyncAttempt", nil]
      triggerChangeNotificationsForDependentKey:@"statusMessage"];
  }
}

+ (id)sourceInfoWithIdentifier:(NSString*)identifier {
  return [[[self alloc] initWithIdentifier:identifier] autorelease];
}

- (id)initWithIdentifier:(NSString*)identifier {
  if ((self = [super init])) {
    identifier_ = [identifier copy];
  }
  return self;
}

- (void)dealloc {
  [identifier_ release];
  [displayName_ release];
  [errorMessage_ release];
  [lastSyncSuccess_ release];
  [lastSyncAttempt_ release];
  [super dealloc];
}

- (NSString*)identifier {
  return identifier_;
}

- (NSString*)statusMessage {
  static NSDateFormatter* dateFormatter = nil;
  if (!dateFormatter) {
    dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
    [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
  }
  if (lastSyncAttempt_) {
    NSString* formattedDate = [dateFormatter stringFromDate:lastSyncAttempt_];
    if (errorMessage_) {
      NSString* formatString =
      [[NSBundle bundleForClass:[self class]] localizedStringForKey:@"FailureFormat"
                                                              value:@"FailureFormat"
                                                              table:@"PrefPane"];
      return [NSString stringWithFormat:formatString, formattedDate, errorMessage_];
    } else {
      NSString* formatString =
      [[NSBundle bundleForClass:[self class]] localizedStringForKey:@"SuccessFormat"
                                                              value:@"SuccessFormat"
                                                              table:@"PrefPane"];
      return [NSString stringWithFormat:formatString, formattedDate];
    }
  }
  return @"";
}

- (NSString *)displayName {
  return [[displayName_ retain] autorelease];
}

- (void)setDisplayName:(NSString*)value {
  if (displayName_ != value) {
    [displayName_ release];
    displayName_ = [value copy];
  }
}

- (NSString*)errorMessage {
  return [[errorMessage_ retain] autorelease];
}

- (void)setErrorMessage:(NSString*)value {
  if (errorMessage_ != value) {
    [errorMessage_ release];
    errorMessage_ = [value copy];
  }
}

- (NSDate*)lastSyncSuccess {
  return [[lastSyncSuccess_ retain] autorelease];
}

- (void)setLastSyncSuccess:(NSDate*)value {
  if (lastSyncSuccess_ != value) {
    [lastSyncSuccess_ release];
    lastSyncSuccess_ = [value copy];
  }
}

- (NSDate *)lastSyncAttempt {
  return [[lastSyncAttempt_ retain] autorelease];
}

- (void)setLastSyncAttempt:(NSDate*)value {
  if (lastSyncAttempt_ != value) {
    [lastSyncAttempt_ release];
    lastSyncAttempt_ = [value copy];
  }
}

- (BOOL)enabled {
  return enabled_;
}

- (void)setEnabled:(BOOL)value {
  if (enabled_ != value) {
    enabled_ = value;
    [[GPSourcePreferences sharedSourcePreferences] setEnabled:enabled_
                                                    forSource:[self identifier]];
  }
}

@end

#pragma mark -

@interface ComGooglePrecipitatePreferencePane (Private)
- (void)populateSourceList;
- (void)setSourceStatuses:(NSArray*)statuses;
- (void)triggerReSync;
- (void)postSyncNotification;
- (void)startProgressIndicator;
- (void)stopProgressIndicator;
@end

@implementation ComGooglePrecipitatePreferencePane

+ (void)initialize
{
  // On Tiger, where valueTransformerForName: won't do a dynamic lookup, we
  // need to get our custom tranformer registered ASAP so the nib can find it.
  if (self == [ComGooglePrecipitatePreferencePane class]) {
    [NSValueTransformer setValueTransformer:[[[ComGooglePrecipitateMessageColorTransformer alloc] init] autorelease]
                                    forName:@"ComGooglePrecipitateMessageColorTransformer"];
  }
}

- (void)dealloc {
  [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
  [sourceStatusManager_ removeObserver:self forKeyPath:@"allStatuses"];
  [sourceStatusManager_ release];
  [self setSourceStatuses:nil];
  [super dealloc];
}

- (void)mainViewDidLoad {
  // Adjust to fix 10.5+ pref pane width.
  if ([GTMSystemVersion isLeopardOrGreater]) {
    NSSize paneSize = [[syncButton_ superview] frame].size;
    paneSize.width = 668;
    [[syncButton_ superview] setFrameSize:paneSize];
  }

  NSDistributedNotificationCenter* dnc = [NSDistributedNotificationCenter defaultCenter];
  [dnc addObserver:self
          selector:@selector(startProgressIndicator)
              name:kPrecipitateSyncStartedNotification
            object:nil];
  [dnc addObserver:self
          selector:@selector(stopProgressIndicator)
              name:kPrecipitateSyncFinishedNotification
            object:nil];

  // Make sure the helper is running.
  NSString* helperAppPath = [[NSBundle bundleForClass:[self class]] pathForResource:@"Precipitate"
                                                                             ofType:@"app"];
  LSLaunchURLSpec launchSpec = {
    (CFURLRef)[NSURL fileURLWithPath:helperAppPath],
    NULL, NULL, kLSLaunchDontSwitch, NULL
  };
  LSOpenFromURLSpec(&launchSpec, NULL);
  

  [sourceTable_ setIntercellSpacing:NSMakeSize(6.0, 8.0)];

  sourceStatusManager_ = [[GPSourceStatus sharedSourceStatus] retain];
  GPKeychainItem* accountInfo = [GPKeychainItem keychainItemForService:kPrecipitateGoogleAccountKeychainServiceName];
  if (accountInfo && [accountInfo password]) {
    [usernameField_ setStringValue:[accountInfo username]];
    [passwordField_ setStringValue:[accountInfo password]];
  }
  [sourceStatusManager_ addObserver:self
                         forKeyPath:@"allStatuses"
                            options:0
                            context:self];
}

- (void)willSelect {
  [self populateSourceList];
}

- (IBAction)setLogin:(id)sender {
  GPKeychainItem *item = [GPKeychainItem keychainItemForService:kPrecipitateGoogleAccountKeychainServiceName];
  if (item) {
    [item setUsername:[usernameField_ stringValue]
             password:[passwordField_ stringValue]];
  } else if ([[usernameField_ stringValue] length] > 0 &&
             [[passwordField_ stringValue] length] > 0) {
    [GPKeychainItem addKeychainItemForService:kPrecipitateGoogleAccountKeychainServiceName
                               withUsername:[usernameField_ stringValue]
                                   password:[passwordField_ stringValue]];
  }

  [self triggerReSync];
}

- (int)numberOfRowsInTableView:(NSTableView *)aTableView {
  // The real data source is done through bindings; this is only here because
  // we need to watch tableView:setObjectValue:forTableColumn:row:, and the
  // OS complains if we claim to be a data source without implementing this.
  return 0;
}

- (id)tableView:(NSTableView *)aTableView
 objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(int)rowIndex {
  // The real data source is done through bindings; this is only here because
  // we need to watch tableView:setObjectValue:forTableColumn:row:, and the
  // OS complains if we claim to be a data source without implementing this.
  return nil;
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
              row:(int)rowIndex {
  if ([[aTableColumn identifier] isEqualToString:@"enabled"]);
    [self triggerReSync];
}

#pragma mark -

- (IBAction)syncNow:(id)sender {
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(postSyncNotification)
                                             object:nil];
  [self postSyncNotification];
}

- (void)triggerReSync {
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(postSyncNotification)
                                             object:nil];
  [self performSelector:@selector(postSyncNotification)
             withObject:nil
             afterDelay:30.0];
}

- (void)postSyncNotification {
  // TODO: Once we are 10.5+ and can use launchd for the helper, this will need
  // to launch the helper rather than send a notification.
  NSDistributedNotificationCenter* dnc = [NSDistributedNotificationCenter defaultCenter];
  [dnc postNotificationName:kPrecipitateReSyncNeededNotification
                     object:nil
                   userInfo:nil];
}

- (void)startProgressIndicator {
  [progressSpinner_ startAnimation:nil];
  [syncButton_ setEnabled:NO];
}

- (void)stopProgressIndicator {
  [progressSpinner_ stopAnimation:nil];
  [syncButton_ setEnabled:YES];
}

#pragma mark -

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
  if (![(id)context isEqual:self])
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  if ([keyPath isEqualToString:@"allStatuses"])
    [self populateSourceList];
}

- (void)populateSourceList {
  NSDictionary* allSourceInfo = [[GPSourcePreferences sharedSourcePreferences] availableSources];
  NSDictionary* allSourceStatus = [sourceStatusManager_ allStatuses];

  NSMutableArray* statusList = [NSMutableArray arrayWithCapacity:[allSourceInfo count]];
  NSEnumerator* sourceEnumerator = [allSourceInfo keyEnumerator];
  NSString* sourceId;
  while ((sourceId = [sourceEnumerator nextObject])) {
    NSDictionary* baseInfo = [allSourceInfo objectForKey:sourceId];
    NSDictionary* status = [allSourceStatus objectForKey:sourceId];

    ComGooglePrecipitateSourceInfo* sourceInfo =
      [ComGooglePrecipitateSourceInfo sourceInfoWithIdentifier:sourceId];
    [sourceInfo setDisplayName:[baseInfo objectForKey:kGPSourcePrefDisplayNameKey]];
    [sourceInfo setEnabled:[[baseInfo objectForKey:kGPSourcePrefEnabledKey] boolValue]];
    [sourceInfo setErrorMessage:[status objectForKey:kGPStatusErrorMessageKey]];
    [sourceInfo setLastSyncAttempt:[status objectForKey:kGPStatusLastAttemptedSyncKey]];
    [sourceInfo setLastSyncSuccess:[status objectForKey:kGPStatusLastSuccessfulSyncKey]];
    [statusList addObject:sourceInfo];
  }
  NSSortDescriptor* initialSort = [[[NSSortDescriptor alloc] initWithKey:@"displayName"
                                                               ascending:YES] autorelease];
  [self setSourceStatuses:[statusList sortedArrayUsingDescriptors:[NSArray arrayWithObject:initialSort]]];
  [sourceTable_ selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];

  // On the first launch, the app won't have populated the source listing yet,
  // so poll until we get something. Ideally, we'd use KVO-compliant
  // distributed preferences and notice changes that way.
  if ([statusList count] == 0)
    [self performSelector:@selector(populateSourceList) withObject:nil afterDelay:1.0];
}

- (NSArray*)sourceStatuses {
  return sourceStatuses_;
}

- (void)setSourceStatuses:(NSArray*)statuses {
  [sourceStatuses_ autorelease];
  sourceStatuses_ = [statuses retain];
}

@end

#pragma mark -

@implementation ComGooglePrecipitateMessageColorTransformer

+ (Class)transformedValueClass {
  return [NSColor class];
}

+ (BOOL)allowsReverseTransformation {
  return NO;
}

- (id)transformedValue:(id)value {
  return (value != nil) ? [NSColor redColor] : [NSColor blackColor];
}

@end
