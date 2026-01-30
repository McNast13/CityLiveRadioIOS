import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ListenAgainView: View {
    @EnvironmentObject private var radio: RadioPlayer
    @Environment(\.dismiss) private var dismiss

    struct Show: Identifiable {
        let id: String
        let title: String
        let url: URL
        let imageName: String
        init(title: String, url: URL, imageName: String) { self.id = url.absoluteString; self.title = title; self.url = url; self.imageName = imageName }
    }

    private var shows: [Show] = [
        Show(title: "Not The 9 O'Clock Show", url: URL(string: "https://cityliveradiouk.co.uk/Streaming/ListenAgain/NTNOCS.mp3")!, imageName: "NineOclock"),
        Show(title: "Red Bearded Viking Show", url: URL(string: "https://cityliveradiouk.co.uk/Streaming/ListenAgain/RBV.mp3")!, imageName: "RedBeard"),
        Show(title: "The Country Mile", url: URL(string: "https://cityliveradiouk.co.uk/Streaming/ListenAgain/CM.mp3")!, imageName: "CountryMile"),
        Show(title: "Ginger and Nuts", url: URL(string: "https://cityliveradiouk.co.uk/Streaming/ListenAgain/GingerandNuts.mp3")!, imageName: "GingerNuts"),
        Show(title: "Weekend Anthems", url: URL(string: "https://cityliveradiouk.co.uk/Streaming/ListenAgain/WeekendAnthems.mp3")!, imageName: "WeekendAnthems"),
        Show(title: "Saturday Club Classics", url: URL(string: "https://cityliveradiouk.co.uk/Streaming/ListenAgain/scc.mp3")!, imageName: "ClubClassics")
    ]

    @State private var selectedShowID: String? = nil
    // Observable image name used for the bottom artwork. Changing this forces the Image to refresh via .id
    @State private var bottomImageName: String? = nil
    // HUD state: shows recent seeked time briefly
    @State private var hudTime: Double? = nil
    @State private var hudWorkItem: DispatchWorkItem? = nil

    // Find an asset image name for a show id (tolerant matching using contains if needed)
    private func imageNameForID(_ id: String?) -> String? {
        guard let id = id else { return nil }
        if let exact = shows.first(where: { $0.id == id }) { return exact.imageName }
        if let contains = shows.first(where: { id.contains($0.id) }) { return contains.imageName }
        if let contained = shows.first(where: { $0.id.contains(id) }) { return contained.imageName }
        return nil
    }

    // Show HUD for a short duration displaying the given seconds value
    private func showHUD(for seconds: Double) {
        hudWorkItem?.cancel()
        hudWorkItem = nil
        DispatchQueue.main.async {
            hudTime = seconds
            let work = DispatchWorkItem {
                DispatchQueue.main.async { hudTime = nil }
            }
            hudWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
    }

    // Local helper to open Mail app for Contact Us
    private func openContactMail() {
        #if canImport(UIKit)
        let to = "contactus@cityliveradio.co.uk"
        if let url = URL(string: "mailto:\(to)") {
            DispatchQueue.main.async {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        #endif
    }

    // Local helper to open the about page in the default browser
    private func openAboutPage() {
        #if canImport(UIKit)
        if let url = URL(string: "https://www.cityliveradio.co.uk/about-us") {
            DispatchQueue.main.async { UIApplication.shared.open(url, options: [:], completionHandler: nil) }
        }
        #endif
    }

    // Small helper to build a show row — extracted to top-level of the struct to reduce body complexity
    @ViewBuilder
    private func showRow(_ show: Show) -> some View {
        let isPlaying = (radio.playingShowID == show.id && radio.isPlaying)
        HStack(spacing: 12) {
            Image(show.imageName)
                .renderingMode(.original)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipped()
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(UIColor.separator), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(show.title)
                    .foregroundColor(Color.primary)
                    .font(.headline)
                    .lineLimit(2)
                Text(show.url.host ?? "")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }

            Spacer()

            Button(action: {
                withAnimation {
                    print("ListenAgain button tapped for show=\(show.title), isPlaying=\(isPlaying)")
                    if isPlaying {
                        // stop playback and clear selection + bottom image
                        radio.stop()
                        selectedShowID = nil
                        bottomImageName = nil
                    } else {
                        // select and show the image immediately, then start stream
                        selectedShowID = show.id
                        bottomImageName = show.imageName
                        print("ListenAgain: selected=\(selectedShowID ?? "nil") bottomImage=\(bottomImageName ?? "nil") -> playing url=\(show.url.absoluteString)")
                        radio.playStream(url: show.url)
                    }
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    Text(isPlaying ? "Stop" : "Play")
                }
                .font(.subheadline)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(isPlaying ? Color.red : Color.accentColor)
                .foregroundColor(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(UIColor.separator).opacity(0.6), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    // Bottom artwork view extracted to reduce complexity in the body
    @ViewBuilder
    private func bottomArtwork() -> some View {
        // Decide which image to show: explicit bottomImageName -> selectedShowID -> playingShowID -> fallback PHLogo
        let imgToShow = bottomImageName
            ?? imageNameForID(selectedShowID)
            ?? imageNameForID(radio.playingShowID)
            ?? "ListenAgainLogo"

        // Determine current show by selectedShowID, playingShowID, or matching currentStreamURL
        let currentURLStr = radio.currentStreamURL?.absoluteString
        let show = shows.first(where: { $0.id == selectedShowID })
            ?? shows.first(where: { $0.id == radio.playingShowID })
            ?? shows.first(where: { $0.url.absoluteString == currentURLStr })
        let isPlayingThisShow = radio.isPlaying && (show != nil)

        ZStack(alignment: .center) {
            Image(imgToShow)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .id(imgToShow)
                .cornerRadius(12)
                .shadow(radius: imgToShow == "PHLogo" ? 4 : 8)
                .padding(imgToShow == "PHLogo" ? 24 : 20)
                .onAppear { print("bottomArtwork -> showing=\(imgToShow) selected=\(String(describing: selectedShowID)) playing=\(String(describing: radio.playingShowID)) currentStream=\(String(describing: radio.currentStreamURL))") }

            if isPlayingThisShow {
                HStack(spacing: 36) {
                    Button(action: { radio.seekBackward(15) }) {
                        Image(systemName: "gobackward.15")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Rewind 15 seconds")

                    Button(action: { radio.seekForward(15) }) {
                        Image(systemName: "goforward.15")
                            .font(.title)
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Fast forward 15 seconds")
                }
                .padding()
                .transition(.opacity)
            }

            if let t = hudTime {
                VStack {
                    Text(formatTime(t))
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(10)
                        .shadow(radius: 6)
                }
                .padding(.bottom, 40)
                .transition(.opacity)
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "-:--" }
        let s = Int(round(seconds))
        let m = s / 60
        let sec = s % 60
        return String(format: "%d:%02d", m, sec)
    }

    // Small subview for the top 60% list area (broken out to help the compiler)
    @ViewBuilder
    private func topArea(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Centered header
            Text("Listen Again")
                .font(.largeTitle)
                .bold()
                .foregroundColor(Color.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding([.horizontal, .top])

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(shows) { show in
                        showRow(show)
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .frame(height: height)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(UIColor.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(UIColor.separator).opacity(0.9), lineWidth: 2)
        )
        .padding(.top, 8)
    }

    @ViewBuilder
    private func bottomArea(height: CGFloat) -> some View {
        ZStack {
            Color.black
            bottomArtwork()
        }
        .frame(height: height)
    }

    // Return bottom safe area inset for the current window (iOS)
    private func currentBottomSafeArea() -> CGFloat {
        #if canImport(UIKit)
        if #available(iOS 15.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })?
                .safeAreaInsets.bottom ?? 0
        } else {
            return UIApplication.shared.keyWindow?.safeAreaInsets.bottom ?? 0
        }
        #else
        return 0
        #endif
    }

    var body: some View {
        GeometryReader { geo in
            // Reserve 10% of total height for the persistent TopMenuView; split remaining 90% 60/40
            let usable = geo.size.height * 0.90
            let topH = usable * 0.6
            let bottomH = usable * 0.4
            VStack(spacing: 0) {
                topArea(height: topH)
                bottomArea(height: bottomH)

                TopMenuView(isListenAgainActive: true,
                            onCityLive: {
                                radio.restoreLive()
                                dismiss()
                            },
                            onListenAgain: {
                                selectedShowID = nil
                                bottomImageName = nil
                                radio.pause()
                            },
                            onContact: { openContactMail() },
                            onInfo: { openAboutPage() })
                    .padding(.bottom, currentBottomSafeArea() + 8)
                    .zIndex(1000)
            }
            .background(Color.black.ignoresSafeArea())
            .onAppear {
                radio.pause()
                bottomImageName = imageNameForID(selectedShowID) ?? imageNameForID(radio.playingShowID) ?? imageNameForID(radio.currentStreamURL?.absoluteString)
            }
            .onDisappear {
                radio.restoreLive()
                selectedShowID = nil
            }
        } // GeometryReader
        // Hide the automatic navigation back button when embedded in a NavigationStack
          .navigationBarBackButtonHidden(true)
          // Disable interactive pop (swipe-to-go-back) to prevent users from navigating back
          .background(NavigationConfigurator { nav in
               nav.interactivePopGestureRecognizer?.isEnabled = false
               // Ensure the top view controller has no back button and the navigation bar is hidden
               nav.topViewController?.navigationItem.hidesBackButton = true
               nav.setNavigationBarHidden(true, animated: false)
           })
          // Ensure the navigation bar is hidden to prevent any visible back controls
          .navigationBarHidden(true)
          // Ensure there's no leading toolbar item (extra defense against back chevron)
          .toolbar {
              ToolbarItem(placement: .navigationBarLeading) {
                  // empty to suppress default back button
                  EmptyView()
              }
          }
          .onChange(of: radio.isPlaying) { _old, isPlaying in
              if !isPlaying {
                  // when playback stops, clear any selected show so UI updates to 'Play'
                  selectedShowID = nil
              }
          }
          .onChange(of: radio.playingShowID) { _old, playingID in
              // When the player sets which show is playing, reflect that in selection so the row turns to Stop
              if let pid = playingID {
                 selectedShowID = pid
             } else {
                 selectedShowID = nil
             }
            // update bottom artwork to match the playing show (or clear)
            bottomImageName = imageNameForID(playingID)
         }
         .onChange(of: radio.currentStreamURL) { _old, newURL in
             // When the player's current stream changes, select the matching show (if any)
             if let u = newURL {
                 if let match = shows.first(where: { $0.url.absoluteString == u.absoluteString }) {
                     selectedShowID = match.id
                 } else {
                     // external stream (e.g., live) — clear selection
                     selectedShowID = nil
                 }
             } else {
                 selectedShowID = nil
             }
            bottomImageName = imageNameForID(newURL?.absoluteString)
         }
         // Show HUD when currentTime changes (seek completed)
        .onChange(of: radio.currentTime) { _old, newTime in
            if let t = newTime { showHUD(for: t) }
        }
    }
}

// Preview for SwiftUI canvas
#Preview {
    ListenAgainView().environmentObject(RadioPlayer())
}
