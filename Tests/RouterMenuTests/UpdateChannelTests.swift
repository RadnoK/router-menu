import XCTest
@testable import RouterMenu

final class UpdateChannelTests: XCTestCase {
    func testStableAllowsNoExtraChannels() {
        XCTAssertTrue(UpdateChannel.stable.allowedChannels.isEmpty)
    }

    /// Beta is additive: Sparkle always offers channel-less (stable) items, so
    /// allowing "beta" adds pre-releases rather than replacing stable ones.
    func testBetaAllowsTheBetaChannel() {
        XCTAssertEqual(UpdateChannel.beta.allowedChannels, ["beta"])
    }

    func testPrereleaseIsDetectedByHyphenSuffix() {
        XCTAssertTrue(UpdateChannel.isPrerelease(version: "0.7.0-beta.1"))
        XCTAssertTrue(UpdateChannel.isPrerelease(version: "1.0.0-rc.2"))
    }

    func testPlainVersionIsNotAPrerelease() {
        XCTAssertFalse(UpdateChannel.isPrerelease(version: "0.7.0"))
        XCTAssertFalse(UpdateChannel.isPrerelease(version: "1.2.3"))
    }

    func testRoundTripsThroughCodable() throws {
        for channel in UpdateChannel.allCases {
            let data = try JSONEncoder().encode(channel)
            XCTAssertEqual(try JSONDecoder().decode(UpdateChannel.self, from: data), channel)
        }
    }
}
