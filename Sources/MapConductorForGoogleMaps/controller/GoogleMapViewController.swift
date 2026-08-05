import CoreLocation
import GoogleMaps
import MapConductorCore
import QuartzCore

final class GoogleMapViewController: MapViewControllerProtocol {
    let holder: AnyMapViewHolder
    let typedHolder: GoogleMapViewHolder
    let coroutine = CoroutineScope()
    private weak var mapView: GMSMapView?
    private(set) var lastLogicalTilt: Double?

    private var cameraMoveStartListener: OnCameraMoveHandler?
    private var cameraMoveListener: OnCameraMoveHandler?
    private var cameraMoveEndListener: OnCameraMoveHandler?
    private var mapClickListener: OnMapEventHandler?
    private var mapLongClickListener: OnMapEventHandler?
    private var mapInitializedListener: OnMapInitializedHandler?

    init(mapView: GMSMapView) {
        self.mapView = mapView
        let typedHolder = GoogleMapViewHolder(mapView: mapView)
        self.typedHolder = typedHolder
        self.holder = AnyMapViewHolder(typedHolder)
    }

    func clearOverlays() async {
        await mapView?.clear()
    }

    func setCameraMoveStartListener(listener: OnCameraMoveHandler?) {
        cameraMoveStartListener = listener
    }

    func setCameraMoveListener(listener: OnCameraMoveHandler?) {
        cameraMoveListener = listener
    }

    func setCameraMoveEndListener(listener: OnCameraMoveHandler?) {
        cameraMoveEndListener = listener
    }

    func setMapClickListener(listener: OnMapEventHandler?) {
        mapClickListener = listener
    }

    func setMapLongClickListener(listener: OnMapEventHandler?) {
        mapLongClickListener = listener
    }

    func setMapInitializedListener(listener: OnMapInitializedHandler?) {
        mapInitializedListener = listener
    }

    func moveCamera(position: MapCameraPosition) {
        guard let mapView = mapView else { return }
        lastLogicalTilt = position.tilt
        let camera = position.toCameraPosition()
        mapView.moveCamera(GMSCameraUpdate.setCamera(camera))
    }

    func animateCamera(position: MapCameraPosition, duration: Long) {
        guard let mapView = mapView else { return }
        lastLogicalTilt = position.tilt
        let camera = position.toCameraPosition()
        let update = GMSCameraUpdate.setCamera(camera)
        CATransaction.begin()
        CATransaction.setAnimationDuration(Double(duration) / 1000.0)
        mapView.animate(with: update)
        CATransaction.commit()
    }

    func setCameraRestriction(_ restriction: CameraRestriction?) {
        guard let mapView = mapView else { return }
        // Google Maps の統一ズームはネイティブズームそのものなので変換不要
        // （android-for-googlemaps と同一仕様）。
        if let sw = restriction?.bounds?.southWest, let ne = restriction?.bounds?.northEast {
            mapView.cameraTargetBounds = GMSCoordinateBounds(
                coordinate: CLLocationCoordinate2D(latitude: sw.latitude, longitude: sw.longitude),
                coordinate: CLLocationCoordinate2D(latitude: ne.latitude, longitude: ne.longitude)
            )
        } else {
            mapView.cameraTargetBounds = nil
        }
        // preference をクリアするには下限/上限に既定値を渡す必要があるため、
        // 未指定時は kGMSMinZoomLevel / kGMSMaxZoomLevel へ戻す。
        mapView.setMinZoom(
            Float(restriction?.minZoom ?? Double(kGMSMinZoomLevel)),
            maxZoom: Float(restriction?.maxZoom ?? Double(kGMSMaxZoomLevel))
        )
    }

    func fitBounds(bounds: GeoRectBounds, padding: Int) {
        guard let mapView = mapView,
              let sw = bounds.southWest,
              let ne = bounds.northEast else { return }
        let coordinateBounds = GMSCoordinateBounds(
            coordinate: CLLocationCoordinate2D(latitude: sw.latitude, longitude: sw.longitude),
            coordinate: CLLocationCoordinate2D(latitude: ne.latitude, longitude: ne.longitude)
        )
        let update = GMSCameraUpdate.fit(coordinateBounds, withPadding: CGFloat(padding))
        mapView.moveCamera(update)
    }

    func notifyCameraMoveStart(_ cameraPosition: MapCameraPosition) {
        cameraMoveStartListener?(cameraPosition)
    }

    func notifyCameraMove(_ cameraPosition: MapCameraPosition) {
        cameraMoveListener?(cameraPosition)
    }

    func notifyCameraMoveEnd(_ cameraPosition: MapCameraPosition) {
        cameraMoveEndListener?(cameraPosition)
    }

    func notifyMapClick(_ point: GeoPoint) {
        mapClickListener?(point)
    }

    func notifyMapLongClick(_ point: GeoPoint) {
        mapLongClickListener?(point)
    }

    func notifyMapInitialized() {
        mapInitializedListener?(.MapCreated)
    }
}
