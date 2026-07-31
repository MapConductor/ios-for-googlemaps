import CoreGraphics
import CoreLocation
import GoogleMaps
import MapConductorCore

public final class GoogleMapViewHolder: MapViewHolderProtocol {
    public let mapView: GMSMapView
    public let map: GMSMapView

    init(mapView: GMSMapView) {
        self.mapView = mapView
        self.map = mapView
    }

    public func toScreenOffset(position: GeoPointProtocol) -> CGPoint? {
        let coordinate = CLLocationCoordinate2D(latitude: position.latitude, longitude: position.longitude)
        return mapView.projection.point(for: coordinate)
    }

    public func fromScreenOffset(offset: CGPoint) async -> GeoPoint? {
        fromScreenOffsetSync(offset: offset)
    }

    public func fromScreenOffsetSync(offset: CGPoint) -> GeoPoint? {
        let coordinate = mapView.projection.coordinate(for: offset)
        return GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
    }
}
