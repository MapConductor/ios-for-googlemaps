import GoogleMaps
import MapConductorCore
import UIKit

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

    /// `GMSURLTileLayer` は `userAgent` しか公開していない。`extraHeaders` は載せられない。
    private func logUnsupportedExtraHeadersIfNeeded(_ state: RasterLayerState) {
        RasterHeaderRuleSet.warnUnsupported(provider: "GoogleMaps", state: state, supportsUserAgent: true)
    }

    /// MapConductor の `tileSize`（ポイント）→ この SDK が求める**物理ピクセル**。
    ///
    /// `GMSTileLayer.tileSize` は「タイル画像を何**ピクセル**として表示したいか」で、
    /// ポイントではない（既定 256）。ポイント数をそのまま渡すと、3 倍の端末では
    /// タイルを 1/3 の大きさで敷きたがるので、SDK は**2 段深いズームのタイル**を要求する。
    ///
    /// 実測（地図ズーム 13、`tileSize` 512 の GeoJSON レイヤ、iPhone シミュレータ）:
    ///
    /// 実測（地図ズーム 13、`tileSize` 512 の GeoJSON レイヤ、iPhone 17 Pro シミュレータ）:
    ///
    /// | 渡す値 | 要求されるタイル z | 線の太さ |
    /// |---|---|---|
    /// | 512（ポイントのまま） | 14 | 5px |
    /// | 512 × 3 = 1536 | 13 | 9px |
    /// | 512 × 6 = 3072 | 13 | 9px |
    ///
    /// **これでも MapLibre（z=12・18px）には届かない。** 1536 と 3072 で結果が同じなので、
    /// SDK 側が `tileSize` に上限（おそらく 1024）を持っていると見られる。倍率を上げても
    /// それ以上は動かないので、正直な値である「実際の画素数 × 画面倍率」を渡すに留める。
    /// 残りの 1 段は SDK に外から効かせる手が無い。
    ///
    /// react-for-googlemaps の `tileZoomForGoogleTileSize` が web 側で同じ辻褄合わせを
    /// している（あちらは CSS ピクセル基準なので倍率は 1）。
    private static func nativeTileSize(_ tileSize: Int) -> Int {
        let scale = max(1, Int(UIScreen.main.scale.rounded()))
        return max(1, tileSize) * scale
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
            layer.tileSize = Self.nativeTileSize(tileSize)
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
                        tileSize: RasterLayerSource.defaultTileSize,
                        minZoom: nil,
                        maxZoom: nil,
                        attributionRules: [],
                        scheme: .XYZ
                    )
                )
            return makeTileLayer(from: arcGisState)
        }
    }
}
