# Rewatch for iOS

Native iOS client for Rewatch, including its SideStore distribution source.

## SideStore

Add this source URL in SideStore:

```
https://raw.githubusercontent.com/eytanerez/rewatch-ios/main/source.json
```

Release IPAs are unsigned build artifacts intended for SideStore to re-sign with the installing user's Apple ID.

## Build

Requirements: Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -project Rewatch.xcodeproj -scheme Rewatch -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
