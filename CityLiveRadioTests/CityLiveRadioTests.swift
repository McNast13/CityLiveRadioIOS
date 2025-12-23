//
//  CityLiveRadioTests.swift
//  CityLiveRadioTests
//
//  Created by paul mackay on 19/12/2025.
//

import Testing
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
            XCTAssertTrue(mock.didPlay, "Underlying player should receive play()")
            XCTAssertTrue(radio.isPlaying, "RadioPlayer should update isPlaying after play()")
            playExpectation.fulfill()
        }
        wait(for: [playExpectation], timeout: 1.0)

        let pauseExpectation = expectation(description: "pause called and isPlaying cleared")
        radio.pause()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertTrue(mock.didPause, "Underlying player should receive pause()")
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
}

private class MockPlayer: PlayerProtocol {
    var didPlay = false
    var didPause = false
    func play() { didPlay = true }
    func pause() { didPause = true }
}
