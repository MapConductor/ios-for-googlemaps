import XCTest
@testable import MapConductorForGoogleMaps

final class GoogleTileCacheBudgetTests: XCTestCase {
    func testCancelledRequestsRecoverOncePerCameraMovement() {
        var recovery = GoogleTileRecovery()
        recovery.cancelled()
        XCTAssertTrue(recovery.needsRefresh)
        recovery.refreshed()
        XCTAssertFalse(recovery.canRefresh, "A freshly populated viewport must not refresh repeatedly")
        recovery.cancelled()
        XCTAssertFalse(recovery.needsRefresh, "Fallback cancellation during refresh must not loop")
        recovery.cameraMoved()
        XCTAssertTrue(recovery.canRefresh, "Panning must re-enable cache eviction")
        recovery.cancelled()
        XCTAssertTrue(recovery.needsRefresh)
        recovery.refreshed()
        recovery.memoryWarning()
        XCTAssertTrue(recovery.needsRefresh, "Memory pressure must refresh even without a gesture")
    }

    func testDecodedBudgetCountsUniqueTilesAndResetsAfterTrim() {
        var budget = GoogleTileCacheBudget(byteLimit: 10, countLimit: 10)
        budget.record(key: "a", cost: 6)
        budget.record(key: "a", cost: 6)
        XCTAssertFalse(budget.shouldTrim)
        XCTAssertEqual(budget.bytes, 6)
        budget.record(key: "b", cost: 6)
        XCTAssertTrue(budget.shouldTrim)
        budget.reset()
        XCTAssertEqual(budget.bytes, 0)
        XCTAssertFalse(budget.shouldTrim)
    }

    func testCountAndLifetimeBounds() {
        var now: TimeInterval = 0
        var budget = GoogleTileCacheBudget(byteLimit: 100, countLimit: 2, ttl: 60, clock: { now })
        XCTAssertFalse(budget.shouldTrim)
        budget.record(key: "a", cost: 1)
        now = 61
        XCTAssertTrue(budget.shouldTrim)
        budget.reset()
        budget.record(key: "b", cost: 1)
        budget.record(key: "c", cost: 1)
        budget.record(key: "d", cost: 1)
        XCTAssertTrue(budget.shouldTrim)
    }

    func testLargeDisplayFitsVisibleTilesWithoutRefreshLoop() {
        var budget = GoogleTileCacheBudget(byteLimit: 10)
        budget.minimumByteLimit = 30
        for index in 0..<3 { budget.record(key: "\(index)", cost: 10) }
        XCTAssertFalse(budget.shouldTrim)
        budget.record(key: "offscreen", cost: 10)
        XCTAssertTrue(budget.shouldTrim)
        // Subsequent continuous panning must not grow accounting indefinitely.
        for index in 0..<1000 { budget.record(key: "extra-\(index)", cost: 10) }
        XCTAssertEqual(budget.bytes, 40)
    }
}
