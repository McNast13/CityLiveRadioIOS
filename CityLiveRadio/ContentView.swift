//
//  ContentView.swift
//  CityLiveRadio
//
//  Created by paul mackay on 19/12/2025.
//

import SwiftUI
import AVFoundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

// Protocol used by tests to inject a mock player implementation.
public protocol PlayerProtocol {
    func play()
    func pause()
}

// Small ObservableObject that manages an AVPlayer for the radio stream.
final class RadioPlayer: NSObject, ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var trackInfo: String? = nil
    @Published var currentStreamURL: URL? = nil
    @Published var artwork: UIImage? = nil

    private var player: AVPlayer?
    private var metadataOutput: AVPlayerItemMetadataOutput?

    // Optional injected player (used by unit tests)
    private var testPlayer: PlayerProtocol? = nil

    // canonical live stream URL
    private let liveStreamURL = URL(string: "https://streaming.live365.com/a91939")!

    // Convenience initializer for tests to inject a mock player
    convenience init(player: PlayerProtocol) {
        self.init()
        self.testPlayer = player
    }

    override init() {
        super.init()
        // Prepare live stream but don't autoplay
        preparePlayer(with: liveStreamURL, autoPlay: false)

        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
        #endif
    }

    private func preparePlayer(with url: URL, autoPlay: Bool) {
        // remove old metadata output
        if let currentItem = player?.currentItem, let output = metadataOutput {
            currentItem.remove(output)
        }

        // clear artwork until new metadata arrives
        DispatchQueue.main.async { self.artwork = nil }

        let item = AVPlayerItem(url: url)
        metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput?.setDelegate(self, queue: DispatchQueue.main)
        if let output = metadataOutput { item.add(output) }

        player = AVPlayer(playerItem: item)
        currentStreamURL = url

        if autoPlay {
            player?.play()
            DispatchQueue.main.async { self.isPlaying = true }
        }
    }

    // Play the currently configured player, or recreate the live player if none
    func play() {
        // If a test player was injected, delegate to it for unit tests
        if let test = testPlayer {
            test.play()
            DispatchQueue.main.async { self.isPlaying = true }
            return
        }
        if player == nil {
            // recreate the live player and start
            preparePlayer(with: liveStreamURL, autoPlay: true)
            return
        }
        player?.play()
        DispatchQueue.main.async { self.isPlaying = true }
    }

    func pause() {
        if let test = testPlayer {
            test.pause()
            DispatchQueue.main.async { self.isPlaying = false }
            return
        }
        player?.pause()
        DispatchQueue.main.async { self.isPlaying = false }
    }

    // Stop playback and clear current player (used when switching streams)
    func stop() {
        if testPlayer != nil {
            // For injected test player just update state
            DispatchQueue.main.async {
                self.isPlaying = false
                self.currentStreamURL = nil
                self.trackInfo = nil
                self.artwork = nil
            }
            return
        }
        player?.pause()
        player = nil
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentStreamURL = nil
            self.trackInfo = nil
            self.artwork = nil
        }
    }

    // Restore live player (prepare but do not autoplay)
    func restoreLive() {
        // If live already prepared and player exists, just pause
        if currentStreamURL == liveStreamURL {
            pause()
            return
        }
        stop()
        preparePlayer(with: liveStreamURL, autoPlay: false)
    }

    // Toggle play/pause
    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    // Play an arbitrary listen-again stream: stop current and prepare new
    func playStream(url: URL) {
        if currentStreamURL == url {
            if !isPlaying { play() }
            return
        }
        stop()
        preparePlayer(with: url, autoPlay: true)
    }

    // Metadata parsing
    func updateMetadata(from metadata: [AVMetadataItem]?) {
        guard let metadata = metadata, !metadata.isEmpty else {
            DispatchQueue.main.async { self.trackInfo = nil; self.artwork = nil }
            return
        }

        var title: String?
        var artist: String?
        for item in metadata {
            let stringVal = (item.value(forKey: "stringValue") as? String) ?? (item.value(forKey: "value") as? String)
            if let key = item.commonKey?.rawValue {
                switch key.lowercased() {
                case "title": title = title ?? stringVal
                case "artist": artist = artist ?? stringVal
                default: break
                }
            } else if let v = stringVal {
                if title == nil { title = v }
            }
        }
        let combined: String? = (artist != nil && title != nil) ? "\(artist!) — \(title!)" : (title ?? artist)
        DispatchQueue.main.async { self.trackInfo = combined }

        // Primary artwork source: iTunes Search API — use title (and artist if available)
        if let t = title {
            print("updateMetadata: attempting iTunes artwork fetch for title='\(t)' artist='\(artist ?? "nil")'")
            fetchArtworkFromiTunes(artist: artist, title: t)
        }
    }

    // MARK: - iTunes Search API lookup (primary)
    // Uses iTunes Search API (no API key) to find artwork for a track. If artist provided, term = "artist title" else title only.
    private func fetchArtworkFromiTunes(artist: String?, title: String) {
        print("fetchArtworkFromiTunes: start for title='\(title)' artist='\(artist ?? "nil")'")
        DispatchQueue.global(qos: .utility).async {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "itunes.apple.com"
            components.path = "/search"

            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            var term = trimmedTitle
            if let a = artist?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty {
                term = "\(a) \(trimmedTitle)"
            }
            components.queryItems = [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "entity", value: "song"),
                URLQueryItem(name: "limit", value: "1")
            ]

            guard let url = components.url else {
                print("fetchArtworkFromiTunes: failed to build URL with term='\(term)'")
                return
            }
            print("fetchArtworkFromiTunes: URL -> \(url.absoluteString)")

            let sem = DispatchSemaphore(value: 0)
            var artworkURLString: String? = nil
            var itError: Error? = nil
            var httpStatus: Int? = nil
            var rawJSONPreview: String? = nil

            let task = URLSession.shared.dataTask(with: url) { data, resp, err in
                defer { sem.signal() }
                if let err = err {
                    itError = err
                    print("fetchArtworkFromiTunes: request error: \(err.localizedDescription)")
                    return
                }
                guard let http = resp as? HTTPURLResponse else {
                    print("fetchArtworkFromiTunes: non-HTTP response")
                    return
                }
                httpStatus = http.statusCode
                print("fetchArtworkFromiTunes: response status: \(http.statusCode), data len: \(data?.count ?? 0)")
                guard let data = data else { return }
                if data.count > 0 {
                    let preview = String(data: data.prefix(4096), encoding: .utf8) ?? "<non-utf8>"
                    rawJSONPreview = preview
                }
                do {
                    if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let results = root["results"] as? [[String: Any]],
                       let first = results.first {
                        if let art = first["artworkUrl100"] as? String {
                            artworkURLString = art
                            print("fetchArtworkFromiTunes: found artworkUrl100 = \(art)")
                        } else {
                            print("fetchArtworkFromiTunes: no artworkUrl100 in first result; keys=\(first.keys)")
                        }
                    } else {
                        print("fetchArtworkFromiTunes: unexpected JSON structure or no results")
                    }
                } catch {
                    print("fetchArtworkFromiTunes: JSON parse error: \(error)")
                }
            }
            task.resume()
            _ = sem.wait(timeout: .now() + 6)

            if let err = itError {
                print("fetchArtworkFromiTunes: network error: \(err.localizedDescription)")
                return
            }

            if let status = httpStatus { print("fetchArtworkFromiTunes: HTTP status -> \(status)") }
            if let preview = rawJSONPreview { print("fetchArtworkFromiTunes: JSON preview -> \(preview)") }

            guard var artStr = artworkURLString else {
                let termValue = components.queryItems?.first(where: { $0.name == "term" })?.value ?? term
                print("fetchArtworkFromiTunes: no artwork URL found for term='\(termValue)'")
                return
            }

            if artStr.contains("100x100") {
                let high = artStr.replacingOccurrences(of: "100x100", with: "600x600")
                print("fetchArtworkFromiTunes: upgrading artwork URL from 100x100 to 600x600 -> \(high)")
                artStr = high
            } else if artStr.contains("/100x") {
                let high = artStr.replacingOccurrences(of: "/100x", with: "/600x")
                artStr = high
                print("fetchArtworkFromiTunes: adjusted artwork URL -> \(artStr)")
            }

            guard let artURL = URL(string: artStr) else {
                print("fetchArtworkFromiTunes: invalid artwork URL string: \(artStr)")
                return
            }

            print("fetchArtworkFromiTunes: downloading artwork from \(artURL.absoluteString)")
            let imgSem = DispatchSemaphore(value: 0)
            var gotData: Data? = nil
            var imgError: Error? = nil
            var imgRespStatus: Int? = nil

            let imgTask = URLSession.shared.dataTask(with: artURL) { data, resp, err in
                defer { imgSem.signal() }
                if let err = err {
                    imgError = err
                    print("fetchArtworkFromiTunes: image download err: \(err.localizedDescription)")
                    return
                }
                if let http = resp as? HTTPURLResponse {
                    imgRespStatus = http.statusCode
                    print("fetchArtworkFromiTunes: image response status: \(http.statusCode), data len: \(data?.count ?? 0)")
                }
                gotData = data
            }
            imgTask.resume()
            _ = imgSem.wait(timeout: .now() + 6)

            if let err = imgError {
                print("fetchArtworkFromiTunes: image network error: \(err.localizedDescription)")
                return
            }
            if let s = imgRespStatus { print("fetchArtworkFromiTunes: final image HTTP status = \(s)") }

            if let d = gotData, let ui = UIImage(data: d) {
                print("fetchArtworkFromiTunes: successfully downloaded artwork, size=\(d.count) bytes")
                DispatchQueue.main.async { self.artwork = ui }
            } else {
                print("fetchArtworkFromiTunes: failed to download or decode artwork")
            }
        }
    }
}

