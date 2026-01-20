# Overview

This project contains sample source code that demonstrates how to integrate Infillion's interactive ad renderer in iOS using Google IMA SDK for client-side ad insertion (CSAI). This document will step through the various pieces of code that make the integration work, so that the same basic ideas can be replicated in a real production app.

**Infillion interactive ads** include:
* **TrueX ads** - Interactive choice card experiences that allow users to skip an entire ad break by engaging with branded content
* **IDVx ads** - Interactive ads that start automatically and play inline with other ads in the break

This reference app covers the essential work. It assumes your app already has a working IMA SDK integration.

For a more detailed integration guide, please refer to: https://github.com/socialvibe/truex-mobile-integrations/

# Access the Infillion Ad Renderer Library

One can get the Infillion Ad Renderer either by the
[non-standard CocoaPods integration](https://guides.cocoapods.org/making/private-cocoapods.html):
[TrueX CocoaPods](https://github.com/socialvibe/cocoapod-specs)
```
source 'https://github.com/socialvibe/cocoapod-specs.git'

target 'your-app' do
    pod 'TruexAdRenderer-iOS', '4.1.0'
end
```
or via Swift Package Manager using the [TruexAdRenderer-iOS-Swift-Package](https://github.com/socialvibe/TruexAdRenderer-iOS-Swift-Package) repository.

# Infillion Interactive Ads

This reference app demonstrates both types of Infillion interactive ads:

### TrueX Ads
TrueX ads present an **interactive choice card** where users can **opt-in** to engage with branded content. The user makes an active choice to interact with the ad. If the user completes the interaction, they earn an **ad credit that skips the entire ad break**, and the main video resumes immediately. If the user opts out or ignores the choice card, standard fallback ads play instead.

**Key characteristics:**
- **Opt-in via choice card** - User must actively choose to engage
- **Skips entire ad break** - Successful engagement bypasses all remaining ads in the pod
- **Configuration**: Uses the `adDescription` field containing a VAST config URL

### IDVx Ads
IDVx ads are **interactive ads** that start **automatically without requiring opt-in**. Unlike TrueX ads which require users to opt-in via a choice card, IDVx ads begin playing automatically. While no opt-in is required to start, users can interact with the ad content throughout its duration. IDVx ads **play inline with other ads** in the ad break. After an IDVx ad completes, the next ad in the sequence plays.

**Key characteristics:**
- **Automatic start** - No opt-in required, begins playing automatically
- **Interactive throughout** - Users can interact with ad content for its duration
- **Plays inline** - Completes and continues to next ad in the pod
- **Configuration**: Uses the `traffickingParameters` field containing JSON configuration

# Integration Steps

The following steps are a guideline for the Infillion Ad Renderer integration with IMA SDK. This assumes you have setup the Ad Renderer dependency above. The starting/key points referenced in each step can be searched in the code for reference. E.g., searching for [2] will direct you to the engagement start.

### [1] - Identify Infillion ads via IMA SDK
This sample app uses the Google IMA SDK to load ads from a VMAP playlist (`ima-vmap-playlist.xml`). The important part is determining if a given ad is an Infillion interactive ad (TrueX or IDVx). In the `kIMAAdEvent_STARTED` handler, check the `adSystem` property to identify the ad type:
- `"trueX"` - TrueX interactive choice card ad
- `"IDVx"` - IDVx inline interactive ad

### [2] - Start the Infillion ad
When an Infillion ad is detected in the IMA ad event:

1. Pause both the content player and the IMA ads manager
2. Seek IMA's internal ad player to the end (so the placeholder video completes when resumed)
3. Create a `TruexAdRenderer` instance with the appropriate initialization:
   - For **TrueX ads**: Use `initWithVastConfigUrl:options:delegate:` with the URL from `ad.adDescription`
   - For **IDVx ads**: Use `initWithAdParameters:options:delegate:` with JSON parsed from `ad.traffickingParameters`
4. Call `start:` to display the interactive ad

**Note**: For TrueX ads, set `options.supportsUserCancelStream = YES` to allow users to back out from the choice card. For IDVx ads, set it to `NO` since they start automatically.

### [3] - Respond to onAdFreePod
The `onAdFreePod` delegate method is called when the user earns credit to skip the ad break. This only applies to **TrueX ads** - IDVx ads never fire this event. Track this state with a flag, but wait for the completion event before taking action.

### [4] - Respond to renderer terminating events
There are three ways the renderer can finish:

1. There were no ads available. (`onNoAdsAvailable`)
2. The ad had an error. (`onAdError`)
3. The viewer has completed the engagement. (`onAdCompleted`)

In `onAdCompleted`:
- **TrueX with credit earned**: Skip all remaining ads in the pod using `[adsManager discardAdBreak]` and resume content playback
- **TrueX without credit** or **IDVx**: Resume the IMA ads manager with `[adsManager resume]` to continue to the next ad in the pod

In all three cases, the renderer will have removed itself from view.

### [5] - Other delegate methods
See the code for other ad events that are fired. Some events are for custom purposes if needed:
- `onAdStarted` - The interactive ad has started
- `onOptIn` - User opted into the TrueX engagement
- `onOptOut` - User opted out of the engagement
- `onPopupWebsite` - User tapped a link; pause the ad and show a web view

The `onPopupWebsite` event is for handling user interactions that open external links. It is important to pause/resume the ad renderer when switching to another view, as shown in the code.
