CityLiveRadio iOS
=================

A SwiftUI iOS frontend for the CityLiveRadio online station with a "Listen Again" list of previously aired shows and artwork lookup.

Overview
--------
- Main purpose: play the live radio stream and let the user play archived shows (Listen Again).
- Live stream (Play/Stop): https://streaming.live365.com/a91939
- Listen Again recordings included in the app (title — stream URL):
  - Not The 9 O'Clock Show — https://cityliveradiouk.co.uk/Streaming/ListenAgain/NTNOCS.mp3
  - Red Bearded Viking Show — https://cityliveradiouk.co.uk/Streaming/ListenAgain/RBV.mp3
  - The Country Mile — https://cityliveradiouk.co.uk/Streaming/ListenAgain/CM.mp3
  - Ginger and Nuts — https://cityliveradiouk.co.uk/Streaming/ListenAgain/GingerandNuts.mp3
  - Weekend Anthems — https://cityliveradiouk.co.uk/Streaming/ListenAgain/WeekendAnthems.mp3
  - Saturday Club Classics — https://cityliveradiouk.co.uk/Streaming/ListenAgain/scc.mp3

Key features (latest)
---------------------
- Live radio playback using `AVPlayer` with an AVAudioSession configured for `.playback`.
- `RadioPlayer` ObservableObject that manages play/pause/stop, switching between live and listen-again streams, and exposes:
  - `isPlaying`, `trackInfo`, `currentStreamURL`, and `artwork` as `@Published` properties.
- Metadata handling:
  - The app parses timed metadata from streams and displays "Now Playing -" with artist/title on the main screen when available.
  - When track metadata arrives the app automatically queries the iTunes Search API (primary source) to retrieve artwork for the track and displays it under the track info.
  - Detailed console logs are printed for iTunes queries and image download steps to help diagnose artwork failures.
- Listen Again UI:
  - A modern `ListenAgainView` with card-style rows, per-show thumbnails, Play/Stop per row and a visible "Now playing" row when a listen-again stream is active.
  - Entering Listen Again pauses live playback; selecting a show stops any current stream and plays the chosen recording; leaving the view restores/prepares the live player.
- Navigation & menu:
  - A hamburger menu in the top-left offers "Listen Again" (navigates to the view) and "Contact Us" (opens the Mail app prefilled). 
- Per-show thumbnails:
  - Each show has an `imageName` field and loads an image from the asset catalog. By default thumbnails use the `cityLogo` asset and you can add per-show assets later.
- Background audio:
  - The project is configured to support background audio (Info/entitlements settings are present). To run on-device, enable the Background Modes -> Audio capability in Xcode Signing & Capabilities and ensure your provisioning profile includes it.

Where to find things
--------------------
- App UI and player logic: `CityLiveRadio/CityLiveRadio/ContentView.swift` (contains `ContentView`, `ListenAgainView` and `RadioPlayer`).
- Assets (images/icons): `CityLiveRadio/CityLiveRadio/Assets.xcassets/` (contains `cityLogo`, per-show image sets, and `AppIcon.appiconset`).
- Entitlements file: `CityLiveRadio/CityLiveRadio/CityLiveRadio.entitlements` (background audio key).
- Unit tests: `CityLiveRadio/CityLiveRadioTests/` (tests for `RadioPlayer` behavior and metadata parsing).

Build & run (quick)
-------------------
Open the Xcode project and run on a simulator or device.

Xcode UI (recommended)
1. Open `CityLiveRadio.xcodeproj` in Xcode.
2. Select the `CityLiveRadio` scheme and a run destination (Simulator or your device).
3. If running on a physical device: in the project target → Signing & Capabilities check “Automatically manage signing” and select your Development Team (Personal Team is supported for local dev). Also enable Background Modes → Audio if you want background playback.
4. Run (Cmd-R).

