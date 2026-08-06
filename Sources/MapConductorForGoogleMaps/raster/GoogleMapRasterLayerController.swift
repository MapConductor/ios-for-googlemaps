import GoogleMaps
import MapConductorCore

@MainActor
final class GoogleMapRasterLayerController: RasterLayerController<GMSURLTileLayer, GoogleMapRasterLayerOverlayRenderer> {
    private weak var mapView: GMSMapView?

    init(mapView: GMSMapView?) {
        self.mapView = mapView
        let rasterManager = RasterLayerManager<GMSURLTileLayer>()
        let renderer = GoogleMapRasterLayerOverlayRenderer(mapView: mapView)
        super.init(rasterLayerManager: rasterManager, renderer: renderer)
    }

    func unbind() {
        mapView = nil
        destroy()
    }
}
