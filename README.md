CityLiveRadio iOS
=================

A small SwiftUI iOS frontend for the CityLiveRadio online station and a "Listen Again" list of previously aired shows.

Overview
--------
- Main purpose: play the live radio stream and let the user play archived shows (Listen Again).
- Live stream (Play/Stop): https://streaming.live365.com/a91939
- Listen Again recordings included in the app:
  - Not The 9 O'Clock Show — https://cityliveradiouk.co.uk/Streaming/ListenAgain/NTNOCS.mp3
  - Red Bearded Viking Show — https://cityliveradiouk.co.uk/Streaming/ListenAgain/RBV.mp3
  - The Country Mile — https://cityliveradiouk.co.uk/Streaming/ListenAgain/CM.mp3
  - Ginger and Nuts — https://cityliveradiouk.co.uk/Streaming/ListenAgain/GingerandNuts.mp3
  - Weekend Anthems — https://cityliveradiouk.co.uk/Streaming/ListenAgain/WeekendAnthems.mp3
  - Saturday Club Classics — https://cityliveradiouk.co.uk/Streaming/ListenAgain/scc.mp3

Where things live
-----------------
- App entry and UI: `CityLiveRadio/CityLiveRadio/ContentView.swift`
- Assets (images): `CityLiveRadio/CityLiveRadio/Assets.xcassets/` (contains `cityLogo` and `listenAgain` sets)
- Unit tests: `CityLiveRadio/CityLiveRadioTests/CityLiveRadioTests.swift`

Build & run
-----------
Open the Xcode project and run on a simulator or device:

1. Open the workspace in Xcode:

```bash
open CityLiveRadio.xcodeproj
```

2. Select the `CityLiveRadio` scheme and a Simulator (or a device). If running on a physical device, pick your device and make sure a development team is selected in Signing & Capabilities.

3. Build & run (Cmd-R) from Xcode.

From the terminal (simulator):

```bash
# build
xcodebuild -project CityLiveRadio.xcodeproj -scheme CityLiveRadio \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO clean build

# run tests
xcodebuild -project CityLiveRadio.xcodeproj -scheme CityLiveRadio \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO clean test
```

Signing / Device notes
----------------------
- The project will require a development team to be set for running on a physical device. In Xcode, open the target -> Signing & Capabilities and select your team.
- To allow background audio (if desired), enable Background Modes -> Audio in the target Capabilities.

Behavior notes
--------------
- Tapping Play on the main screen plays the live stream. While playing, metadata parsed from the stream will appear under the button as:

  Now Playing -
  <Artist/Title>

  The header and the track text are on separate lines, header is larger.

- Tapping the Listen Again image navigates to a list of archived shows. When the Listen Again view appears, live playback is paused. Selecting a show will stop any existing playback and play the chosen MP3 stream. Hitting Back will stop any listen-again stream and re-prepare the live stream so pressing Play on the main screen resumes the live stream.

Testing
-------
- There are unit tests in `CityLiveRadioTests` (basic RadioPlayer behavior). Run them from Xcode or with the `xcodebuild ... test` command above.

Known issues & troubleshooting
------------------------------
- If the preview or run fails with "requires a development team", set your team in Signing & Capabilities.
- If run-time audio doesn't start on device, verify Developer Mode and that the device has network connectivity.
- Some streams may not provide metadata; the app attempts to parse AV metadata and falls back to empty values.

Contributing & next steps
-------------------------
- Add more Listen Again items to `ContentView.swift` (the `shows` array inside `ListenAgainView`).
- Add unit tests covering `playStream` and `restoreLive` flows.

License
-------
This project contains open references to online streams; check the streams' terms of use before redistribution. The code here is provided as-is.
