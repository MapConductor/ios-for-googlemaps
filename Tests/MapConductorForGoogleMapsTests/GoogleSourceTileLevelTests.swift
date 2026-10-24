import XCTest
@testable import MapConductorForGoogleMaps

final class GoogleSourceTileLevelTests: XCTestCase {
    func testRoundedRasterGridUsesTheLowerVectorSourceLevel() {
        for zoom in [7.0, 7.2, 7.49, 7.5, 7.8, 7.95, 7.99, 8.0, 12.0] {
            let grid = UInt(zoom.rounded())
            let offset = GoogleLocalTileLayer.sourceZoomOffset(
                requestedZoom: grid, cameraZoom: zoom, logicalTileSize: 256)
            XCTAssertEqual(Double(grid) - 1 - Double(offset), floor(zoom - 1))
        }
    }

    func testFallbackTilesAreNotMadeCoarser() {
        XCTAssertEqual(GoogleLocalTileLayer.sourceZoomOffset(
            requestedZoom: 6, cameraZoom: 7.8, logicalTileSize: 256), 0)
    }
}
