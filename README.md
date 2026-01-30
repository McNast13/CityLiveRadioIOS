CityLiveRadio iOS
=================

A SwiftUI iOS frontend for the CityLive Radio station with live playback and a "Listen Again" list of previously aired shows.

Overview
--------
- Main purpose: play the live radio stream and let the user play archived shows (Listen Again).
- Live stream URL: https://streaming.live365.com/a91939
- Listen Again recordings included in the app (title — stream URL):
  - Not The 9 O'Clock Show — https://cityliveradiouk.co.uk/Streaming/ListenAgain/NTNOCS.mp3
  - Red Bearded Viking Show — https://cityliveradiouk.co.uk/Streaming/ListenAgain/RBV.mp3
  - The Country Mile — https://cityliveradiouk.co.uk/Streaming/ListenAgain/CM.mp3
  - Ginger and Nuts — https://cityliveradiouk.co.uk/Streaming/ListenAgain/GingerandNuts.mp3
  - Weekend Anthems — https://cityliveradiouk.co.uk/Streaming/ListenAgain/WeekendAnthems.mp3
  - Saturday Club Classics — https://cityliveradiouk.co.uk/Streaming/ListenAgain/scc.mp3

Latest features & behavior
---------------------------
- Player & metadata
  - `RadioPlayer` (`ObservableObject`) manages playback (play/pause/stop), switching between live and listen-again streams, and exposes published state such as `isPlaying`, `trackInfo`, `currentStreamURL`, `playingShowID`, `artwork`, and `currentTime`.
  - Stream metadata is parsed and displayed on the main screen as:
    - Header: `Now Playing -` (on its own line)
    - Track line: artist/title on the next line in a larger font.
  - Artwork lookup: iTunes Search API (no key) by title and artist; falls back to `PHLogo` when no image is found.
  - Console logs for artwork lookup, HTTP response, and image download are available for troubleshooting.

- Listen Again UI
  - `ListenAgainView` lists archived shows in a scrollable top area (top 60% of usable content) and shows the selected show's artwork in the bottom area (bottom 40% of usable content).  The two areas together use 90% of the screen height to reserve space for the bottom `TopMenuView` overlay.
  - Per-show thumbnails are taken from assets (`imageName` per show). Listen Again always uses these per-show images for the bottom artwork (decoupled from live-track artwork).
  - Play/Stop buttons in each row toggle correctly and only the playing show's row shows a Stop button.
  - When a ListenAgain stream is playing, two overlay controls appear centered on the bottom artwork: Rewind 15s and Fast-forward 15s. These call `RadioPlayer.seekBackward(15)` and `RadioPlayer.seekForward(15)` respectively. Seeking is no-op for non-seekable live streams.
  - After a successful seek, a small HUD (mm:ss) shows briefly above the artwork to indicate the new playback time.

- TopMenuView (bottom overlay)
  - The bottom `TopMenuView` is an overlay present on both `ContentView` and `ListenAgainView`. It contains four buttons: Live, Listen Again, Contact, Info.
  - Contact opens the Mail app prepopulated to `contactus@cityliveradio.co.uk`.
  - Info opens the about page in the default browser: https://www.cityliveradio.co.uk/about-us
  - The overlay is safe-area aware and sits above the home indicator.

- Play button behavior
  - On `ContentView` initial appearance (app launch or returning from `ListenAgainView`) the Play button is disabled for 3 seconds to avoid accidental presses. This is deterministic and managed with a cancellable scheduled work item to avoid UI flashes when dismissing modal views.
  - There is also a verification retry flow when starting playback: the app checks `radio.isPlaying` and whether artwork has been populated and will retry play a small number of times if verification fails (configurable).

- Background audio and entitlements
  - The project is prepared for background audio. To enable background playback on-device:
    1. Open target → Signing & Capabilities → add Background Modes → check "Audio, AirPlay, and Picture in Picture".
    2. Ensure the provisioning profile/App ID includes the `com.apple.developer.background-modes` entitlement (Xcode can update the profile when using Automatic Signing and "Fix Issue").
  - If you do not want background entitlement during development, use the `NoBackground.entitlements` file (project has been adjusted to avoid requesting the entitlement unless you enable Background Modes).

