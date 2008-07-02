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

#import <Foundation/Foundation.h>
#import <GData/GData.h>
#import "GPSyncProtocol.h"


// Source for documents, spreadsheets, and presentations in Google Docs.
// Note: presentations currently won't have content data.
@interface GPDocsSync : NSObject <GPSyncSource> {
  id<GPSyncManager>              manager_;  // weak reference
  GDataServiceGoogleDocs*        docService_;
  GDataServiceGoogleSpreadsheet* spreadsheetService_;
}

@end