// MARK: - AVPlayerItemMetadataOutputPushDelegate
extension RadioPlayer: AVPlayerItemMetadataOutputPushDelegate {
    func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                        didOutputTimedMetadataGroups timedMetadataGroups: [AVTimedMetadataGroup],
                        from playerItemTrack: AVPlayerItemTrack?) {
        let allMetadata = timedMetadataGroups.flatMap { $0.items }
        updateMetadata(from: allMetadata)
    }
}

struct ContentView: View {
    @StateObject private var radio = RadioPlayer()
    @State private var showListenAgain: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Black background that fills the whole screen
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    // Use the cityLogo image from Assets.xcassets (2x asset will be used automatically by iOS when appropriate)
                    Image("cityLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 140)
                        .shadow(radius: 6)

                    Button(action: { radio.toggle() }) {
                        HStack {
                            Image(systemName: radio.isPlaying ? "stop.fill" : "play.fill")
                                .foregroundColor(.black)
                            Text(radio.isPlaying ? "Stop" : "Play")
                                .bold()
                                .foregroundColor(.black)
                        }
                        .frame(minWidth: 140)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .accessibilityLabel(radio.isPlaying ? "Stop radio" : "Play radio")

                    // Track metadata (if any) displayed below the action button
                    Group {
                        if radio.isPlaying {
                            if let track = radio.trackInfo {
                                VStack(spacing: 4) {
                                    Text("Now Playing -")
                                        .font(.title2)
                                        .bold()
                                    Text(track)
                                        .font(.title3)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)

                                    if let art = radio.artwork {
                                        Image(uiImage: art)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: 220, maxHeight: 220)
                                            .cornerRadius(8)
                                            .shadow(radius: 6)
                                            .padding(.top, 8)
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                                .padding(.top, 8)
                            } else {
                                // placeholder spacer to keep layout stable
                                Text(" ")
                                    .font(.subheadline)
                                    .padding(.top, 8)
                            }
                        } else {
                            // keep same space when not playing
                            Text(" ")
                                .font(.subheadline)
                                .padding(.top, 8)
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button(action: { showListenAgain = true }) {
                            Label("Listen Again", systemImage: "clock.arrow.circlepath")
                        }
                        Button(action: { openContactMail() }) {
                            Label("Contact Us", systemImage: "envelope")
                        }
                    } label: {
                        Image(systemName: "line.horizontal.3")
                            .font(.title2)
                            .foregroundColor(.white)
                            .accessibilityLabel("Menu")
                            .padding(.leading, 4)
                    }
                }
            }
            .navigationDestination(isPresented: $showListenAgain) {
                ListenAgainView().environmentObject(radio)
            }
        }
    }

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
}

