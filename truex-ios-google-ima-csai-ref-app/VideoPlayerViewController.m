//
//  VideoPlayerViewController.m
//  truex-ios-google-ima-csai-ref-app
//
//  Created by Kyle Lam on 7/21/21.
//  Copyright © 2021 true[X]. All rights reserved.
//

#import "VideoPlayerViewController.h"
#import "WebViewViewController.h"
#import <TruexAdRenderer/TruexAdRenderer.h>
#import <GoogleInteractiveMediaAds/GoogleInteractiveMediaAds.h>

NSString* const kContentURLString = @"https://ctv.truex.com/assets/reference-app-stream-no-ads-720p.mp4";
NSString *const kAdTagURLString = @"https://stash.truex.com/ios/reference_app/ima-vmap-playlist.xml";


@interface VideoPlayerViewController () <IMAAdsLoaderDelegate, IMAAdsManagerDelegate>

@property TruexAdRenderer* activeAdRenderer;
@property(nonatomic) IMAAVPlayerContentPlayhead *contentPlayhead;
@property(nonatomic) IMAAdsLoader *adsLoader;
@property(nonatomic) IMAAdsManager *adsManager;

@end

// internal state for the fake ad manager
BOOL _truexAdActive = NO;
BOOL _adFreePodEarned = NO;

@implementation VideoPlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(pause)
                                               name:UIApplicationWillResignActiveNotification
                                             object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(resume)
                                               name:UIApplicationDidBecomeActiveNotification
                                             object:nil];
    IMASettings *adsSettings = [[IMASettings alloc] init];
    adsSettings.autoPlayAdBreaks = NO;
    self.adsLoader = [[IMAAdsLoader alloc] initWithSettings:adsSettings];
    self.adsLoader.delegate = self;
    [self setupStream];
}

- (void)viewDidAppear:(BOOL)animated {
    [self fetchVmapFromServer];
    [self.player play];
}

- (void)viewDidDisappear:(BOOL)animated {
    [self resetActiveAdRenderer];
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    // true[X] - Hide home indicator during true[X] Ad
    return (self.activeAdRenderer != nil);
}

- (BOOL)prefersStatusBarHidden {
    // true[X] - Hide the status bar during true[X] Ad
    return (self.activeAdRenderer != nil);
}

- (void)pause {
    // true[X] - Be sure to pasue and resume the true[X] Ad Renderer
    [self.activeAdRenderer pause];
}

- (void)resume {
    [self.activeAdRenderer resume];
}

- (void)resetActiveAdRenderer {
    if (self.activeAdRenderer) {
        [self.activeAdRenderer stop];
    }
    self.activeAdRenderer = nil;
}

#pragma mark - IMAAdsLoaderDelegate

- (void)adsLoader:(IMAAdsLoader *)loader adsLoadedWithData:(IMAAdsLoadedData *)adsLoadedData {
    // Initialize and listen to the ads manager loaded for this request.
    self.adsManager = adsLoadedData.adsManager;
    self.adsManager.delegate = self;
    [self.adsManager initializeWithAdsRenderingSettings:nil];
    [self.adsManager pause];
}

- (void)adsLoader:(IMAAdsLoader *)loader failedWithErrorData:(IMAAdLoadingErrorData *)adErrorData {
    // Fall back to playing content.
    NSLog(@"Error loading ads: %@", adErrorData.adError.message);
    [self.player play];
}

#pragma mark - IMAAdsManagerDelegate

