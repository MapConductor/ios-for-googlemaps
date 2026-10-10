import GoogleMaps
import MapConductorCore
import UIKit
import XCTest
@testable import MapConductorForGoogleMaps

final class GoogleLocalTileLayerTests: XCTestCase {
    @MainActor
    func testBackgroundRequestOutsideCoverageRepliesOnMain() async throws {
        let server = LocalTileServer.startServer()
        defer { server.stop() }
        let source = try XCTUnwrap(GoogleRasterTileURLSource(.urlTemplate(
            template: server.urlTemplate(routeId: "test", tileSize: 256),
            minZoom: 4, maxZoom: 12)))
        // Call through the Objective-C base type, as the SDK does. A Swift
        // MainActor annotation does not move an Objective-C call to main.
        let layer: GMSTileLayer = GoogleLocalTileLayer(
            source: source, server: server, logicalTileSize: 256)
        let answered = expectation(description: "out-of-coverage request answered")
        let receiver = Receiver(x: 0, y: 0, zoom: 3, answered: answered) { image in
            XCTAssertTrue(image === kGMSTileLayerNoTile)
        }
        DispatchQueue.global().async {
            layer.requestTileFor(x: 0, y: 0, zoom: 3, receiver: receiver)
        }
        await fulfillment(of: [answered], timeout: 2)
    }

    @MainActor
    func testConcurrentSDKRequestsDuringCameraChangesAndInvalidation() async throws {
        let server = LocalTileServer.startServer()
        defer { server.stop() }
        let png = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).pngData { _ in }
        server.register(routeId: "test", provider: Provider(png: png))
        let source = try XCTUnwrap(GoogleRasterTileURLSource(.urlTemplate(
            template: server.urlTemplate(routeId: "test", tileSize: 256))))
        let localLayer = GoogleLocalTileLayer(
            source: source, server: server, logicalTileSize: 256)
        let layer: GMSTileLayer = localLayer
        let answered = expectation(description: "every concurrent request answered once")
        answered.expectedFulfillmentCount = 200
        localLayer.cameraChanged(zoom: 12)

        for request in 0..<200 {
            let x = UInt(request % 16), y = UInt(request / 16)
            let zoom = UInt(8 + request % 5)
            let receiver = Receiver(x: x, y: y, zoom: zoom, answered: answered)
            DispatchQueue.global().async {
                layer.requestTileFor(x: x, y: y, zoom: zoom, receiver: receiver)
            }
            if request % 10 == 0 {
                DispatchQueue.main.async {
                    localLayer.cameraChanged(zoom: Double(zoom))
                    if request % 20 == 0 { localLayer.cancelRequests() }
                }
            }
        }
        await fulfillment(of: [answered], timeout: 5)
    }

    private final class Receiver: NSObject, GMSTileReceiver {
        let x: UInt, y: UInt, zoom: UInt
        let answered: XCTestExpectation
        let checkImage: (UIImage?) -> Void

        init(x: UInt, y: UInt, zoom: UInt, answered: XCTestExpectation,
             checkImage: @escaping (UIImage?) -> Void = { _ in }) {
            self.x = x; self.y = y; self.zoom = zoom
            self.answered = answered; self.checkImage = checkImage
        }

        func receiveTileWith(x: UInt, y: UInt, zoom: UInt, image: UIImage?) {
            XCTAssertTrue(Thread.isMainThread, "SDK callbacks must enter the queue on main")
            XCTAssertEqual(x, self.x); XCTAssertEqual(y, self.y); XCTAssertEqual(zoom, self.zoom)
            checkImage(image)
            answered.fulfill()
        }
    }

    private final class Provider: TileProvider {
        let png: Data
        init(png: Data) { self.png = png }
        func renderTile(request: TileRequest) -> Data? {
            Thread.sleep(forTimeInterval: 0.002)
            return png
        }
    }
}
