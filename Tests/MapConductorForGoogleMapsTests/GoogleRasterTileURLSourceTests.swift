import MapConductorCore
import XCTest
@testable import MapConductorForGoogleMaps

final class GoogleRasterTileURLSourceTests: XCTestCase {
    func testAnExistingConstructorReadsUpdatedURLsAndCoverage() throws {
        let source = try XCTUnwrap(GoogleRasterTileURLSource(.urlTemplate(
            template: "https://example.com/g0/{z}/{x}/{y}.png", tileSize: 256)))
        XCTAssertEqual(source.url(x: 3, y: 5, zoom: 4)?.absoluteString,
                       "https://example.com/g0/4/3/5.png")
        XCTAssertTrue(source.update(.urlTemplate(
            template: "https://example.com/g1/{z}/{x}/{y}.png", tileSize: 256,
            minZoom: 4, maxZoom: 6, scheme: .TMS)))
        XCTAssertEqual(source.url(x: 3, y: 5, zoom: 4)?.absoluteString,
                       "https://example.com/g1/4/3/10.png")
        XCTAssertNil(source.url(x: 0, y: 0, zoom: 3))
        XCTAssertNil(source.url(x: 0, y: 0, zoom: 7))
    }

    func testChangingTileGridRequiresReplacementAndKeepsPreviousConfiguration() throws {
        let source = try XCTUnwrap(GoogleRasterTileURLSource(.urlTemplate(
            template: "https://example.com/old/{z}/{x}/{y}.png", tileSize: 256)))
        XCTAssertFalse(source.update(.urlTemplate(
            template: "https://example.com/new/{z}/{x}/{y}.png", tileSize: 512)))
        XCTAssertFalse(source.update(.tileJson(url: "https://example.com/tiles.json")))
        XCTAssertEqual(source.url(x: 0, y: 0, zoom: 0)?.absoluteString,
                       "https://example.com/old/0/0/0.png")
    }
}
