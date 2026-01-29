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
- Live radio playback using `AVPlayer` with an `AVAudioSession` configured for `.playback`.
- `RadioPlayer` `ObservableObject` that manages play/pause/stop, switching between live and listen-again streams, and exposes:
  - `isPlaying`, `trackInfo`, `currentStreamURL`, `playingShowID` and `artwork` as `@Published` properties.
- Metadata handling and artwork lookup:
  - The app parses timed metadata from streams and displays "Now Playing -" with artist/title on the main screen when available.
  - Primary artwork lookup: iTunes Search API (no API key). The app searches by title and (when present) artist; if no artwork is found a placeholder `PHLogo` asset is used.
  - Detailed console logs are printed for artwork lookups and image download steps to help diagnose failures.
- Listen Again UI:
  - `ListenAgainView` lists archived shows in a scrollable card-style top area and displays the selected show's artwork in the lower area.
  - The layout reserves 90% of the screen for the content (top 60% list + bottom 40% artwork). The remaining ~10% is reserved for the bottom `TopMenuView` overlay so the menu doesn't obscure content.
  - Playing a ListenAgain stream stops any current playback and shows the related show image (images are taken from the asset catalog per-show `imageName`).
  - When returning from `ListenAgainView`, the app restores/prepares the live player.
- UI & behavior updates:
  - A small delay: when `ContentView` loads (app launch or returning from ListenAgain), the Play button is disabled for 3 seconds to avoid accidental quick taps.
  - The Play/Stop controls in `ListenAgainView` toggle correctly per-row: pressing Play on a show turns that row's button to Stop; pressing Stop stops playback and resets buttons.
  - The `TopMenuView` (bottom overlay) now includes a fourth Info icon which opens the about page (https://www.cityliveradio.co.uk/about-us) in the default browser; this handler is wired in both `ContentView` and `ListenAgainView`.
- Background audio:
  - The project is prepared to support background audio. To use background playback on-device enable Background Modes → Audio in the target Signing & Capabilities and ensure the provisioning profile includes the entitlement.

Where to find things
--------------------
- App UI and player logic: `CityLiveRadio/CityLiveRadio/ContentView.swift` (contains `ContentView` and `RadioPlayer`).
- `ListenAgainView`: `CityLiveRadio/CityLiveRadio/ListenAgainView.swift` (now a separate view file, uses `@EnvironmentObject RadioPlayer`).
- Top menu component: `CityLiveRadio/CityLiveRadio/TopMenuView.swift` (includes Live, Listen Again, Contact, Info buttons).
- Assets (images/icons): `CityLiveRadio/CityLiveRadio/Assets.xcassets/` (contains `cityLogo`, per-show image sets, `PHLogo`, and the `AppIcon.appiconset`).
- Entitlements file: `CityLiveRadio/CityLiveRadio/CityLiveRadio.entitlements` (background audio key).
- Unit tests: `CityLiveRadio/CityLiveRadioTests/` (tests cover `RadioPlayer` behavior and metadata parsing).

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
  - Artwork for the current track is fetched from the iTunes Search API and shown under the track info when found; if no artwork is returned the `PHLogo` placeholder is used.
- Listen Again:
  - The Listen Again view lists archived shows with per-show thumbnails, title and a Play/Stop control in each row.
  - The top list and bottom artwork together use 90% of the visible height; the bottom `TopMenuView` overlay occupies the remaining space so content is not covered.
  - Starting a ListenAgain stream stops any current playback. When a ListenAgain stream is playing, its row shows Stop; pressing Stop stops playback and resets row buttons.
- Menu, contact & info:
  - The top-left hamburger triggers navigation (Listen Again) and Contact (mailto: contactus@cityliveradio.co.uk).
  - The bottom `TopMenuView` overlay contains four icons: Live, Listen Again, Contact, Info; Info opens the about page: https://www.cityliveradio.co.uk/about-us.

Artwork / iTunes integration
----------------------------
- iTunes Search API is used as primary artwork source. The app searches by title and optionally artist.
- Console logging includes the iTunes request URL, HTTP status, a short JSON preview, chosen artwork URL (upgraded to a larger size when possible), and image download status.
- If the iTunes lookup or image download fails, the app falls back to showing the `PHLogo` asset.

Thumbnails & artwork assets guidance
-----------------------------------
- Recommended thumbnail display size (UI uses 64×64 points): supply these image files in an image set:
  - 1x: 64×64 px
  - 2x: 128×128 px
  - 3x: 192×192 px
- Recommended large artwork for "Now Playing": provide a 600×600 or 1024×1024 pixel image for best quality.
- Square images are preferred. If your source isn’t square, pad or crop to a square canvas so rounded corners won't cut off content.
- Add per-show asset sets in `Assets.xcassets` and set each show's `imageName` to the asset name in `ListenAgainView`/`ContentView` shows array.

Logging & troubleshooting
------------------------
- Check Xcode's debug console for `fetchArtworkFromiTunes:` logs when artwork doesn't appear. The app logs helpful diagnostic info for network errors, JSON parse issues and final image download status.
- Common issues:
  - Stream provides no timed metadata; in that case trackInfo will be blank.
  - iTunes returns no results for the query term; the app will show `PHLogo` as fallback.
  - Device/simulator TLS or network issues may block the iTunes or image download requests; ensure connectivity.

Signing & provisioning
----------------------
- To run on device you must have a provisioning profile for the bundle identifier (`PMackay.CityLiveRadio`) and a selected Development Team in Xcode.
- Quick fix: in Xcode → Preferences → Accounts add your Apple ID, then in the project target → Signing & Capabilities select your Team and click "Fix Issue" if prompted.

Testing & unit tests
--------------------
- Unit tests target `CityLiveRadioTests` include tests for `RadioPlayer` and its metadata parsing. Run tests via Xcode Test (Cmd-U) or the `xcodebuild` command above.

Repository notes
----------------
- Active working branch with recent UI and metadata/artwork changes: `menu` (contains the TopMenu Info button, ListenAgain layout changes and other UI fixes). Push target: `origin/menu` (remote: https://github.com/McNast13/CityLiveRadioIOS.git).
- If you want these changes merged to `main` I can open a PR or merge on your behalf.

Contributing
------------
- To add a new Listen Again show: add an entry to the `shows` array in `ListenAgainView.swift` (use the `Show` struct fields: `title`, `url`, `imageName`) and add a corresponding image asset to `Assets.xcassets`.
- To add artwork caching persistence, a disk cache or `NSCache` implementation is recommended.

Contact
-------
- App Contact email used in UI: contactus@cityliveradio.co.uk

License
-------
This project bundles references to third-party streams; ensure you have permission before redistributing recordings. The code is provided as-is.

App icon filenames and exact pixel sizes
---------------------------------------
Add the following PNG files to `CityLiveRadio/CityLiveRadio/Assets.xcassets/AppIcon.appiconset` (these are the exact filenames and pixel dimensions iOS expects for each slot):

- AppIcon-20x20@2x.png — 40 × 40 px (20pt @2x)
- AppIcon-20x20@3x.png — 60 × 60 px (20pt @3x)
- AppIcon-29x29@2x.png — 58 × 58 px (29pt @2x)
- AppIcon-29x29@3x.png — 87 × 87 px (29pt @3x)
- AppIcon-40x40@2x.png — 80 × 80 px (40pt @2x)
- AppIcon-40x40@3x.png — 120 × 120 px (40pt @3x)
- AppIcon-60x60@2x.png — 120 × 120 px (60pt @2x)
- AppIcon-60x60@3x.png — 180 × 180 px (60pt @3x)
- AppIcon-76x76@1x.png — 76 × 76 px (76pt @1x)
- AppIcon-76x76@2x.png — 152 × 152 px (76pt @2x)
- AppIcon-83.5x83.5@2x.png — 167 × 167 px (83.5pt @2x)
- AppIcon-1024x1024@1x.png — 1024 × 1024 px (App Store / large icon)

Notes:
- Filenames are case-sensitive. Place these files directly in the `AppIcon.appiconset` folder and ensure `Contents.json` references the same filenames.
- The best-quality source is a square 1024×1024 PNG; resize down to the exact dimensions above to avoid scaling artifacts.
- After replacing icons, clean the build and reinstall the app on device (uninstall first) to ensure iOS updates the displayed icon (SpringBoard caches icons).
