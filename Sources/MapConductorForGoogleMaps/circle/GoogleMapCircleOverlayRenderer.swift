import CoreLocation
import GoogleMaps
import MapConductorCore
import UIKit

@MainActor
final class GoogleMapCircleOverlayRenderer: AbstractCircleOverlayRenderer<GMSPolygon> {
    private weak var mapView: GMSMapView?

    init(mapView: GMSMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createCircle(state: CircleState) async -> GMSPolygon? {
        guard let mapView else { return nil }
        let center = CLLocationCoordinate2D(latitude: state.center.latitude, longitude: state.center.longitude)
        let adjustedRadius = adjustedRadiusMeters(for: state, center: center)
        let path = makeCirclePath(center: state.center, radiusMeters: adjustedRadius, geodesic: state.geodesic)

        let polygon = GMSPolygon(path: path)
        polygon.strokeColor = state.strokeColor
        polygon.strokeWidth = CGFloat(state.strokeWidth)
        polygon.fillColor = state.fillColor
        // Use mapView(_:didTapAt:) + CircleManager hit-testing for click handling.
        // If we set this tappable, Google Maps consumes taps and we'd need mapView(_:didTap:) overlay handling.
        polygon.isTappable = false
        polygon.zIndex = Int32(state.zIndex ?? 0)
        polygon.geodesic = state.geodesic
        polygon.map = mapView
        polygon.userData = state.id
        return polygon
    }

    override func updateCircleProperties(
        circle: GMSPolygon,
        current: CircleEntity<GMSPolygon>,
        prev: CircleEntity<GMSPolygon>
    ) async -> GMSPolygon? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        if finger.center != prevFinger.center ||
            finger.radiusMeters != prevFinger.radiusMeters ||
            finger.geodesic != prevFinger.geodesic ||
            finger.strokeWidth != prevFinger.strokeWidth {
            let center = CLLocationCoordinate2D(latitude: current.state.center.latitude, longitude: current.state.center.longitude)
            let adjustedRadius = adjustedRadiusMeters(for: current.state, center: center)
            circle.path = makeCirclePath(
                center: current.state.center,
                radiusMeters: adjustedRadius,
                geodesic: current.state.geodesic
            )
            circle.geodesic = current.state.geodesic
        }

        if finger.strokeWidth != prevFinger.strokeWidth {
            circle.strokeWidth = CGFloat(current.state.strokeWidth)
        }

        if finger.strokeColor != prevFinger.strokeColor {
            circle.strokeColor = current.state.strokeColor
        }

        if finger.fillColor != prevFinger.fillColor {
            circle.fillColor = current.state.fillColor
        }

        if finger.clickable != prevFinger.clickable {
            circle.isTappable = current.state.clickable
        }

        if finger.zIndex != prevFinger.zIndex {
            circle.zIndex = Int32(current.state.zIndex ?? 0)
        }

        return circle
    }

    override func removeCircle(entity: CircleEntity<GMSPolygon>) async {
        entity.circle?.map = nil
    }

    private func adjustedRadiusMeters(for state: CircleState, center: CLLocationCoordinate2D) -> Double {
        let strokeWidth = max(0.0, state.strokeWidth)
        guard strokeWidth > 0.0 else { return state.radiusMeters }
        guard let mapView else { return state.radiusMeters }
        let projection = mapView.projection
        let centerPoint = projection.point(for: center)
        let offsetPoint = CGPoint(x: centerPoint.x, y: centerPoint.y - CGFloat(strokeWidth / 2.0))
        let offsetCoord = projection.coordinate(for: offsetPoint)
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let offsetLocation = CLLocation(latitude: offsetCoord.latitude, longitude: offsetCoord.longitude)
        let strokeMeters = centerLocation.distance(from: offsetLocation)
        return state.radiusMeters + strokeMeters
    }
}

/// Builds the circle outline from the core `circleToRing` (shared across providers, WGS84
/// radius) and closes it with `closeRing`.
private func makeCirclePath(
    center: GeoPointProtocol,
    radiusMeters: Double,
    geodesic: Bool
) -> GMSPath {
    let ring = closeRing(circleToRing(center: center, radiusMeters: radiusMeters, geodesic: geodesic))
    let path = GMSMutablePath()
    for point in ring {
        path.add(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
    }
    return path
}
