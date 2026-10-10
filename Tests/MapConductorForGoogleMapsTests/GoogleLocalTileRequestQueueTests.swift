import XCTest
@testable import MapConductorForGoogleMaps

final class GoogleLocalTileRequestQueueTests: XCTestCase {
    @MainActor
    func testZoomCancelsOldWorkAndStartsCurrentTilesWithoutWaitingForIt() async throws {
        let started = expectation(description: "old renders started")
        started.expectedFulfillmentCount = 2
        let obsolete = expectation(description: "all old requests answered retryable")
        obsolete.expectedFulfillmentCount = 3
        let current = expectation(description: "current tile delivered")
        let queue = GoogleLocalTileRequestQueue(width: 2) { url, cancelled in
            if url.lastPathComponent == "old" {
                started.fulfill()
                let deadline = Date().addingTimeInterval(5)
                while !cancelled(), Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
                XCTAssertTrue(cancelled())
                return Data([1]) // A late result must not reach the receiver.
            }
            return Data([2])
        }
        queue.updateZoom(12)
        for _ in 0..<3 {
            queue.enqueue(url: URL(string: "http://example.test/old")!, zoom: 12) {
                XCTAssertNil($0)
                obsolete.fulfill()
            }
        }
        await fulfillment(of: [started], timeout: 1)
        queue.updateZoom(8)
        queue.enqueue(url: URL(string: "http://example.test/current")!, zoom: 8) {
            XCTAssertEqual($0, Data([2]))
            current.fulfill()
        }
        await fulfillment(of: [obsolete, current], timeout: 1)

        // Going back to the same zoom must fetch again, without retaining a
        // transparent/no-tile answer from the cancelled requests.
        let revisited = expectation(description: "old zoom revisited")
        queue.updateZoom(12)
        queue.enqueue(url: URL(string: "http://example.test/revisited")!, zoom: 12) {
            XCTAssertEqual($0, Data([2]))
            revisited.fulfill()
        }
        await fulfillment(of: [revisited], timeout: 1)
    }

    @MainActor
    func testStyleInvalidationCancelsPendingAndActiveTiles() async {
        let started = expectation(description: "render started")
        let cancelled = expectation(description: "old style requests cancelled")
        cancelled.expectedFulfillmentCount = 2
        let queue = GoogleLocalTileRequestQueue(width: 1) { _, isCancelled in
            started.fulfill()
            let deadline = Date().addingTimeInterval(5)
            while !isCancelled(), Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            return Data([1])
        }
        for _ in 0..<2 {
            queue.enqueue(url: URL(string: "http://example.test/old-style")!, zoom: 12) {
                XCTAssertNil($0)
                cancelled.fulfill()
            }
        }
        await fulfillment(of: [started], timeout: 1)
        queue.cancelAll()
        await fulfillment(of: [cancelled], timeout: 1)
    }

    @MainActor
    func testCurrentZoomPreemptsASlowAdjacentFallback() async {
        let started = expectation(description: "adjacent fallback started")
        let cancelled = expectation(description: "fallback cancelled")
        let current = expectation(description: "current level delivered")
        let queue = GoogleLocalTileRequestQueue(width: 1) { url, isCancelled in
            if url.lastPathComponent == "fallback" {
                started.fulfill()
                let deadline = Date().addingTimeInterval(5)
                while !isCancelled(), Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
                return Data([1])
            }
            return Data([2])
        }
        queue.updateZoom(12)
        queue.enqueue(url: URL(string: "http://example.test/fallback")!, zoom: 12) {
            XCTAssertNil($0)
            cancelled.fulfill()
        }
        await fulfillment(of: [started], timeout: 1)
        queue.updateZoom(13)
        queue.enqueue(url: URL(string: "http://example.test/current")!, zoom: 13) {
            XCTAssertEqual($0, Data([2]))
            current.fulfill()
        }
        await fulfillment(of: [cancelled, current], timeout: 1)
    }

    @MainActor
    func testAdjacentZoomAndFallbackRequestsAreStillRendered() async {
        let finished = expectation(description: "all requested levels delivered")
        finished.expectedFulfillmentCount = 3
        let queue = GoogleLocalTileRequestQueue { _, _ in Data([3]) }
        queue.updateZoom(12)
        for level: UInt in [11, 12, 8] {
            queue.enqueue(url: URL(string: "http://example.test/\(level)")!, zoom: level) {
                XCTAssertEqual($0, Data([3]))
                finished.fulfill()
            }
        }
        await fulfillment(of: [finished], timeout: 1)
    }
}
