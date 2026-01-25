//
//  CityLiveRadioTests.swift
//  CityLiveRadioTests
//
//  Created by paul mackay on 19/12/2025.
//

import XCTest
import AVFoundation
@testable import CityLiveRadio

final class CityLiveRadioTests: XCTestCase {

    func testPlayPauseToggle() {
        let mock = MockPlayer()
        let radio = RadioPlayer(player: mock)

        let playExpectation = expectation(description: "play called and isPlaying set")
        radio.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertTrue(mock.playCalled, "Underlying player should receive play()")
            XCTAssertTrue(radio.isPlaying, "RadioPlayer should update isPlaying after play()")
            playExpectation.fulfill()
        }
        wait(for: [playExpectation], timeout: 1.0)

        let pauseExpectation = expectation(description: "pause called and isPlaying cleared")
        radio.pause()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertTrue(mock.pauseCalled, "Underlying player should receive pause()")
            XCTAssertFalse(radio.isPlaying, "RadioPlayer should update isPlaying after pause()")
            pauseExpectation.fulfill()
        }
        wait(for: [pauseExpectation], timeout: 1.0)
    }

    func testUpdateMetadataCombinesArtistTitle() {
        let radio = RadioPlayer(player: MockPlayer())

        let titleItem = AVMutableMetadataItem()
        titleItem.keySpace = .common
        titleItem.key = AVMetadataKey.commonKeyTitle as (NSCopying & NSObjectProtocol)
        titleItem.value = "Song Title" as (NSCopying & NSObjectProtocol)

        let artistItem = AVMutableMetadataItem()
        artistItem.keySpace = .common
        artistItem.key = AVMetadataKey.commonKeyArtist as (NSCopying & NSObjectProtocol)
        artistItem.value = "Artist Name" as (NSCopying & NSObjectProtocol)

        radio.updateMetadata(from: [titleItem, artistItem])

        let expect = expectation(description: "metadata combined")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertEqual(radio.trackInfo, "Artist Name — Song Title")
            expect.fulfill()
        }
        wait(for: [expect], timeout: 1.0)
    }

    func testPlayStreamSetsCurrentStream() {
        let mock = MockPlayer()
        let radio = RadioPlayer(player: mock)

        let url = URL(string: "https://cityliveradiouk.co.uk/Streaming/ListenAgain/NTNOCS.mp3")!
        let playExpectation = expectation(description: "playStream sets currentStreamURL and isPlaying")

        radio.playStream(url: url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(radio.currentStreamURL?.absoluteString, url.absoluteString)
            XCTAssertTrue(radio.isPlaying, "RadioPlayer should be playing after playStream")
            playExpectation.fulfill()
        }
        wait(for: [playExpectation], timeout: 2.0)
    }

    func testStopClearsState() {
        let mock = MockPlayer()
        let radio = RadioPlayer(player: mock)

        let url = URL(string: "https://cityliveradiouk.co.uk/Streaming/ListenAgain/RBV.mp3")!
        let stopExpectation = expectation(description: "stop clears currentStreamURL and isPlaying")

        radio.playStream(url: url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            // Now stop
            radio.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                XCTAssertFalse(radio.isPlaying, "RadioPlayer should not be playing after stop")
                XCTAssertNil(radio.currentStreamURL, "currentStreamURL should be cleared after stop")
                stopExpectation.fulfill()
            }
        }
        wait(for: [stopExpectation], timeout: 3.0)
    }
}
