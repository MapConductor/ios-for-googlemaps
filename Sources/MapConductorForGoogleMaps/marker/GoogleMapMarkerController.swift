import Combine
import CoreLocation
import GoogleMaps
@_spi(MapConductorDriver) import MapConductorCore

@MainActor
final class GoogleMapMarkerController: AbstractMarkerController<GMSMarker, GoogleMapMarkerRenderer> {
    private weak var mapView: GMSMapView?

    private var markerStatesById: [String: MarkerState] = [:]
    private var markerSubscriptions: [String: AnyCancellable] = [:]

    private let onUpdateInfoBubble: (String) -> Void

    init(mapView: GMSMapView?, onUpdateInfoBubble: @escaping (String) -> Void) {
        self.mapView = mapView
        self.onUpdateInfoBubble = onUpdateInfoBubble

        let markerManager = MarkerManager<GMSMarker>.defaultManager()
        let renderer = GoogleMapMarkerRenderer(mapView: mapView, markerManager: markerManager)
        super.init(markerManager: markerManager, renderer: renderer)
    }

    /// 同一一覧の再送を見抜く門番。詳細は型のコメントに。
    private var syncIdentity = MarkerListIdentity()

    func syncMarkers(_ markers: [Marker]) {
        // 同じ一覧の再送は入口で帰す。SwiftUI はカメラが動くたびに body を
        // 再評価し、そのたびに全マーカーがここへ来る。なぜそれが実害か
        // （144k 件で操作の 89% が凍った）は core の MarkerListIdentity に。
        guard syncIdentity.shouldProcess(markers) else {
            refreshTileLayerIfNeeded()
            return
        }
        let newIds = Set(markers.map { $0.id })
        let oldIds = Set(markerStatesById.keys)

        var newStatesById: [String: MarkerState] = [:]
        var shouldSyncList = false

        for marker in markers {
            let state = marker.state
            if let existingState = markerStatesById[state.id], existingState !== state {
                markerSubscriptions[state.id]?.cancel()
                markerSubscriptions.removeValue(forKey: state.id)
                // State instance changed: ensure controller updates entity reference.
                shouldSyncList = true
            }
            newStatesById[state.id] = state
            if !markerManager.hasEntity(state.id) {
                shouldSyncList = true
            }
        }

        if oldIds != newIds {
            shouldSyncList = true
        }

        markerStatesById = newStatesById

        let removedIds = oldIds.subtracting(newIds)
        for id in removedIds {
            markerSubscriptions[id]?.cancel()
            markerSubscriptions.removeValue(forKey: id)
        }

        if shouldSyncList {
            Task { [weak self] in
                guard let self else { return }
                MCLog.marker("GoogleMapMarkerController.syncMarkers -> add()")
                await self.add(data: markers.map { $0.state })
            }
        } else {
            refreshTileLayerIfNeeded()
        }

        for marker in markers {
            subscribeToMarker(marker.state)
            onUpdateInfoBubble(marker.id)
        }
    }

