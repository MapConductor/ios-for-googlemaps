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
        polygon.zIndex = Int32(truncatingIfNeeded: state.zIndex)
        polygon.holes = state.holes.map { holePoints in
            resolvedHolePath(for: holePoints)
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
            polygon.path = resolvedPath(for: current.state, mapView: mapView)
            polygon.geodesic = current.state.geodesic
            polygon.holes = current.state.holes.map { holePoints in
                resolvedHolePath(for: holePoints)
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

    private func resolvedPath(for state: PolygonState, mapView: GMSMapView) -> GMSPath {
        func rawPath(_ points: [GeoPointProtocol]) -> GMSPath {
            let path = GMSMutablePath()
            for point in closedNormalizedRing(points) {
                path.add(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            }
            return path
        }
        // Let Google Maps render polygon edges from the original ring.
        // Extra interpolation can distort complex outlines and produce broken strokes.
        _ = mapView
        _ = interpolationCache
        return rawPath(state.points)
    }

    private func resolvedHolePath(for points: [GeoPointProtocol]) -> GMSPath {
        let path = GMSMutablePath()
        for point in closedNormalizedRing(points) {
            path.add(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
        }
        return path
    }

    private func closedNormalizedRing(_ points: [GeoPointProtocol]) -> [GeoPointProtocol] {
        var ring = points.map { $0.normalize() }
        if let first = ring.first, let last = ring.last,
           !(GeoPoint.from(position: first) == GeoPoint.from(position: last)) {
            ring.append(first)
        }
        return ring
    }
}