Files & locations
-----------------
- App UI & player logic: `CityLiveRadio/CityLiveRadio/ContentView.swift` (includes `ContentView` and `RadioPlayer`).
- Listen Again: `CityLiveRadio/CityLiveRadio/ListenAgainView.swift` (separate view, uses `@EnvironmentObject var radio: RadioPlayer`).
- Bottom menu: `CityLiveRadio/CityLiveRadio/TopMenuView.swift`.
- Player protocol: `CityLiveRadio/CityLiveRadio/PlayerProtocol.swift` (single declaration used across code/tests).
- Assets: `CityLiveRadio/CityLiveRadio/Assets.xcassets/` (per-show images, `PHLogo`, `AppIcon.appiconset`).
- Entitlements: `CityLiveRadio/CityLiveRadio/CityLiveRadio.entitlements` and `NoBackground.entitlements` (used when background audio entitlement is not desired).
- Unit tests: `CityLiveRadio/CityLiveRadioTests/` (tests for `RadioPlayer` and artwork fallback behavior).

Build & run
-----------
Open the Xcode project and run on a simulator or device.

Xcode UI steps (recommended):
1. Open `CityLiveRadio.xcodeproj` in Xcode.
2. Select the `CityLiveRadio` scheme and a run destination (Simulator or your device).
3. For physical device: select your Development Team in Signing & Capabilities and enable Background Modes if needed.
4. Run (Cmd-R).

From Terminal (simulator, no signing):
```bash
cd /Users/paulmackay/Desktop/myProjects/ios/CityLiveRadio
xcodebuild -project CityLiveRadio.xcodeproj -scheme CityLiveRadio \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO clean build
```

Run tests (simulator):
```bash
xcodebuild -project CityLiveRadio.xcodeproj -scheme CityLiveRadio \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO clean test
```

Artwork & thumbnails guidance
-----------------------------
- Thumbnails (used in Listen Again list): UI uses ~64×64 points.
  - Provide images: 1x = 64×64 px, 2x = 128×128 px, 3x = 192×192 px.
- Large artwork (Now Playing): provide 600×600 or 1024×1024 for best quality.
- Per-show images should be added as named image sets to `Assets.xcassets` and referenced by the show's `imageName`.

App icons (appiconset)
----------------------
Place exact-size PNGs in `Assets.xcassets/AppIcon.appiconset` using these filenames and pixel sizes (case-sensitive):
- `AppIcon-20x20@2x.png` — 40 × 40 px
- `AppIcon-20x20@3x.png` — 60 × 60 px
- `AppIcon-29x29@2x.png` — 58 × 58 px
- `AppIcon-29x29@3x.png` — 87 × 87 px
- `AppIcon-40x40@2x.png` — 80 × 80 px
- `AppIcon-40x40@3x.png` — 120 × 120 px
- `AppIcon-60x60@2x.png` — 120 × 120 px
- `AppIcon-60x60@3x.png` — 180 × 180 px
- `AppIcon-76x76@1x.png` — 76 × 76 px
- `AppIcon-76x76@2x.png` — 152 × 152 px
- `AppIcon-83.5x83.5@2x.png` — 167 × 167 px
- `AppIcon-1024x1024@1x.png` — 1024 × 1024 px (App Store / ios-marketing)

I updated `Contents.json` and verified `AppIcon.appiconset` contains a 1024×1024 image and all referenced filenames exist. If you want, I can generate the full set from the 1024 source and commit them.

Troubleshooting & logs
----------------------
- Check Xcode console for logs from `RadioPlayer` and artwork retrieval. The app logs metadata events, iTunes search URLs, HTTP statuses and image download results.
- If artwork is missing: confirm the iTunes search JSON shows results or check asset names/case sensitivity.

Committing & pushing
---------------------
I can commit and push these README/asset changes to branch `menu`. Locally run:

```bash
cd /Users/paulmackay/Desktop/myProjects/ios/CityLiveRadio
# switch/create branch
git checkout -B menu
# stage changes
git add -A
git commit -m "chore: update README and fix AppIcon assets"
# push
git remote get-url origin || git remote add origin https://github.com/McNast13/CityLiveRadioIOS.git
git push -u origin menu
```

If you want me to try to push from this environment say "try push here" and I'll attempt it (may require your credentials).

Questions / next suggestions
--------------------------
- Would you like me to generate a full, correctly-sized app icon set from the 1024×1024 source and commit them? (recommended)
- Would you like the README to include exact test outputs or CI instructions (GitHub Actions)?

Which of the above should I do next? (generate icons / commit & push / add CI / nothing)
