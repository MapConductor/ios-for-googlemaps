import Combine
import CoreLocation
import GoogleMaps
import MapConductorCore

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

    func syncMarkers(_ markers: [Marker]) {
        MCLog.marker("GoogleMapMarkerController.syncMarkers count=\(markers.count)")
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
        MCLog.marker("GoogleMapMarkerController.subscribe id=\(state.id)")
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
            iconScaleCallback: scaledCallback
        )
        TileServerRegistry.get().register(routeId: routeId, provider: renderer)
        tileRenderer = renderer
        tileRouteId = routeId
    }

    /// Hit-test tiled markers at the given screen point (pts). Returns true if a clickable marker was found.
    func handleTiledMarkerTap(at screenPoint: CGPoint) -> Bool {
        MCLog.marker("GoogleMapMarkerController.handleTiledMarkerTap point=\(screenPoint) tiledCount=\(tiledMarkerIds.count)")
        guard !tiledMarkerIds.isEmpty, let mapView else { return false }
        let clickRadiusPt: CGFloat = 44
        var bestState: MarkerState? = nil
        var bestDist = CGFloat.infinity

        for id in tiledMarkerIds {
            guard let entity = markerManager.getEntity(id), entity.state.clickable else { continue }
            let coord = CLLocationCoordinate2D(
                latitude: entity.state.position.latitude,
                longitude: entity.state.position.longitude
            )
            let markerPoint = mapView.projection.point(for: coord)
            let dist = hypot(screenPoint.x - markerPoint.x, screenPoint.y - markerPoint.y)
            if dist < clickRadiusPt && dist < bestDist {
                bestDist = dist
                bestState = entity.state
            }
        }

        if let state = bestState {
            MCLog.marker("GoogleMapMarkerController.handleTiledMarkerTap hit id=\(state.id) dist=\(bestDist)")
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
