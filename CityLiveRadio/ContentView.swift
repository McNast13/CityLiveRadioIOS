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

public protocol PlayerProtocol {
    func play()
    func pause()
}

final class RadioPlayer: NSObject, ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var trackInfo: String? = nil
    @Published var currentStreamURL: URL? = nil
    // id (url.absoluteString) of the show that's currently playing (if any)
    @Published var playingShowID: String? = nil
    @Published var artwork: UIImage? = nil

    private var player: AVPlayer?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var testPlayer: PlayerProtocol? = nil
    private let liveStreamURL = URL(string: "https://streaming.live365.com/a91939")!

    convenience init(player: PlayerProtocol) {
        self.init()
        self.testPlayer = player
    }

    override init() {
        super.init()
        preparePlayer(with: liveStreamURL, autoPlay: false)
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioSessionInterruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWillEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        #endif
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func preparePlayer(with url: URL, autoPlay: Bool) {
        print("preparePlayer: url=\(url.absoluteString) autoPlay=\(autoPlay)")
        if let currentItem = player?.currentItem, let output = metadataOutput {
            currentItem.remove(output)
        }
        DispatchQueue.main.async { self.artwork = nil }
        let item = AVPlayerItem(url: url)
        metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput?.setDelegate(self, queue: DispatchQueue.main)
        if let output = metadataOutput { item.add(output) }
        player = AVPlayer(playerItem: item)
        player?.automaticallyWaitsToMinimizeStalling = false
        currentStreamURL = url
        print("preparePlayer: set currentStreamURL=\(currentStreamURL?.absoluteString ?? "nil")")

        if autoPlay {
            #if os(iOS)
            do { try AVAudioSession.sharedInstance().setActive(true) } catch { print("Failed to activate audio session before play: \(error)") }
            #endif
            player?.play()
            DispatchQueue.main.async {
                self.playingShowID = url.absoluteString
                self.isPlaying = true
            }
            print("preparePlayer: started playback, isPlaying set true, playingShowID=\(url.absoluteString)")
        }
    }

    func play() {
        if let test = testPlayer {
            test.play()
            DispatchQueue.main.async { self.isPlaying = true }
            return
        }
        #if os(iOS)
        do { try AVAudioSession.sharedInstance().setActive(true) } catch { print("play(): could not activate audio session: \(error)") }
        #endif
        if player == nil { preparePlayer(with: liveStreamURL, autoPlay: true); return }
        player?.play()
        DispatchQueue.main.async { self.isPlaying = true }
    }

    func pause() {
        if let test = testPlayer { test.pause(); DispatchQueue.main.async { self.isPlaying = false }; return }
        player?.pause()
        DispatchQueue.main.async { self.isPlaying = false }
    }

    func stop() {
        print("RadioPlayer.stop() called")
        if testPlayer != nil {
            DispatchQueue.main.async {
                self.isPlaying = false
                self.currentStreamURL = nil
                self.trackInfo = nil
                self.artwork = nil
                self.playingShowID = nil
            }
            return
        }
        player?.pause(); player = nil
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentStreamURL = nil
            self.trackInfo = nil
            self.artwork = nil
            self.playingShowID = nil
        }
        print("RadioPlayer.stop(): player paused and cleared; isPlaying will be false; currentStreamURL cleared")
    }

    func restoreLive() {
        if currentStreamURL == liveStreamURL { pause(); return }
        stop(); preparePlayer(with: liveStreamURL, autoPlay: false)
    }

    func toggle() { if isPlaying { pause() } else { play() } }

    func playStream(url: URL) {
        print("playStream: requested url=\(url.absoluteString)")
        // If tests inject testPlayer, make playStream simulate starting playback
        if testPlayer != nil {
            DispatchQueue.main.async {
                self.currentStreamURL = url
                self.playingShowID = url.absoluteString
                self.isPlaying = true
            }
            // call underlying test player's play to simulate
            testPlayer?.play()
            print("playStream: testPlayer mode - set currentStreamURL & isPlaying")
            return
        }
        stop()
        preparePlayer(with: url, autoPlay: true)
        print("playStream: finished prepare for url=\(url.absoluteString)")
    }

    func updateMetadata(from metadata: [AVMetadataItem]?) {
        guard let metadata = metadata, !metadata.isEmpty else { DispatchQueue.main.async { self.trackInfo = nil; self.artwork = nil }; return }
        var title: String?; var artist: String?
        for item in metadata {
            let stringVal = (item.value(forKey: "stringValue") as? String) ?? (item.value(forKey: "value") as? String)
            if let key = item.commonKey?.rawValue {
                switch key.lowercased() {
                case "title": title = title ?? stringVal
                case "artist": artist = artist ?? stringVal
                default: break
                }
            } else if let v = stringVal { if title == nil { title = v } }
        }
        let combined: String? = (artist != nil && title != nil) ? "\(artist!) — \(title!)" : (title ?? artist)
        DispatchQueue.main.async { self.trackInfo = combined }
        if let t = title {
            print("updateMetadata: attempting iTunes artwork fetch for title='\(t)' artist='\(artist ?? "nil")'")
            fetchArtworkFromiTunes(artist: artist, title: t)
        }
    }

    // MARK: - Audio session & interruption handling
    @objc private func handleAudioSessionInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // Interruption began — pause playback (e.g., incoming phone call)
            print("handleAudioSessionInterruption: began")
            pause()
        case .ended:
            // Interruption ended — if should resume, resume playback
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
            print("handleAudioSessionInterruption: ended, options=\(options)")
            if options.contains(.shouldResume) {
                // small delay to allow system to settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if self.currentStreamURL != nil {
                        self.play()
                    }
                }
            }
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        print("handleRouteChange: reason=\(reason)")
        if reason == .oldDeviceUnavailable {
            // e.g., headphones unplugged — pause the audio
            pause()
        }
    }

    @objc private func handleDidEnterBackground(_ note: Notification) {
        // Ensure audio session remains active in background. With Background Modes (audio) enabled this keeps playback running.
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            print("handleDidEnterBackground: audio session kept active")
        } catch {
            print("handleDidEnterBackground: failed to keep audio session active: \(error)")
        }
        #endif
    }

    @objc private func handleWillEnterForeground(_ note: Notification) {
        // Nothing special required, but log for diagnostics
        print("handleWillEnterForeground: called")
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
                DispatchQueue.main.async { self.artwork = UIImage(named: "PHLogo") }
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
                print("fetchArtworkFromiTunes: network error: \(err.localizedDescription) - using PHLogo placeholder")
                DispatchQueue.main.async { self.artwork = UIImage(named: "PHLogo") }
                return
            }

            if let status = httpStatus { print("fetchArtworkFromiTunes: HTTP status -> \(status)") }
            if let preview = rawJSONPreview { print("fetchArtworkFromiTunes: JSON preview -> \(preview)") }

            guard var artStr = artworkURLString else {
                let termValue = components.queryItems?.first(where: { $0.name == "term" })?.value ?? term
                print("fetchArtworkFromiTunes: no artwork URL found for term='\(termValue)' - using PHLogo placeholder")
                DispatchQueue.main.async { self.artwork = UIImage(named: "PHLogo") }
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
                print("fetchArtworkFromiTunes: invalid artwork URL string: \(artStr) - using PHLogo placeholder")
                DispatchQueue.main.async { self.artwork = UIImage(named: "PHLogo") }
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
                print("fetchArtworkFromiTunes: image network error: \(err.localizedDescription) - falling back to PHLogo")
                DispatchQueue.main.async { self.artwork = UIImage(named: "PHLogo") }
                return
            }
            if let s = imgRespStatus { print("fetchArtworkFromiTunes: final image HTTP status = \(s)") }

            if let d = gotData, let ui = UIImage(data: d) {
                print("fetchArtworkFromiTunes: successfully downloaded artwork, size=\(d.count) bytes")
                DispatchQueue.main.async { self.artwork = ui }
            } else {
                print("fetchArtworkFromiTunes: failed to download or decode artwork - using PHLogo placeholder")
                DispatchQueue.main.async { self.artwork = UIImage(named: "PHLogo") }
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
                                // Determine if this show is playing by comparing the RadioPlayer.playingShowID
                                let isPlaying = (radio.playingShowID == show.id && radio.isPlaying)

                                HStack(spacing: 12) {
                                    Image(show.imageName)
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
                                            print("ListenAgain button tapped for show=\(show.title), isPlaying=\(isPlaying), selectedShowID=\(String(describing: selectedShowID))")
                                            if isPlaying {
                                                // stop current show and clear selection
                                                radio.stop()
                                                selectedShowID = nil
                                            } else {
                                                // select and play this show
                                                selectedShowID = show.id
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
                            } // ForEach
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

                    if let sel = selectedShowID, let show = shows.first(where: { $0.id == sel }), radio.playingShowID == show.id && radio.isPlaying {
                        if let art = radio.artwork {
                            Image(uiImage: art)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(12)
                                .shadow(radius: 8)
                                .padding(20)
                        } else {
                            Image(show.imageName)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(12)
                                .shadow(radius: 8)
                                .padding(20)
                        }
                    } else {
                        Image("PHLogo")
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)
                            .shadow(radius: 4)
                            .padding(24)
                    }
                }
                .frame(height: geo.size.height * 0.4)
            } // VStack root
            .background(Color.black.ignoresSafeArea())
            .onAppear {
                // Pause live playback when showing Listen Again
                radio.pause()
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
        }
    }
}

// Preview for SwiftUI canvas
#Preview {
    ContentView()
}
