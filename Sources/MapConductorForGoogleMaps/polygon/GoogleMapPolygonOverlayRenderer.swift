import GoogleMaps
import MapConductorCore
import UIKit

@MainActor
final class GoogleMapPolygonOverlayRenderer: AbstractPolygonOverlayRenderer<GMSPolygon> {
    private weak var mapView: GMSMapView?
    private let interpolationCache = InterpolationCache<GMSPath>(countLimit: 64)

    init(mapView: GMSMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createPolygon(state: PolygonState) async -> GMSPolygon? {
        guard let mapView else { return nil }
        let resolved = resolveHoles(state)
        let path = ringPath(for: resolved.points, geodesic: resolved.geodesic, mapView: mapView)

        let polygon = GMSPolygon(path: path)
        polygon.strokeColor = resolved.strokeColor
        polygon.strokeWidth = CGFloat(resolved.strokeWidth)
        polygon.fillColor = resolved.fillColor
        polygon.geodesic = resolved.geodesic
        polygon.zIndex = Int32(truncatingIfNeeded: resolved.zIndex)
        polygon.holes = resolved.holes.map { holePoints in
            ringPath(for: holePoints, geodesic: resolved.geodesic, mapView: mapView)
        }
        polygon.map = mapView
        polygon.userData = state.id
        return polygon
    }

    override func updatePolygonProperties(
        polygon: GMSPolygon,
        current: PolygonEntity<GMSPolygon>,
        prev: PolygonEntity<GMSPolygon>
    ) async -> GMSPolygon? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        if finger.points != prevFinger.points || finger.geodesic != prevFinger.geodesic || finger.holes != prevFinger.holes {
            guard let mapView else { return polygon }
            let resolved = resolveHoles(current.state)
            polygon.path = ringPath(for: resolved.points, geodesic: resolved.geodesic, mapView: mapView)
            polygon.geodesic = resolved.geodesic
            polygon.holes = resolved.holes.map { holePoints in
                ringPath(for: holePoints, geodesic: resolved.geodesic, mapView: mapView)
            }
        }

        if finger.strokeWidth != prevFinger.strokeWidth {
            polygon.strokeWidth = CGFloat(current.state.strokeWidth)
        }

        if finger.strokeColor != prevFinger.strokeColor {
            polygon.strokeColor = current.state.strokeColor
        }

        if finger.fillColor != prevFinger.fillColor {
            polygon.fillColor = current.state.fillColor
        }

        if finger.zIndex != prevFinger.zIndex {
            polygon.zIndex = Int32(truncatingIfNeeded: current.state.zIndex)
        }

        return polygon
    }

    override func removePolygon(entity: PolygonEntity<GMSPolygon>) async {
        entity.polygon?.map = nil
    }

    /// 複数の穴が重なっている場合は結合（union）して重複を解消する
    /// （android-for-googlemaps と同一仕様）。
    private func resolveHoles(_ state: PolygonState) -> PolygonState {
        state.holes.count > 1 ? state.unionHoles() : state
    }

    /// リングをコア共通の補間（geodesic は球面補間・非 geodesic は線形補間）で密度化し、
    /// 正規化・閉環して `GMSPath` へ変換する。geodesic はカメラズームに応じた
    /// 適応セグメント長で補間し、結果をキャッシュする（android-for-googlemaps と同一仕様）。
    private func ringPath(
        for points: [GeoPointProtocol],
        geodesic: Bool,
        mapView: GMSMapView
    ) -> GMSPath {
        if !geodesic {
            return makePath(createLinearInterpolatePoints(points))
        }

        let camera = mapView.camera
        let maxSegmentLength =
            AdaptiveInterpolation.maxSegmentLengthMeters(
                zoom: camera.zoom,
                latitude: camera.target.latitude
            )
        let key =
            AdaptiveInterpolation.cacheKey(
                pointsHash: AdaptiveInterpolation.pointsHash(points),
                maxSegmentLengthMeters: maxSegmentLength
            )
        if let cached = interpolationCache.get(key) {
            return cached
        }

        let path = makePath(createInterpolatePoints(points, maxSegmentLength: maxSegmentLength))
        interpolationCache.put(key, path)
        return path
    }

    private func makePath(_ points: [GeoPointProtocol]) -> GMSPath {
        let ring = closeRing(points.map { $0.normalize() })
        let path = GMSMutablePath()
        for point in ring {
            path.add(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
        }
        return path
    }
}
