//
//  VideoPlayerViewController.h
//  truex-ios-mobile-reference-app
//
//  Created by Kyle Lam on 7/21/21.
//  Copyright © 2021 true[X]. All rights reserved.
//

#import <UIKit/UIKit.h>
@import AVKit;
#import <TruexAdRenderer/TruexShared.h>

NS_ASSUME_NONNULL_BEGIN

@interface VideoPlayerViewController : AVPlayerViewController<TruexAdRendererDelegate, NSXMLParserDelegate>

@end

NS_ASSUME_NONNULL_END
