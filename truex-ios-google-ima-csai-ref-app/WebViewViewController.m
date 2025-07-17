//
//  WebViewViewController.m
//  truex-ios-mobile-reference-app
//
//  Created by Kyle Lam on 7/22/21.
//  Copyright © 2021 true[X]. All rights reserved.
//

#import <WebKit/WebKit.h>
#import "WebViewViewController.h"

@interface WebViewViewController ()
@property (weak, nonatomic) IBOutlet WKWebView *mainWebView;

@end

@implementation WebViewViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    if (self.url) {
        NSURLRequest* request = [[NSURLRequest alloc] initWithURL:self.url];
        [self.mainWebView loadRequest:request];
        self.url = nil;
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isBeingDismissed) {
        if (self.onDismiss) {
            self.onDismiss();
        }
    }
}

- (IBAction)onBackClicked:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
