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
        let path = resolvedPath(for: state, mapView: mapView)

        let polygon = GMSPolygon(path: path)
        polygon.strokeColor = state.strokeColor
        polygon.strokeWidth = CGFloat(state.strokeWidth)
        polygon.fillColor = state.fillColor
        polygon.geodesic = state.geodesic
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

        if finger.points != prevFinger.points || finger.geodesic != prevFinger.geodesic {
            guard let mapView else { return polygon }
            polygon.path = resolvedPath(for: current.state, mapView: mapView)
            polygon.geodesic = current.state.geodesic
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

        return polygon
    }

    override func removePolygon(entity: PolygonEntity<GMSPolygon>) async {
        entity.polygon?.map = nil
    }

    private func resolvedPath(for state: PolygonState, mapView: GMSMapView) -> GMSPath {
        func rawPath(_ points: [GeoPointProtocol]) -> GMSPath {
            let path = GMSMutablePath()
            for point in points {
                path.add(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            }
            return path
        }

        if !state.geodesic {
            return rawPath(createLinearInterpolatePoints(state.points))
        }

        let camera = mapView.camera
        let maxSegmentLength =
            AdaptiveInterpolation.maxSegmentLengthMeters(
                zoom: camera.zoom,
                latitude: camera.target.latitude
            )
        let key =
            AdaptiveInterpolation.cacheKey(
                pointsHash: AdaptiveInterpolation.pointsHash(state.points),
                maxSegmentLengthMeters: maxSegmentLength
            )
        if let cached = interpolationCache.get(key) {
            return cached
        }

        let interpolated = createInterpolatePoints(state.points, maxSegmentLength: maxSegmentLength)
        // Google Maps iOS has practical limits on polygon point counts; fallback to raw points if too large.
        if interpolated.count > 10_000 {
            return rawPath(state.points)
        }

        let path = rawPath(interpolated)
        interpolationCache.put(key, path)
        return path
    }
}
