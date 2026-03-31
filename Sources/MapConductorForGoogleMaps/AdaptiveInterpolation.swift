import Foundation
import MapConductorCore

enum AdaptiveInterpolation {
    // Target segment length on screen (pixels).
    //
    // Roughly matches the historical "1000m at zoom16 near equator" behavior:
    // zoom16 meters/px ≈ 2.39 → 2.39 * 400 ≈ 956m
    private static let targetSegmentPixels: Double = 400.0

    private static let minSegmentLengthMeters: Double = 50.0
    private static let maxSegmentLengthMeters: Double = 100_000.0

    static func maxSegmentLengthMeters(
        zoom: Float,
        latitude: Double
    ) -> Double {
        let metersPerPixel = calculateMetersPerPixel(latitude: latitude, zoom: Double(zoom))
        return (metersPerPixel * targetSegmentPixels)
            .clamped(to: minSegmentLengthMeters...maxSegmentLengthMeters)
    }

    static func pointsHash(_ points: [any GeoPointProtocol]) -> UInt64 {
        // 64-bit FNV-1a over quantized lat/lng to avoid floating instability.
        var hash: UInt64 = 0xcbf29ce484222325
        for point in points {
            let lat = Int64((point.latitude * 1e6).rounded())
            let lng = Int64((point.longitude * 1e6).rounded())
            hash = (hash ^ UInt64(bitPattern: lat)) &* 0x100000001b3
            hash = (hash ^ UInt64(bitPattern: lng)) &* 0x100000001b3
        }
        hash = (hash ^ UInt64(points.count)) &* 0x100000001b3
        return hash
    }

    static func cacheKey(
        pointsHash: UInt64,
        maxSegmentLengthMeters: Double
    ) -> NSString {
        "\(pointsHash)_\(Int64(maxSegmentLengthMeters.rounded()))" as NSString
    }
}

final class InterpolationCache<Value: AnyObject> {
    private let cache: NSCache<NSString, Value>

    init(countLimit: Int) {
        let cache = NSCache<NSString, Value>()
        cache.countLimit = countLimit
        self.cache = cache
    }

    func get(_ key: NSString) -> Value? {
        cache.object(forKey: key)
    }

    func put(_ key: NSString, _ value: Value) {
        cache.setObject(value, forKey: key)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

