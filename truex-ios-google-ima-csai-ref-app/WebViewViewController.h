//
//  WebViewViewController.h
//  truex-ios-mobile-reference-app
//
//  Created by Kyle Lam on 7/22/21.
//  Copyright © 2021 true[X]. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WebViewViewController : UIViewController

@property (nullable)NSURL* url;
@property (nonatomic, copy, nullable) void (^onDismiss)(void);

@end

NS_ASSUME_NONNULL_END