    private func subscribeToMarker(_ state: MarkerState) {
        guard markerSubscriptions[state.id] == nil else { return }
        markerSubscriptions[state.id] = state.asFlow()
            .dropFirst() // Skip initial value to avoid triggering update on subscription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.markerStatesById[state.id] != nil else { return }
                MCLog.marker("GoogleMapMarkerController.asFlow emit id=\(state.id) anim=\(String(describing: state.getAnimation()))")
                Task { [weak self] in
                    guard let self else { return }
                    await self.update(state: state)
                    self.onUpdateInfoBubble(state.id)
                }
            }
    }

    func getMarkerState(for id: String) -> MarkerState? {
        markerManager.getEntity(id)?.state
    }

    func getIcon(for state: MarkerState) -> BitmapIcon {
        let resolvedIcon = state.icon ?? DefaultMarkerIcon()
        return resolvedIcon.toBitmapIcon()
    }

    // MARK: - Marker tiling

    var tilingOptions: MarkerTilingOptions = .Default
    private var tileRenderer: MarkerTileRenderer<GMSMarker>?
    private var tileRouteId: String?
    private var tiledMarkerIds: Set<String> = []
    private var tileTileLayer: GMSURLTileLayer?
    private var tileCacheClearScheduled = false
    private var lastSettledZoom = Double.nan
    private var settleClearTask: Task<Void, Never>?
    private var lastServerBaseUrl: String = ""
    private let defaultMarkerIconForTiling: BitmapIcon = DefaultMarkerIcon().toBitmapIcon()

    private static var retinaAwareTileSize: Int {
        256 * max(1, Int(UIScreen.main.scale))
    }

    private func setupTileRenderer() {
        let routeId = "mapconductor-markers-\(UUID().uuidString)"
        let contentScale = Double(UIScreen.main.scale)
        let baseCallback = tilingOptions.iconScaleCallback
        let scaledCallback: ((MarkerState, Int) -> Double)? = { state, zoom in
            (baseCallback?(state, zoom) ?? 1.0) * contentScale
        }
        MCLog.marker("GoogleMapMarkerController.setupTileRenderer tileSize=\(Self.retinaAwareTileSize) contentScale=\(contentScale) routeId=\(routeId)")
        let renderer = MarkerTileRenderer<GMSMarker>(
            markerManager: markerManager,
            tileSize: Self.retinaAwareTileSize,
            cacheSizeBytes: tilingOptions.cacheSize,
            debugTileOverlay: tilingOptions.debugTileOverlay,
            iconScaleCallback: scaledCallback,
            // MapLibre と同じく tilingOptions から。渡し忘れると 14px の間引きが
            // 黙って無効になり、密なデータで描画も突き合わせも重くなる（実際に
            // ここが 0 のままだった）。
            declutterPx: tilingOptions.declutterPx
        )
        // 「データはあるのに空」のタイルを、少し置いて検証する。
        //
        // 透明タイルは 200 で返るため、GMS はセッションの間それを有効な絵と
        // して持ち続け、再要求しない。取り込みや更新の途中に重なった空振りが
        // 四角い穴として固定化する（霞が関で実際に起きた）。700ms 後に同じ
        // 問い合わせをやり直し、**今度はマーカーが居た**ときだけ -- つまり
        // さっき渡した透明が嘘だったときだけ -- タイルキャッシュを捨てて
        // 引き直させる。本当に空の場所（皇居の堀）は何度聞いても空なので、
        // 捨てるループにはならない。
        renderer.onEmptyTileWhilePopulated = { [weak self, weak renderer] request in
            Task { @MainActor [weak self, weak renderer] in
                guard let self, !self.tileCacheClearScheduled else { return }
                self.tileCacheClearScheduled = true
                defer { self.tileCacheClearScheduled = false }
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard let renderer, !renderer.tileStillEmpty(request: request) else { return }
                MCLog.tileServer(
                    "GoogleMapMarkerController: transparent tile was a lie, clearTileCache "
                        + "(z=\(request.z)/\(request.x)/\(request.y))"
                )
                renderer.clear()
                self.tileTileLayer?.clearTileCache()
            }
        }
        TileServerRegistry.get().register(routeId: routeId, provider: renderer)
        tileRenderer = renderer
        tileRouteId = routeId
    }

    /// Hit-test tiled markers at the given screen point (pts). Returns true if a clickable marker was found.
    func handleTiledMarkerTap(at screenPoint: CGPoint) -> Bool {
        MCLog.marker("GoogleMapMarkerController.handleTiledMarkerTap point=\(screenPoint) tiledCount=\(tiledMarkerIds.count)")
        guard !tiledMarkerIds.isEmpty, let mapView, let tileRenderer else { return false }
        let state = tileRenderer.hitTest(
            screenPoint: screenPoint,
            markerIds: tiledMarkerIds,
            zoom: Int(mapView.camera.zoom.rounded()),
            unproject: { point in
                let coordinate = mapView.projection.coordinate(for: point)
                return GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
            }
        ) { point in
            mapView.projection.point(for: CLLocationCoordinate2D(
                latitude: point.latitude,
                longitude: point.longitude
            ))
        }

        if let state {
            MCLog.marker("GoogleMapMarkerController.handleTiledMarkerTap hit id=\(state.id)")
            dispatchClick(state: state)
            return true
        }
        MCLog.marker("GoogleMapMarkerController.handleTiledMarkerTap miss")
        return false
    }

    override func add(data: [MarkerState]) async {
        guard tilingOptions.enabled else {
            MCLog.marker("GoogleMapMarkerController.add tilingDisabled count=\(data.count)")
            await super.add(data: data)
            return
        }
        if tileRenderer == nil { setupTileRenderer() }

        let shouldTileAll = data.count >= tilingOptions.minMarkerCount
        MCLog.marker("GoogleMapMarkerController.add count=\(data.count) minMarkerCount=\(tilingOptions.minMarkerCount) shouldTileAll=\(shouldTileAll)")
        var localTiledMarkerIds = tiledMarkerIds
        let result = await MarkerIngestionEngine.ingest(
            data: data,
            markerManager: markerManager,
            renderer: renderer,
            defaultMarkerIcon: defaultMarkerIconForTiling,
            tilingEnabled: tilingOptions.enabled,
            tiledMarkerIds: &localTiledMarkerIds,
            shouldTile: { [shouldTileAll] _ in shouldTileAll }
        )
        tiledMarkerIds = localTiledMarkerIds
        MCLog.marker("GoogleMapMarkerController.add ingest done tiledDataChanged=\(result.tiledDataChanged) hasTiledMarkers=\(result.hasTiledMarkers) tiledCount=\(tiledMarkerIds.count)")

        if result.tiledDataChanged, let tileRenderer {
            tileRenderer.invalidate()
            updateTileLayer(hasTiledMarkers: result.hasTiledMarkers)
        }
    }

    /**
     ズームのジェスチャが**整数段を跨いで**静止したら、タイルキャッシュを 1 回捨てる。

     ズーム中、GMS はまだ届いていない段のタイルの代わりに親の絵を拡大して敷く。
     本来は目的の段が揃った時点で置き換わるが、静止後も一部の升だけ親の絵の
     ままになることがある -- サーバは全タイルを正しく返しているのに、画面では
     アイコンが切れたり、隣どうしで別サイズの丸が混ざって見える（皇居の南で
     実際に起きた形。サーバの現物 16 枚を繋いで確認した）。GMS の内部合成は
     こちらから直せないので、静止のたびに引き直させて収束を保証する。

     コストは静止 1 回につき可視タイル分の再取得だが、サーバ側の NSCache に
     全部載っているので 1 枚あたり数 ms。パンだけ（同じ段のまま）の静止では
     何もしない。
     */
    func cameraSettled(zoom: Double) {
        /*
         既定では何もしない。

         この「静止 2 秒後のレイヤー再構築」は、切れ・割れの正体が GMS 側の
         合成崩れだと疑っていた時期の保険。実際の正体はタイルを焼く側
         （GPU 経路の誤描画と、404/透明のキャッシュ焼き付き）で、どちらも
         発生源で直した。原因が消えた今、毎静止の全タイル引き直しはちらつきと
         無駄で、`MAPCONDUCTOR_GMS_SETTLE_REBUILD=1` の実験用にだけ残す。
         */
        guard ProcessInfo.processInfo.environment["MAPCONDUCTOR_GMS_SETTLE_REBUILD"] == "1" else {
            return
        }
        /*
         「整数段が変わったときだけ」では足りなかった。z15.7 から摘まんで z15.5 で
         止まると、丸めた段は同じ 16 のままだが、ジェスチャの間に GMS は z15 と
         z16 の両方のタイルを取り込み、画面には両方が貼り交ぜられたまま残る
         （新宿中央公園で再現。継ぎ目の上下で別の段の絵だった）。だから
         **ズーム値が実際に動いた静止はすべて**引き直す。パンだけの静止は
         ズームが変わらないので、今まで通り何もしない。
         */
        let firstSettle = lastSettledZoom.isNaN
        let moved = firstSettle || abs(zoom - lastSettledZoom) > 0.05
        lastSettledZoom = zoom
        guard moved, !firstSettle, tileTileLayer != nil else { return }
        let settled = Int(zoom.rounded())
        /*
         すぐには捨てない。静止の瞬間はその段のタイルがまだ配信中で、届いた
         そばから捨てると **GMS はそれを再要求しない** -- 実測では静止 80ms 後の
         クリアで、クリア直前に届いた升だけが古い絵のまま残った（戸越で再現。
         クリア前 21:18:11.12-.18 に届いた 29100-29101 が欠け、クリア後に届いた
         29102-29103 は正常だった）。2 秒待てば配信は確実に済んでいて、静かな
         状態でのクリアは全升の引き直しになる。ズームが続いたらやり直す。
         */
        settleClearTask?.cancel()
        settleClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !Task.isCancelled, Int(self.lastSettledZoom.rounded()) == settled else { return }
            /*
             clearTileCache では足りなかった。実測では、クリア後に正しいタイルを
             再取得させても（サーバログで配信を確認済み）、一部の升だけ古い絵の
             まま描かれ続けた -- GMS が保持するデコード済みテクスチャまでは
             捨てられないらしい。レイヤーごと作り直せば GMS 側の状態は全部消え、
             全升がまっさらに引き直される。サーバの NSCache に全部載っているので
             引き直しは 1 枚数 ms。
             */
            MCLog.tileServer("GoogleMapMarkerController: zoom settled at \(settled), rebuilding tile layer")
            self.updateTileLayer(hasTiledMarkers: !self.tiledMarkerIds.isEmpty)
        }
    }

    private func refreshTileLayerIfNeeded() {
        guard !tiledMarkerIds.isEmpty else { return }
        let server = TileServerRegistry.get()
        guard server.baseUrl != lastServerBaseUrl else { return }
        MCLog.marker("GoogleMapMarkerController.refreshTileLayerIfNeeded serverRestarted oldUrl=\(lastServerBaseUrl) newUrl=\(server.baseUrl)")
        updateTileLayer(hasTiledMarkers: true)
    }

    private func updateTileLayer(hasTiledMarkers: Bool) {
        MCLog.marker("GoogleMapMarkerController.updateTileLayer hasTiledMarkers=\(hasTiledMarkers) mapView=\(mapView != nil) routeId=\(tileRouteId ?? "nil")")
        tileTileLayer?.map = nil
        tileTileLayer = nil

        guard hasTiledMarkers, let mapView, let routeId = tileRouteId, let tileRenderer else { return }

        let server = TileServerRegistry.get()
        lastServerBaseUrl = server.baseUrl
        let urlTemplate = server.urlTemplate(routeId: routeId, tileSize: tileRenderer.tileSize)
        MCLog.marker("GoogleMapMarkerController.updateTileLayer addLayer urlTemplate=\(urlTemplate) tileSize=\(tileRenderer.tileSize)")

        let layer = GMSURLTileLayer { (x, y, zoom) in
            let url = urlTemplate
                .replacingOccurrences(of: "{z}", with: String(zoom))
                .replacingOccurrences(of: "{x}", with: String(x))
                .replacingOccurrences(of: "{y}", with: String(y))
            return URL(string: url)
        }
        layer.tileSize = tileRenderer.tileSize
        // タイル差し替え時のフェードを切る。フェード中の升は古い絵と新しい絵の
        // 合成で、そこにジェスチャが重なると途中の絵が残ることがある。
        layer.fadeIn = false
        layer.zIndex = 0
        layer.map = mapView
        tileTileLayer = layer
    }

    func unbind() {
        markerSubscriptions.values.forEach { $0.cancel() }
        markerSubscriptions.removeAll()
        markerStatesById.removeAll()
        tileTileLayer?.map = nil
        tileTileLayer = nil
        if let routeId = tileRouteId {
            TileServerRegistry.get().unregister(routeId: routeId)
        }
        tileRenderer = nil
        tileRouteId = nil
        tiledMarkerIds.removeAll()
        renderer.unbind()
        mapView = nil
        destroy()
    }
}
