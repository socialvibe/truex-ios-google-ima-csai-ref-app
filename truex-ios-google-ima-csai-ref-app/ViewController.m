//
//  ViewController.m
//  truex-ios-mobile-reference-app
//
//  Created by Kyle Lam on 7/21/21.
//  Copyright © 2021 true[X]. All rights reserved.
//

#import "ViewController.h"
#import <AppTrackingTransparency/AppTrackingTransparency.h>

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UILabel *infoLabel;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    NSBundle* truexAdRendererBundle = [NSBundle bundleWithIdentifier:@"com.truex.TruexAdRenderer"];
    NSString* truexAdRendererVersion = [[truexAdRendererBundle infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    NSLog(@"TruexAdRenderer Version: %@", truexAdRendererVersion);
    [self.infoLabel setText:[NSString stringWithFormat:@"%@\n\nTruexAdRenderer Version: %@", self.infoLabel.text, truexAdRendererVersion]];
    
    // Optional, request ad tracking
    // See: https://developer.apple.com/documentation/apptrackingtransparency
    [self requestTrackingClicked];
}

- (void)requestTrackingClicked {
    if (@available(iOS 14.0, *))
    {
        [ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus status) {
            NSLog(@"%@", status == ATTrackingManagerAuthorizationStatusAuthorized? @"ATTrackingManagerAuthorizationStatusAuthorized YES": @"ATTrackingManagerAuthorizationStatusAuthorized NO");
        }];
    }
}

@end
