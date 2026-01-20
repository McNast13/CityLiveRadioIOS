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

    var body: some View {
        NavigationStack {
            ZStack {
                // Black background that fills the whole screen
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    // Use the cityLogo image from Assets.xcassets
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
                    // Make the button prominent and use a white tint so it shows on black background
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .accessibilityLabel(radio.isPlaying ? "Stop radio" : "Play radio")

                    // Track metadata (if any) displayed below the action button
                    if radio.isPlaying {
                        if let track = radio.trackInfo {
                            // Show the header on its own line (larger) and the track on the next line (smaller)
                            VStack(spacing: 4) {
                                Text("Now Playing -")
                                    .font(.title2)
                                    .bold()
                                Text(track)
                                    .font(.title3)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)

                                // artwork (if available)
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
                            // Show placeholder while playing but metadata hasn't arrived yet
                            Text(" ")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.0))
                                .padding(.top, 8)
                        }
                    } else {
                        // Keep the empty space so layout doesn't jump when metadata appears
                        Text(" ")
                            .font(.subheadline)
                            .padding(.top, 8)
                    }

                    // Listen Again image placed under the track metadata – tappable to navigate
                    NavigationLink(destination: ListenAgainView().environmentObject(radio)) {
                        Image("listenAgain")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 250, height: 120)
                            .shadow(radius: 6)
                            .padding(.top, 12)
                            .accessibilityLabel("Listen again")
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding()
            }
        }
    }
}

// Simple ListenAgain screen with a back button
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
        VStack(spacing: 12) {
            Text("Listen Again")
                .font(.title)
                .bold()
                .foregroundColor(.white)
                .padding(.top, 16)

            List {
                ForEach(shows) { show in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(show.title)
                                .foregroundColor(.white)
                            if radio.currentStreamURL == show.url && radio.isPlaying {
                                Text("Playing")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        Spacer()
                        Button(action: {
                            // If this show is already playing, stop it; otherwise play it (stopping current first)
                            if radio.currentStreamURL == show.url && radio.isPlaying {
                                radio.stop()
                            } else {
                                // Ensure any live playback is stopped and play the selected show
                                radio.playStream(url: show.url)
                            }
                        }) {
                            Image(systemName: (radio.currentStreamURL == show.url && radio.isPlaying) ? "stop.fill" : "play.fill")
                                .foregroundColor(.white)
                                .imageScale(.large)
                                .padding(8)
                                .background(Color.gray.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(Color.black)
                }
            }
            .listStyle(.plain)
            .background(Color.black)

            Spacer()

            Button(action: {
                // Restore live stream when leaving so Play resumes live stream
                radio.restoreLive()
                dismiss()
            }) {
                Text("Back")
                    .bold()
                    .frame(minWidth: 140)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .foregroundColor(.black)
            .tint(.white)
            .padding(.bottom, 24)
        }
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
    }
}

#Preview {
    ContentView()
}
