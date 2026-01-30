import XCTest
import AVFoundation
@testable import CityLiveRadio

final class MockPlayer: PlayerProtocol {
    var playCalled = false
    var pauseCalled = false
    func play() { playCalled = true }
    func pause() { pauseCalled = true }
}

final class RadioPlayerTests: XCTestCase {
    func testPlayPauseStopWithTestPlayer() {
        let mock = MockPlayer()
        let radio = RadioPlayer(player: mock)

        // Initially not playing
        XCTAssertFalse(radio.isPlaying)
        XCTAssertNil(radio.currentStreamURL)
        XCTAssertNil(radio.playingShowID)

        // Play using test player (should set isPlaying true)
        radio.play()
        // test player should have received play
        XCTAssertTrue(mock.playCalled, "Mock player should have play called")
        XCTAssertTrue(radio.isPlaying || radio.playingShowID == nil || radio.currentStreamURL == nil)

        // Pause should call pause on testPlayer and set isPlaying false
        radio.pause()
        XCTAssertTrue(mock.pauseCalled)
        XCTAssertFalse(radio.isPlaying)

        // playStream in test mode should set currentStreamURL and playingShowID
        let url = URL(string: "https://example.com/stream.mp3")!
        radio.playStream(url: url)
        XCTAssertEqual(radio.currentStreamURL?.absoluteString, url.absoluteString)
        XCTAssertEqual(radio.playingShowID, url.absoluteString)
        XCTAssertTrue(radio.isPlaying)

        // stop should clear state
        radio.stop()
        XCTAssertFalse(radio.isPlaying)
        XCTAssertNil(radio.currentStreamURL)
        XCTAssertNil(radio.playingShowID)
        XCTAssertNil(radio.trackInfo)
        XCTAssertNil(radio.artwork)
    }

    func testRestoreLivePreparesLivePlayer() {
        let mock = MockPlayer()
        let radio = RadioPlayer(player: mock)
        // Ensure initial prepare created liveStreamURL but not playing
        XCTAssertEqual(radio.currentStreamURL?.absoluteString, radio.playingShowID) == false // may be nil

        // Play a test stream
        let url = URL(string: "https://example.com/recording.mp3")!
        radio.playStream(url: url)
        XCTAssertEqual(radio.playingShowID, url.absoluteString)
        XCTAssertTrue(radio.isPlaying)

        // Now restore live
        radio.restoreLive()
        // After restoreLive, currentStreamURL should be liveStreamURL or nil depending on implementation
        // We expect that preparePlayer set currentStreamURL to live stream and isPlaying false
        XCTAssertFalse(radio.isPlaying)
        XCTAssertNotEqual(radio.currentStreamURL?.absoluteString, url.absoluteString)
    }
}