struct ListenAgainView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var radio: RadioPlayer

    struct Show: Identifiable {
        let id = UUID()
        let title: String
        let url: URL
    }

    private var shows: [Show] = [
        Show(title: "Not The 9 O'Clock Show", url: URL(string: "https://cityliveradiouk.co.uk/Streaming/ListenAgain/NTNOCS.mp3")!),
        Show(title: "Red Bearded Viking Show", url: URL(string: "https://cityliveradiouk.co.uk/Streaming/ListenAgain/RBV.mp3")!),
        Show(title: "The Country Mile", url: URL(string: "https://cityliveradiouk.co.uk/Streaming/ListenAgain/CM.mp3")!),
        Show(title: "Ginger and Nuts", url: URL(string: "https://cityliveradiouk.co.uk/Streaming/ListenAgain/GingerandNuts.mp3")!),
        Show(title: "Weekend Anthems", url: URL(string: "https://cityliveradiouk.co.uk/Streaming/ListenAgain/WeekendAnthems.mp3")!),
        Show(title: "Saturday Club Classics", url: URL(string: "https://cityliveradiouk.co.uk/Streaming/ListenAgain/scc.mp3")!)
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Listen Again")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)

                if let current = radio.currentStreamURL, radio.isPlaying, let playing = shows.first(where: { $0.url == current }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Now playing")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(playing.title)
                                .font(.headline)
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
            }
            .padding([.top, .horizontal], 16)

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(shows) { show in
                        let isPlaying = (radio.currentStreamURL == show.url && radio.isPlaying)
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(width: 64, height: 64)
                                Image(systemName: "music.note.list")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 30, height: 30)
                                    .foregroundColor(.white.opacity(0.9))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(show.title)
                                    .foregroundColor(.white)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(show.url.host ?? "")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Button(action: {
                                withAnimation {
                                    if isPlaying {
                                        radio.stop()
                                    } else {
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
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.03), lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                    } // ForEach(shows)
                } // LazyVStack
                .padding(.vertical, 12)
            } // ScrollView

            // Bottom Back button
            VStack {
                Button(action: {
                    radio.restoreLive()
                    dismiss()
                }) {
                    Text("Back")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(12)
                .padding(16)
            }
            .background(Color.black)
        } // VStack root
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Listen Again")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Pause any live playback when entering the Listen Again screen
            radio.pause()
        }
        .onDisappear {
            // Ensure listen-again playback is stopped and live is restored when leaving
            radio.restoreLive()
        }
    } // body
} // struct ListenAgainView

// Preview for SwiftUI canvas
#Preview {
    ContentView()
}
