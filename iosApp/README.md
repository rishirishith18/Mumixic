# Mumixic for iPhone (isolated iOS app)

This native SwiftUI target is contained in `iosApp/`. It does not alter Android sources or backend services. The iOS experience follows Mumixic's artwork-led player design and includes Home, Library, Search, grouped Settings, swipe navigation, an icon-only animated dock, iOS 26 Liquid Glass surfaces with a material fallback on earlier versions, Classic/Vinyl/Cover Flow player modes, gently animated still artwork in the Classic player, a playback queue, YouTube Music Home shelves and playlist browsing, light/dark/system appearance, a custom player background, local Files import, YouTube Music web sign-in, online song search, audio playback where YouTube returns a direct stream URL, timed LRCLIB lyrics, and iOS lock-screen/Control Center controls. A captured YouTube Music session is stored in the iOS Keychain and used to sign InnerTube requests; signing out also clears the app's Google/YouTube web cookies.

## Build for Sideloadly

On a Mac with Xcode and the iOS SDK installed, run:

```sh
./iosApp/build-ipa.sh
```

The unsigned arm64 IPA is written to `iosApp/build/Mumixic-iOS-Sideloadly.ipa`. Open it in Sideloadly and sign it with your Apple ID. The package targets iOS 17 or later.

## Online playback note

Search uses YouTube Music's public InnerTube web client. YouTube may return direct audio URLs for a result or may require a playback integrity token or a different player client. This standalone iOS implementation does not bypass those checks; when a direct stream is unavailable, the player displays the reason and leaves local playback available. Timed lyrics are loaded from LRCLIB when a synchronized transcript is published for the song. Android integrations that depend on Android services, additional backend endpoints, or credentials not present in the iOS app (for example Android audio effects, device-specific audio routing, and Android downloads) are not represented as working iOS options. Network access is required for online search, sign-in, online playback, artwork, and lyrics.
