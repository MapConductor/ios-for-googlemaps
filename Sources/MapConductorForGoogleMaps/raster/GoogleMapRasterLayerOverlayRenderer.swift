import GoogleMaps
import MapConductorCore
import UIKit

@MainActor
final class GoogleMapRasterLayerOverlayRenderer: AbstractRasterLayerOverlayRenderer<GMSTileLayer> {
    private weak var mapView: GMSMapView?
    private var tileSources: [ObjectIdentifier: GoogleRasterTileURLSource] = [:]

    init(mapView: GMSMapView?) {
        self.mapView = mapView
        super.init()
    }

    override func createLayer(state: RasterLayerState) async -> GMSTileLayer? {
        guard let mapView else { return nil }
        guard let layer = makeTileLayer(from: state) else { return nil }
        layer.opacity = Float(state.opacity)
        layer.zIndex = Int32(clamping: state.zIndex)
        applyVisibility(layer: layer, state: state, mapView: mapView)
        return layer
    }

    override func updateLayerProperties(
        layer: GMSTileLayer,
        current: RasterLayerEntity<GMSTileLayer>,
        prev: RasterLayerEntity<GMSTileLayer>
    ) async -> GMSTileLayer? {
        let finger = current.fingerPrint
        let prevFinger = prev.fingerPrint

        var refreshTiles = false
        if finger.source != prevFinger.source,
           let source = tileSources[ObjectIdentifier(layer)],
           (layer is GoogleLocalTileLayer) == isLocalSource(current.state.source),
           source.update(current.state.source) {
            // Keep the attached layer and its draw order. The constructor
            // reads the latest template when Google requests refreshed tiles.
            (layer as? GoogleLocalTileLayer)?.cancelRequests()
            refreshTiles = true
        } else if finger.source != prevFinger.source {
            tileSources.removeValue(forKey: ObjectIdentifier(layer))
            localLayers.removeValue(forKey: ObjectIdentifier(layer))
            (layer as? GoogleLocalTileLayer)?.cancelRequests()
            layer.map = nil
            guard let mapView else { return nil }
            guard let newLayer = makeTileLayer(from: current.state) else { return nil }
            newLayer.opacity = Float(current.state.opacity)
            newLayer.zIndex = Int32(clamping: current.state.zIndex)
            applyVisibility(layer: newLayer, state: current.state, mapView: mapView)
            return newLayer
        }

        if finger.opacity != prevFinger.opacity {
            layer.opacity = Float(current.state.opacity)
        }

        if finger.zIndex != prevFinger.zIndex {
            layer.zIndex = Int32(clamping: current.state.zIndex)
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

        if refreshTiles { layer.clearTileCache() }

        return layer
    }

    override func removeLayer(entity: RasterLayerEntity<GMSTileLayer>) async {
        if let layer = entity.layer {
            tileSources.removeValue(forKey: ObjectIdentifier(layer))
            localLayers.removeValue(forKey: ObjectIdentifier(layer))
        }
        (entity.layer as? GoogleLocalTileLayer)?.cancelRequests()
        entity.layer?.map = nil
    }

    func cameraChanged(zoom: Double) {
        for layer in localLayers.values {
            layer.cameraChanged(zoom: zoom)
        }
    }

    func detachLocalLayers() {
        for layer in localLayers.values {
            layer.cancelRequests()
            layer.map = nil
        }
        localLayers.removeAll()
        tileSources.removeAll()
    }

    private var localLayers: [ObjectIdentifier: GoogleLocalTileLayer] = [:]

    private func isLocalSource(_ source: RasterLayerSource) -> Bool {
        guard case let .urlTemplate(template, _, _, _, _, _) = source else { return false }
        guard template.hasPrefix("http://127.0.0.1:") else { return false }
        return template.hasPrefix(TileServerRegistry.get().baseUrl + "/tiles/")
    }

    private func applyVisibility(layer: GMSTileLayer, state: RasterLayerState, mapView: GMSMapView) {
        if !state.visible { (layer as? GoogleLocalTileLayer)?.cancelRequests() }
        layer.map = state.visible ? mapView : nil
    }

    private func applyUserAgent(layer: GMSTileLayer, state: RasterLayerState) {
        guard let layer = layer as? GMSURLTileLayer else { return }
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

    private func makeTileLayer(from state: RasterLayerState) -> GMSTileLayer? {
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
        case let .urlTemplate(_, tileSize, _, _, _, _):
            guard let source = GoogleRasterTileURLSource(state.source) else { return nil }
            if isLocalSource(state.source) {
                let layer = GoogleLocalTileLayer(source: source, server: TileServerRegistry.get(), logicalTileSize: tileSize)
                localLayers[ObjectIdentifier(layer)] = layer
                tileSources[ObjectIdentifier(layer)] = source
                layer.tileSize = Self.nativeTileSize(tileSize)
                if let mapView { layer.cameraChanged(zoom: Double(mapView.camera.zoom)) }
                return layer
            }
            let urls: GMSTileURLConstructor = { (x, y, zoom) in
                source.url(x: x, y: y, zoom: zoom)
            }
            
            // Do not change the below line
            let layer = GMSURLTileLayer(urlConstructor: urls)
            tileSources[ObjectIdentifier(layer)] = source
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

/// The SDK retains its constructor. Protect its configuration independently
/// of the main-actor renderer so a callback never reads partially updated data.
final class GoogleRasterTileURLSource {
    private let lock = NSLock()
    private var source: RasterLayerSource
    private let tileSize: Int

    init?(_ source: RasterLayerSource) {
        guard case let .urlTemplate(_, tileSize, _, _, _, _) = source else { return nil }
        self.source = source
        self.tileSize = tileSize
    }

    /// A different tile grid needs a new layer; URL and coverage changes do not.
    func update(_ next: RasterLayerSource) -> Bool {
        guard case let .urlTemplate(_, size, _, _, _, _) = next, size == tileSize else {
            return false
        }
        lock.lock()
        source = next
        lock.unlock()
        return true
    }

    func url(x: UInt, y: UInt, zoom: UInt) -> URL? {
        lock.lock()
        let current = source
        lock.unlock()
        guard case let .urlTemplate(template, _, minZoom, maxZoom, _, scheme) = current else {
            return nil
        }
        guard zoom < UInt(Int.bitWidth - 1) else { return nil }
        let z = Int(zoom)
        if let minZoom, z < minZoom { return nil }
        if let maxZoom, z > maxZoom { return nil }
        // The supported map zoom range is far below the integer shift limit.
        let extent = UInt(1 << z)
        guard scheme != .TMS || y < extent else { return nil }
        let tileY = scheme == .TMS ? extent - 1 - y : y
        return URL(string: template
            .replacingOccurrences(of: "{z}", with: String(z))
            .replacingOccurrences(of: "{x}", with: String(x))
            .replacingOccurrences(of: "{y}", with: String(tileY)))
    }
}
