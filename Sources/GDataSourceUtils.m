//
// Copyright (c) 2009 Google Inc.
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

#import "GDataSourceUtils.h"

#import "SharedConstants.h"

@implementation GDataServiceGoogle(PrecipitateSourceExtensions)
- (void)gp_configureWithCredentials:(GPKeychainItem*)credentials {
  [self setUserAgent:kPrecipitateUserAgent];
  [self setIsServiceRetryEnabled:YES];
  [self setServiceShouldFollowNextLinks:YES];

  NSString* username = [credentials username];
  NSString* password = [credentials password];
  [self setUserCredentialsWithUsername:username password:password];
}
@end


@implementation NSError(PrecipitateSourceExtensions)
+ (NSError*)gp_loginErrorWithDescriptionKey:(NSString*)key {
  NSString* errorString = NSLocalizedString(key, nil);
  NSDictionary* errorInfo =
      [NSDictionary dictionaryWithObject:errorString
                                  forKey:NSLocalizedDescriptionKey];
  return [NSError errorWithDomain:@"LoginFailure" code:403 userInfo:errorInfo];
}
@end

@interface NSArray(PrecipitateSourceExtensions)
- (NSArray*)gp_peopleStringsForGDataPeople  {
  NSMutableArray* peopleStrings =
      [NSMutableArray arrayWithCapacity:[self count]];
  for (GDataPerson* person in self) {
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
@end
