import GoogleMaps
import MapConductorCore
import UIKit

@MainActor
final class GoogleMapPolylineOverlayRenderer: AbstractPolylineOverlayRenderer<GMSPolyline> {
    private weak var mapView: GMSMapView?
    private let interpolationCache = InterpolationCache<GMSPath>(countLimit: 64)

    init(mapView: GMSMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createPolyline(state: PolylineState) async -> GMSPolyline? {
        guard let mapView else { return nil }
        let path = resolvedPath(for: state, mapView: mapView)

        let polyline = GMSPolyline(path: path)
        polyline.strokeColor = state.strokeColor
        polyline.strokeWidth = CGFloat(state.strokeWidth)
        polyline.geodesic = state.geodesic
        polyline.isTappable = false
        polyline.map = mapView
        polyline.userData = state.id
        return polyline
    }

    override func updatePolylineProperties(
        polyline: GMSPolyline,
        current: PolylineEntity<GMSPolyline>,
        prev: PolylineEntity<GMSPolyline>
    ) async -> GMSPolyline? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        if finger.points != prevFinger.points || finger.geodesic != prevFinger.geodesic {
            guard let mapView else { return polyline }
            polyline.path = resolvedPath(for: current.state, mapView: mapView)
            polyline.geodesic = current.state.geodesic
        }

        if finger.strokeWidth != prevFinger.strokeWidth {
            polyline.strokeWidth = CGFloat(current.state.strokeWidth)
        }

        if finger.strokeColor != prevFinger.strokeColor {
            polyline.strokeColor = current.state.strokeColor
        }

        return polyline
    }

    override func removePolyline(entity: PolylineEntity<GMSPolyline>) async {
        entity.polyline?.map = nil
    }

    private func resolvedPath(for state: PolylineState, mapView: GMSMapView) -> GMSPath {
        if !state.geodesic {
            let geoPoints = createLinearInterpolatePoints(state.points)
            let path = GMSMutablePath()
            for point in geoPoints {
                path.add(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            }
            return path
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

        let geoPoints = createInterpolatePoints(state.points, maxSegmentLength: maxSegmentLength)
        let path = GMSMutablePath()
        for point in geoPoints {
            path.add(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
        }
        interpolationCache.put(key, path)
        return path
    }
}
