import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ListenAgainView: View {
    @EnvironmentObject private var radio: RadioPlayer

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

    // Find an asset image name for a show id (tolerant matching using contains if needed)
    private func imageNameForID(_ id: String?) -> String? {
        guard let id = id else { return nil }
        if let exact = shows.first(where: { $0.id == id }) { return exact.imageName }
        if let contains = shows.first(where: { id.contains($0.id) }) { return contains.imageName }
        if let contained = shows.first(where: { $0.id.contains(id) }) { return contained.imageName }
        return nil
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
            ?? "PHLogo"

        Image(imgToShow)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .id(imgToShow) // force SwiftUI to replace the Image when the name changes
            .cornerRadius(12)
            .shadow(radius: imgToShow == "PHLogo" ? 4 : 8)
            .padding(imgToShow == "PHLogo" ? 24 : 20)
            .onAppear { print("bottomArtwork -> showing=\(imgToShow) selected=\(String(describing: selectedShowID)) playing=\(String(describing: radio.playingShowID)) currentStream=\(String(describing: radio.currentStreamURL))") }
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing:0) {
                // TOP 60%: header + scrollable list on a light gray background with border
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
                         } // LazyVStack
                         .padding(.vertical, 12)
                     } // ScrollView
                 } // top VStack
                 .frame(height: geo.size.height * 0.6)
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

                // BOTTOM 40%: black background (same as main view), shows artwork or PHLogo placeholder
                ZStack {
                    Color.black
                    bottomArtwork()
                }
                .frame(height: geo.size.height * 0.4)
            } // VStack root
            // Replace the previous solid black background with the same top->bottom gradient used in ContentView
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.white, Color.black]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .onAppear {
                // Pause live playback when showing Listen Again
                radio.pause()
                // initialize bottom image from current selection/player
                bottomImageName = imageNameForID(selectedShowID) ?? imageNameForID(radio.playingShowID) ?? imageNameForID(radio.currentStreamURL?.absoluteString)
            }
            .onDisappear {
                // When leaving ListenAgain, restore live player (without autoplay)
                radio.restoreLive()
                selectedShowID = nil
            }
         } // GeometryReader
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
    }
}

// Preview for SwiftUI canvas
#Preview {
    ListenAgainView().environmentObject(RadioPlayer())
}