From Terminal (simulator, no signing required):
```bash
cd /path/to/CityLiveRadio
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

Behavior details
----------------
- Live playback:
  - The Play button on the main screen toggles the live stream (https://streaming.live365.com/a91939).
  - Track metadata (artist/title) is shown below the Play button when available, with the header "Now Playing -" on its own line and the track text beneath.
  - Artwork for the current track is fetched from the iTunes Search API and shown under the track info when found.
- Listen Again:
  - The Listen Again view lists archived shows with thumbnails, title, host/URL info and a Play/Stop control.
  - Entering the view pauses any live playback. Playing a recording stops any existing playback and begins the recording stream. Pressing Back stops recording playback and restores (prepares) the live player so pressing Play resumes live radio.
- Menu & contact:
  - The hamburger menu in the top-left contains two items: "Listen Again" and "Contact Us". Contact opens a `mailto:` link to `contactus@cityliveradio.co.uk`.

Artwork / iTunes integration
----------------------------
- The app uses the iTunes Search API as the primary artwork source (no API key required). It searches by title and, when available, artist.
- The lookup publishes detailed console logs showing the iTunes request URL, HTTP status, JSON preview and image download status. Use Xcode's debug console to view these logs during runtime.
- The app caches artwork in memory for the app lifecycle to reduce repeated network requests. If you want persistent disk caching, we can add that as a follow-up.

Thumbnails & artwork assets guidance
-----------------------------------
- Recommended thumbnail display size (UI uses 64×64 points): supply these image files in an image set:
  - 1x: 64×64 px
  - 2x: 128×128 px
  - 3x: 192×192 px
- Recommended large artwork for "Now Playing": provide a 600×600 or 1024×1024 pixel image for best quality.
- Square images are preferred. If your source isn’t square, pad or crop to a square canvas so rounded corners or cornerRadius won't cut off content.
- Add per-show asset sets in `Assets.xcassets` (e.g. `ntnocs.imageset`, `rbv.imageset`) and set the `imageName` in `ContentView.swift`'s `shows` array to point to them.

Logging & troubleshooting
-------------------------
- If artwork does not appear, open Xcode's debug console and look for `fetchArtworkFromiTunes:` prints. The app logs:
  - The constructed iTunes Search URL, HTTP status, a small JSON preview, and the chosen artwork URL (upgraded to 600×600 when possible).
  - Image download HTTP status and any network errors or JSON parse errors.
- Common issues:
  - No metadata from stream: some streams do not publish timed metadata; metadata may be absent.
  - iTunes returns no match for the query term — try different metadata formats or enable artist-only or title-only fallbacks.
  - TLS/Network errors: ensure device/simulator has working network and can reach `itunes.apple.com`.

Signing & provisioning
----------------------
- To run on device you must be signed and have a provisioning profile for the app bundle identifier (`PMackay.CityLiveRadio`) and the selected Development Team.
- Quick fix: in Xcode → Preferences → Accounts add your Apple ID, then in the project target → Signing & Capabilities select your Team and click "Fix Issue" if prompted.
- If you prefer changing the bundle identifier to your own (e.g. `com.yourname.CityLiveRadio`) you can edit the target's bundle id in Xcode or ask me to make that repo change.

Testing & unit tests
--------------------
- Unit tests cover `RadioPlayer` behavior (play/pause/toggle, metadata parsing). Use Xcode Test (Cmd-U) or `xcodebuild ... test` above to run them.
- For artwork/network tests we use URLSession stubbing patterns (can be added) to avoid live network calls.

Repository notes
----------------
- Active working branch with recent UI and metadata/artwork changes: `menu` (contains hamburger menu, ListenAgain UI improvements and recent fixes). The branch has been pushed to the remote `origin` as `menu`.
- If you want these changes merged to `main` I can open a PR or push a merge commit.

Contributing
------------
- To add a new Listen Again show: add an entry to the `shows` array in `ContentView.swift` (use the `Show` struct fields: `title`, `url`, `imageName`) and add a corresponding image asset to `Assets.xcassets`.
- To add artwork caching persistence, a disk cache or `NSCache` implementation is recommended.

Next steps / suggestions
------------------------
- Provide square source images for per-show thumbnails and for the app icon set (preferred ≥1024×1024 for best results).
- Add persistent artwork cache to avoid repeated network calls across app launches.
- Optionally add a small settings screen to toggle verbose artwork logs.

Contact
-------
- App Contact email used in UI: contactus@cityliveradio.co.uk

License
-------
This project bundles references to third-party streams; ensure you have permission before redistributing recordings. The code is provided as-is.
