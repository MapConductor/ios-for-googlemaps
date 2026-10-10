import GoogleMaps
import MapConductorCore

@MainActor
final class GoogleMapRasterLayerController: RasterLayerController<GMSTileLayer, GoogleMapRasterLayerOverlayRenderer> {
    private weak var mapView: GMSMapView?

    init(mapView: GMSMapView?) {
        self.mapView = mapView
        let rasterManager = RasterLayerManager<GMSTileLayer>()
        let renderer = GoogleMapRasterLayerOverlayRenderer(mapView: mapView)
        super.init(rasterLayerManager: rasterManager, renderer: renderer)
    }

    func unbind() {
        renderer.detachLocalLayers()
        mapView = nil
        destroy()
    }

    override func onCameraChanged(mapCameraPosition: MapCameraPosition) async {
        renderer.cameraChanged(zoom: mapCameraPosition.zoom)
    }

}
