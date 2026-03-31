import GoogleMaps
import MapConductorCore

@MainActor
final class GoogleMapRasterLayerOverlayRenderer: AbstractRasterLayerOverlayRenderer<GMSURLTileLayer> {
    private weak var mapView: GMSMapView?

    init(mapView: GMSMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createLayer(state: RasterLayerState) async -> GMSURLTileLayer? {
        guard let mapView else { return nil }
        guard let layer = makeTileLayer(from: state) else { return nil }
        applyVisibility(layer: layer, state: state, mapView: mapView)
        layer.opacity = Float(state.opacity)
        layer.zIndex = Int32(0)
        return layer
    }

    override func updateLayerProperties(
        layer: GMSURLTileLayer,
        current: RasterLayerEntity<GMSURLTileLayer>,
        prev: RasterLayerEntity<GMSURLTileLayer>
    ) async -> GMSURLTileLayer? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        if finger.source != prevFinger.source {
            layer.map = nil
            guard let mapView else { return nil }
            guard let newLayer = makeTileLayer(from: current.state) else { return nil }
            applyVisibility(layer: newLayer, state: current.state, mapView: mapView)
            newLayer.opacity = Float(current.state.opacity)
            newLayer.zIndex = Int32(0)
            return newLayer
        }

        if finger.opacity != prevFinger.opacity {
            layer.opacity = Float(current.state.opacity)
        }

        if finger.visible != prevFinger.visible {
            guard let mapView else { return layer }
            applyVisibility(layer: layer, state: current.state, mapView: mapView)
        }

        if finger.userAgent != prevFinger.userAgent {
            applyUserAgent(layer: layer, state: current.state)
        }

        if finger.extraHeaders != prevFinger.extraHeaders {
            logUnsupportedExtraHeadersIfNeeded(current.state)
        }

        return layer
    }

    override func removeLayer(entity: RasterLayerEntity<GMSURLTileLayer>) async {
        entity.layer?.map = nil
    }

    private func applyVisibility(layer: GMSURLTileLayer, state: RasterLayerState, mapView: GMSMapView) {
        layer.map = state.visible ? mapView : nil
    }

    private func applyUserAgent(layer: GMSURLTileLayer, state: RasterLayerState) {
        let ua = state.userAgent?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if let ua, !ua.isEmpty {
            layer.userAgent = ua
        } else {
            let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
            layer.userAgent = "iOS App(\(bundleId)) powered by MapConductor"
        }
    }

    private func logUnsupportedExtraHeadersIfNeeded(_ state: RasterLayerState) {
        guard let headers = state.extraHeaders, !headers.isEmpty else { return }
        NSLog("[MapConductor] GoogleMaps RasterLayer: extraHeaders are not supported on iOS and will be ignored. id=%@", state.id)
    }

    private func makeTileLayer(from state: RasterLayerState) -> GMSURLTileLayer? {
        logUnsupportedExtraHeadersIfNeeded(state)

        switch state.source {
            /*
             *   GMSTileURLConstructor constructor = ^(NSUInteger x, NSUInteger y, NSUInteger zoom) {
             *     NSString *URLStr =
             *         [NSString stringWithFormat:@"https://example.com/%d/%d/%d.png", x, y, zoom];
             *     return [NSURL URLWithString:URLStr];
             *   };
             *   GMSTileLayer *layer =
             *       [GMSURLTileLayer tileLayerWithURLConstructor:constructor];
             *   layer.userAgent = @"SDK user agent";
             *   layer.map = map;
             */
        case let .urlTemplate(template, tileSize, minZoom, maxZoom, _, scheme):
            let urls: GMSTileURLConstructor = { (x, y, zoom) in
                let zoomInt = Int(zoom)
                if let minZoom {
                    if zoomInt < minZoom {
                        return nil
                    }
                }
                if let maxZoom {
                    if zoomInt > maxZoom {
                        return nil
                    }
                }

                let tileY: UInt
                switch scheme {
                case .XYZ:
                    tileY = y
                case .TMS:
                    let max = 1 << zoomInt
                    tileY = UInt(max - 1 - Int(y))
                }

                let url = template
                    .replacingOccurrences(of: "{z}", with: String(zoomInt))
                    .replacingOccurrences(of: "{y}", with: String(tileY))
                    .replacingOccurrences(of: "{x}", with: String(x))
                return URL(string: url)
            }
            
            // Do not change the below line
            let layer = GMSURLTileLayer(urlConstructor: urls)
            layer.tileSize = Int(max(1, tileSize))
            applyUserAgent(layer: layer, state: state)
            return layer
        case .tileJson:
            NSLog("[MapConductor] GoogleMaps RasterLayer: tileJson sources are not supported on iOS yet. id=%@", state.id)
            return nil
        case let .arcGisService(serviceUrl):
            let base = serviceUrl.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let template = "\(base)/tile/{z}/{y}/{x}"
            let arcGisState =
                state.copy(
                    source: .urlTemplate(
                        template: template,
                        tileSize: RasterSource.defaultTileSize,
                        minZoom: nil,
                        maxZoom: nil,
                        attribution: nil,
                        scheme: .XYZ
                    )
                )
            return makeTileLayer(from: arcGisState)
        }
    }
}