- (void)adsManager:(IMAAdsManager *)adsManager didReceiveAdEvent:(IMAAdEvent *)event {
    // Play each ad once it has loaded.
    if (event.type == kIMAAdEvent_LOADED) {
        [adsManager start];

    } else if (event.type == kIMAAdEvent_STARTED) {
        if ([event.ad.adSystem isEqualToString:@"trueX"]) {
            NSString* vastConfigUrl = [event.ad.adDescription stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([vastConfigUrl length] > 0) {
                _truexAdActive = YES;
                [self.player pause];
                [adsManager pause];

                // For this demo app only: use a fresh user id each request to work around user ad limits.
                TruexAdOptions options = DefaultOptions();
                options.userAdvertisingId = [[NSUUID UUID] UUIDString];

                self.activeAdRenderer = [[TruexAdRenderer alloc] initWithVastConfigUrl:vastConfigUrl options:options delegate:self];
                [self.activeAdRenderer start:self.view];
            }
        }
    }
}

- (void)adsManager:(IMAAdsManager *)adsManager didReceiveAdError:(IMAAdError *)error {
    // Fall back to playing content.
    NSLog(@"AdsManager error: %@", error.message);
    [self.player play];
}

- (void)adsManagerDidRequestContentPause:(IMAAdsManager *)adsManager {
    // Pause the content for the SDK to play ads.
    [self.player pause];
}

- (void)adsManagerDidRequestContentResume:(IMAAdsManager *)adsManager {
    // Resume the content since the SDK is done playing ads (at least for now).
    [self.player play];
}

// MARK: - TRUEX DELEGATE METHODS
// [5] - Other delegate method
- (void)onAdStarted:(NSString*)campaignName {
    // true[X] - User has started their ad engagement
    NSLog(@"truex: onAdStarted: %@", campaignName);
}

// [4] - Respond to renderer terminating events
- (void)truexExitHelper {
    [self resetActiveAdRenderer];
    _truexAdActive = NO;
}

- (void)onAdCompleted:(NSInteger)timeSpent {
    // true[X] - User has finished the true[X] engagement, resume the video stream
    NSLog(@"truex: onAdCompleted: %ld", (long) timeSpent);
    [self truexExitHelper];
    if (_adFreePodEarned) {
        [self seekOverCurrentAdBreak];
        _adFreePodEarned = NO;
        [self.player play];
    } else {
        [self.adsManager resume];
    }
}

// [4]
- (void)onAdError:(NSString*)errorMessage {
    // true[X] - TruexAdRenderer encountered an error presenting the ad, resume with standard ads
    NSLog(@"truex: onAdError: %@", errorMessage);
    [self truexExitHelper];
    [self.adsManager resume];
}

// [4]
- (void)onNoAdsAvailable {
    // true[X] - TruexAdRenderer has no ads ready to present, resume with standard ads
    NSLog(@"truex: onNoAdsAvailable");
    [self truexExitHelper];
    [self.adsManager resume];
}

// [3] - Respond to onAdFreePod
- (void)onAdFreePod {
    // true[X] - User has met engagement requirements, skips past remaining pod ads
    NSLog(@"truex: onAdFreePod");
    _adFreePodEarned = YES;
}

// [5] - Other delegate method
- (void)onPopupWebsite:(NSString *)url {
    // true[X] - User wants to open an external link in the true[X] ad

    NSLog(@"truex: onPopupWebsite: %@", url);
    // Open URL with the SFSafariViewController
    // SFSafariViewController *svc = [[SFSafariViewController alloc] initWithURL:[NSURL URLWithString: url]];
    // svc.delegate = self;
    // svc.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    // [self presentViewController:svc animated:YES completion:nil];
    // [self.activeAdRenderer pause];

    // Or, open the URL directly in Safari
    // [[UIApplication sharedApplication] openURL:[NSURL URLWithString: url] options:@{} completionHandler:nil];

    // Or, open with the existing in-app webview
     UIStoryboard* storyBoard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
     WebViewViewController* newViewController = [storyBoard instantiateViewControllerWithIdentifier:@"webviewVC"];
     newViewController.url = [NSURL URLWithString:url];
     newViewController.modalPresentationStyle = UIModalPresentationOverCurrentContext;
     __weak typeof(self) weakSelf = self;
     newViewController.onDismiss = ^(void) {
         // true[X] - You will need to pause and remume the true[X] Ad Renderer
         [weakSelf.activeAdRenderer resume];
     };
     [self.activeAdRenderer pause];
     [self presentViewController:newViewController animated:YES completion:nil];
}

// When using SFSafariViewController for onPopupWebsite
//- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller {
//    // true[X] - You will need remume the true[X] Ad Renderer after safariViewController
//    if (self.activeAdRenderer) {
//        [self.activeAdRenderer resume];
//    }
//}

// MARK: @optional true[X] delegate methods
// [5]
-(void) onOptIn:(NSString*)campaignName adId:(NSInteger)adId {
    // true[X] - This event is triggered when a user decides opt-in to the true[X] interactive ad
    NSLog(@"truex: onOptIn: %@, %li", campaignName, (long)adId);
}

// [5]
-(void) onOptOut:(BOOL)userInitiated {
    // true[X] - User has opted out of true[X] engagement, show standard ads
    NSLog(@"truex: userInitiated: %@", userInitiated? @"true": @"false");
}

// [5]
-(void) onSkipCardShown {
    // true[X] - TruexAdRenderer displayed a Skip Card
    NSLog(@"truex: onSkipCardShown");
}

// [5]
-(void) onUserCancel {
    // true[X] - This event will fire when a user backs out of the true[X] interactive ad unit after having opted in.
    NSLog(@"truex: onUserCancel");
}

// MARK: - Helper Functions / Fake Ad Server Call

// Simulating video server call
- (void)fetchVmapFromServer {
    IMAAdDisplayContainer *adDisplayContainer = [[IMAAdDisplayContainer alloc] initWithAdContainer:self.view
                                                                                    viewController:self];
    // "Real" requests original from an ad server via an ad url.
    // However for this demo app, we use a local VMAP xml file to allow the developer
    // to see the VAST xml contents directly, and to allow edits and explorations.
//    IMAAdsRequest *request = [[IMAAdsRequest alloc] initWithAdTagUrl:kAdTagURLString
//                                                  adDisplayContainer:adDisplayContainer
//                                                     contentPlayhead:self.contentPlayhead
//                                                          userContext:nil];
    NSString* vmapPlaylistPath = [[NSBundle mainBundle] pathForResource:@"ima-vmap-playlist" ofType:@"xml"];
    NSData* vmapData = [NSData dataWithContentsOfFile:vmapPlaylistPath];
    NSString* vmapResponse = [[NSString alloc] initWithData:vmapData encoding:NSUTF8StringEncoding];
    IMAAdsRequest *request = [[IMAAdsRequest alloc] initWithAdsResponse:vmapResponse
                                                     adDisplayContainer:adDisplayContainer
                                                        contentPlayhead:self.contentPlayhead
                                                            userContext:nil];
    [self.adsLoader requestAdsWithRequest:request];
}

// Simulating your existing ad framework
- (void)setupStream {
    NSURL* url = [NSURL URLWithString:kContentURLString];
    AVAsset* asset = [AVAsset assetWithURL:url];
    NSArray* assetKeys = @[ @"playable" ];
    AVPlayerItem* playerItem = [AVPlayerItem playerItemWithAsset:asset automaticallyLoadedAssetKeys:assetKeys];
    self.player = [AVPlayer playerWithPlayerItem:playerItem];
    self.contentPlayhead = [[IMAAVPlayerContentPlayhead alloc] initWithAVPlayer:self.player];
}

- (void)seekOverCurrentAdBreak {
    [self.adsManager discardAdBreak];
}

- (void)alertWithTitle:(NSString*)title message:(NSString*)message completion:(void (^)(void))completionCallback;
{
    NSLog(@"alertWithTitle: %@: %@", title, message);
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title
                                   message:message
                                   preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
       handler:^(UIAlertAction * action) {}];

    [alert addAction:defaultAction];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:completionCallback];
    });
}

@end
