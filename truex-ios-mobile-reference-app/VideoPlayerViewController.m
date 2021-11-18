//
//  VideoPlayerViewController.m
//  truex-ios-mobile-reference-app
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

// internal state for the fake ad manager
@property NSMutableDictionary* videoMap;
@property NSMutableDictionary* macros;

@end

// internal state for the fake ad manager
BOOL _truexAdActive = NO;
BOOL _inAdBreak = NO;
int _adBreakIndex = 0;
int _resumeTime = -1;
BOOL _snappingBack = NO;

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
    adsSettings.enableDebugMode = YES;
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
    self.videoMap = nil;
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
    // true[X] - Besure to pasue and resume the true[X] Ad Renderer
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
    NSLog(@"AD EVENT FROM: %@", event.ad.adTitle);
    if (event.type == kIMAAdEvent_LOADED) {
        if (!_truexAdActive) {
            [adsManager start];
        }
        if ([event.ad.adSystem isEqualToString:@"trueX"]) {
            NSError *error;
            NSData *jsonData = [event.ad.traffickingParameters dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary* adParameters = [NSJSONSerialization JSONObjectWithData:jsonData
                                                                         options:0
                                                                           error:&error];
            if (!error) {
                _truexAdActive = YES;
                [self.player pause];
                [adsManager pause];
                NSString* slotType = (CMTimeGetSeconds(self.player.currentTime) == 0) ? @"preroll" : @"midroll";
                self.activeAdRenderer = [[TruexAdRenderer alloc] initWithUrl:@"https://media.truex.com/placeholder.js"
                                                                adParameters:adParameters
                                                                    slotType:slotType];
                self.activeAdRenderer.delegate = self;
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


// MARK: - Fake Ad Manager's Video Life Cycle Callbacks
- (void)videoStarted {
    NSLog(@"Ad Manager: Video Started");
}

- (void)videoEnded {
    NSLog(@"Ad Manager: Video Ended");
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)adBreakStarted {
    NSLog(@"Ad Manager: Ad Break Started");
    self.requiresLinearPlayback = YES;
    
    // [1] - Look for true[X] ad
    /* 
        Here in the Fake Vmap, in order to simply the logic, 
        we have the "system" attribute to indicate the ad being a true[X] ad, and the adParameters's vast_config_url as the "url" attribute.    
        While in the real world, one will have to change the follow logic for their ad stack. 
        
        In this VAST example, the "AdSystem" element indicate the ad type, and adParameters exists in the Character Data of the "AdParameters" element.
        https://qa-get.truex.com/f7e02f55ada3e9d2e7e7f22158ce135f9fba6317/vast?dimension_2=0&amp;stream_position=preroll&amp;stream_id=[stream_id]
    */
    NSDictionary* currentAdBreak = [self currentAdBreak];
    NSArray* ads = [currentAdBreak objectForKey:@"ads"];
    NSDictionary* firstAd = [ads objectAtIndex:0];
    BOOL isTruexAd = [[firstAd objectForKey:@"system"] isEqualToString:@"truex"];
    if (isTruexAd) {
        // [2] - Prepare to enter the engagement
        [self.player pause];
        [self resetActiveAdRenderer];
        NSString* slotType = (CMTimeGetSeconds(self.player.currentTime) == 0) ? @"preroll" : @"midroll";
        self.activeAdRenderer = [[TruexAdRenderer alloc] initWithUrl:@"https://media.truex.com/placeholder.js"
                                                        adParameters:@{
                                                            @"vast_config_url": [firstAd objectForKey:@"url"]
                                                        }
                                                            slotType:slotType];
        self.activeAdRenderer.delegate = self;
        [self.activeAdRenderer start:self.view];
        // true[X] - Seeking over the true[X] ad's placeholder
        [self seekOverFirstAd];
    }
}

- (void)adBreakEnded {
    NSLog(@"Ad Manager: Ad Break Ended");
    self.requiresLinearPlayback = NO;
}

// MARK: - TRUEX DELEGATE METHODS
// [5] - Other delegate method
- (void)onAdStarted:(NSString*)campaignName {
    // true[X] - User has started their ad engagement
    NSLog(@"truex: onAdStarted: %@", campaignName);
}

// [4] - Respond to renderer terminating events
- (void)onAdCompleted:(NSInteger)timeSpent {
    // true[X] - User has finished the true[X] engagement, resume the video stream
    NSLog(@"truex: onAdCompleted: %ld", (long)timeSpent);
    [self resetActiveAdRenderer];
    [self.adsManager skip];
    [self.player play];
    _truexAdActive = NO;
}

// [4]
- (void)onAdError:(NSString*)errorMessage {
    // true[X] - TruexAdRenderer encountered an error presenting the ad, resume with standard ads
    NSLog(@"truex: onAdError: %@", errorMessage);
    [self resetActiveAdRenderer];
    [self.adsManager skip];
    [self.player play];
    _truexAdActive = NO;
}

// [4]
- (void)onNoAdsAvailable {
    // true[X] - TruexAdRenderer has no ads ready to present, resume with standard ads
    NSLog(@"truex: onNoAdsAvailable");
    [self resetActiveAdRenderer];
    [self.adsManager skip];
    [self.player play];
    _truexAdActive = NO;
}

// [3] - Respond to onAdFreePod
- (void)onAdFreePod {
    // true[X] - User has met engagement requirements, skips past remaining pod ads
    NSLog(@"truex: onAdFreePod");
    if (_resumeTime == -1) {
        // true[X] - Skipping the whole ad break here as user earn credit from true[X]
        [self seekOverCurrentAdBreak];
    } else {
        // Custom snap back logic, skipping ad break and send user back to their original position
        [self.player seekToTime:CMTimeMake(_resumeTime, 1)];
        _resumeTime = -1;
    }
    [self helperEndAdBreak];
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
    IMAAdsRequest *request = [[IMAAdsRequest alloc] initWithAdTagUrl:kAdTagURLString
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

- (NSDictionary*)currentAdBreak {
    for (NSMutableDictionary* adbreak in [self.videoMap objectForKey:@"adbreaks"]) {
        int currentTime = CMTimeGetSeconds(self.player.currentTime);
        int timeOffset = [[adbreak valueForKey:@"timeOffset"] intValue];
        int duration = [[adbreak valueForKey:@"duration"] intValue];
        if ((timeOffset <= currentTime) && (currentTime < (timeOffset+duration))){
            return [adbreak copy];
        }
    }
    return nil;
}

- (NSDictionary*)adBreakAtIndex:(int)index {
    return [[self.videoMap objectForKey:@"adbreaks"] objectAtIndex:(NSUInteger)index];
}

- (int)currentAdBreakIndex {
    int index = -1;
    for (NSMutableDictionary* adbreak in [self.videoMap objectForKey:@"adbreaks"]) {
        int currentTime = CMTimeGetSeconds(self.player.currentTime);
        int timeOffset = [[adbreak valueForKey:@"timeOffset"] intValue];
        if (currentTime < timeOffset){
            return index;
        }
        index++;
    }
    return index;
}

- (void)helperStartAdBreak {
    if (!_inAdBreak) {
        _inAdBreak = YES;
        [self adBreakStarted];
    }
}

- (void)helperEndAdBreak {
    if (_inAdBreak) {
        _inAdBreak = NO;
        [self adBreakEnded];
        _adBreakIndex = [self currentAdBreakIndex];
    }
    
}

- (void)seekOverFirstAd {
    NSDictionary* currentAdBreak = [self currentAdBreak];
    NSArray* ads = [currentAdBreak objectForKey:@"ads"];
    NSDictionary* firstAd = [ads objectAtIndex:0];
    int duration = [[firstAd valueForKey:@"duration"] intValue];
    [self.player seekToTime:CMTimeAdd(self.player.currentTime, CMTimeMake(duration, 1))];
}

- (void)seekOverCurrentAdBreak {
    [self.adsManager discardAdBreak];
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    if ([elementName isEqualToString:@"notVmap"]) {
        self.videoMap = [attributeDict mutableCopy];
        NSMutableArray* adbreaks = [@[] mutableCopy];
        [self.videoMap setObject:adbreaks forKey:@"adbreaks"];
    } else if ([elementName isEqualToString:@"adbreak"]) {
        NSMutableDictionary* adbreak = [attributeDict mutableCopy];
        NSMutableArray* ads = [@[] mutableCopy];
        [adbreak setObject:ads forKey:@"ads"];
        [[self.videoMap valueForKey:@"adbreaks"] addObject:adbreak];
    } else if ([elementName isEqualToString:@"ad"]) {
        NSMutableDictionary* ad = [attributeDict mutableCopy];
        NSString* url = [ad objectForKey:@"url"];
        if (url) {
            NSString* streamId = [self.macros objectForKey:@"stream_id"];
            url = [url stringByReplacingOccurrencesOfString:@"[stream_id]" withString:streamId];
            [ad setValue:url forKey:@"url"];
        }
        NSMutableArray* adbreaks = [self.videoMap valueForKey:@"adbreaks"];
        NSMutableDictionary* adbreak = [adbreaks objectAtIndex:([adbreaks count] - 1)];
        [[adbreak valueForKey:@"ads"] addObject:ad];
    }
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
    [self alertWithTitle:@"Error" message:@"Failed to fetch vmap." completion:nil];
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
