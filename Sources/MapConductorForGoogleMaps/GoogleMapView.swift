import Combine
import GoogleMaps
import MapConductorCore
import SwiftUI
import UIKit

public struct GoogleMapView: View {
    @ObservedObject private var state: GoogleMapViewState
    private let handlers: MapViewHandlers<GoogleMapViewState>
    private let cameraRestriction: CameraRestriction?
    private let content: () -> MapViewContent

    public init(
        state: GoogleMapViewState,
        cameraRestriction: CameraRestriction? = nil,
        onMapLoaded: OnMapLoadedHandler<GoogleMapViewState>? = nil,
        onMapClick: OnMapEventHandler? = nil,
        onMapLongClick: OnMapEventHandler? = nil,
        onCameraMoveStart: OnCameraMoveHandler? = nil,
        onCameraMove: OnCameraMoveHandler? = nil,
        onCameraMoveEnd: OnCameraMoveHandler? = nil,
        sdkInitialize: (() -> Void)? = nil,
        @MapViewContentBuilder content: @escaping () -> MapViewContent = { MapViewContent() }
    ) {
        self.state = state
        self.handlers = MapViewHandlers(
            onMapLoaded: onMapLoaded,
            onMapClick: onMapClick,
            onMapLongClick: onMapLongClick,
            onCameraMoveStart: onCameraMoveStart,
            onCameraMove: onCameraMove,
            onCameraMoveEnd: onCameraMoveEnd,
            sdkInitialize: sdkInitialize
        )
        self.cameraRestriction = cameraRestriction
        self.content = content
    }

    public var body: some View {
        // The provider's registry is in scope only while content is being assembled —
        // the same window in which Compose provides `LocalMapServiceRegistry` around the
        // content lambda. Bracketing the pass lets a removed plugin be noticed.
        let support = state.serviceRegistry.get(MarkerRenderingSupportKey.self)
        support?.beginContentPass()
        let mapContent = MapServiceRegistryScope.with(state.serviceRegistry) { content() }
        support?.endContentPass()
        return MapViewBase(
            attributionRules: state.mapDesignType.attributionRules,
            camera: state.cameraPosition,
            content: mapContent
        ) {
            GoogleMapViewRepresentable(
                state: state,
                cameraRestriction: cameraRestriction,
                handlers: handlers,
                content: mapContent
            )
        }
    }
}

private final class GoogleMapWrapperView: UIView {
    let mapView: GMSMapView
    let overlayContainer: UIView

    init(mapView: GMSMapView, overlayContainer: UIView) {
        self.mapView = mapView
        self.overlayContainer = overlayContainer
        super.init(frame: .zero)

        addSubview(mapView)
        addSubview(overlayContainer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        mapView.frame = bounds
        overlayContainer.frame = bounds
    }
}

private struct GoogleMapViewRepresentable: UIViewRepresentable {
    @ObservedObject var state: GoogleMapViewState
    let cameraRestriction: CameraRestriction?
    let handlers: MapViewHandlers<GoogleMapViewState>
    let content: MapViewContent

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, handlers: handlers)
    }

    func makeUIView(context: Context) -> GoogleMapWrapperView {
        if let sdkInitialize = handlers.sdkInitialize {
            Coordinator.runOnce(sdkInitialize)
        }

        let camera = makeCamera(from: state.cameraPosition)
        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.mapType = state.mapDesignType.getValue()
        mapView.settings.scrollGestures = state.uiSettings.scrollGesture
        mapView.settings.zoomGestures = state.uiSettings.zoomGesture
        mapView.settings.rotateGestures = state.uiSettings.rotateGesture
        mapView.settings.tiltGestures = state.uiSettings.tiltGesture
        mapView.delegate = context.coordinator

        let wrapper = GoogleMapWrapperView(mapView: mapView, overlayContainer: context.coordinator.infoBubbleContainer)
        wrapper.backgroundColor = .clear

        context.coordinator.attachInfoBubbleContainer(to: wrapper)
        context.coordinator.mapView = mapView
        context.coordinator.bind(state: state, mapView: mapView)
        // android-for-googlemaps の GoogleMapView.kt がコントローラ生成直後に
        // setCameraRestriction するのと同じ位置。
        context.coordinator.applyCameraRestriction(cameraRestriction)
        // Ensure overlay controllers subscribe immediately (before the first updateUIView),
        // so early UI actions (e.g. tapping animation buttons) are not missed.
        MCLog.map("GoogleMapView.makeUIView updateContent markers=\(content.markers.count) bubbles=\(content.infoBubbles.count)")
        context.coordinator.updateContent(content)
        context.coordinator.updateInfoBubbleLayouts()
        return wrapper
    }

    func updateUIView(_ uiView: GoogleMapWrapperView, context: Context) {
        uiView.mapView.mapType = state.mapDesignType.getValue()
        // ジェスチャはここ（updateUIView）で直接適用する。SwiftUI の同期フックは常に
        // ネイティブビューを持っているのに対し、コントローラはまだ生成されていない／
        // まだ mapView を保持していないことがあり、その場合に設定が落ちる（実機の
        // UISettingsUITests が MapLibre/MapTiler/Mapbox で検出）。
        // コントローラ側の `applyUISettings` は android-sdk と同じ API を提供するための
        // 命令的な入口で、同じ値を同じネイティブプロパティへ書く。
        uiView.mapView.settings.scrollGestures = state.uiSettings.scrollGesture
        uiView.mapView.settings.zoomGestures = state.uiSettings.zoomGesture
        uiView.mapView.settings.rotateGestures = state.uiSettings.rotateGesture
        uiView.mapView.settings.tiltGestures = state.uiSettings.tiltGesture
        // 制限値が変わったときだけ再適用する（毎フレーム native API を叩かない）。
        context.coordinator.applyCameraRestriction(cameraRestriction)
        MCLog.map("GoogleMapView.updateUIView updateContent markers=\(content.markers.count) bubbles=\(content.infoBubbles.count)")
        context.coordinator.updateContent(content)
        context.coordinator.updateInfoBubbleLayouts()
    }

    static func dismantleUIView(_ uiView: GoogleMapWrapperView, coordinator: Coordinator) {
        coordinator.unbind()
        uiView.mapView.delegate = nil
    }

    private func makeCamera(from camera: MapCameraPosition) -> GMSCameraPosition {
        camera.toCameraPosition()
    }

    @MainActor
    final class Coordinator: MapViewCoordinatorBase<GoogleMapViewState>, GMSMapViewDelegate {
        weak var mapView: GMSMapView?
        // updateUIView から applyUISettings を呼ぶため private を外している。
        private(set) var controller: GoogleMapViewController?

        /// android-sdk の `cameraRestriction?.let { controller.setCameraRestriction(it) }` 相当。
        /// 変化検知は `MapViewCoordinatorBase.applyCameraRestriction(_:to:)` が行う。
        func applyCameraRestriction(_ restriction: CameraRestriction?) {
            applyCameraRestriction(restriction, to: controller)
        }
        private var markerController: GoogleMapMarkerController?
        private var groundImageController: GoogleMapGroundImageController?
        private var rasterController: GoogleMapRasterLayerController?
        private var circleController: GoogleMapCircleController?
        private var polylineController: GoogleMapPolylineController?
        private var polygonController: GoogleMapPolygonController?
        private var hullPolygonController: GoogleMapPolygonController?
        private var overlayScope: MapOverlayScope?
        private var infoBubbleCoordinator: InfoBubbleOverlayCoordinator?
        private lazy var strategyManager = StrategyMarkerManager<GMSMarker, GoogleMapMarkerRenderer>(
            makeRenderer: { [weak self] strategy in
                guard let mapView = self?.mapView else { fatalError("mapView unavailable") }
                return GoogleMapMarkerRenderer(mapView: mapView, markerManager: strategy.markerManager)
            },
            currentCamera: { [weak self] in
                guard let self, let mapView = self.mapView else { return nil }
                return self.currentCameraPosition(from: mapView)
            }
        )

        func bind(state: GoogleMapViewState, mapView: GMSMapView) {
            // Publish marker rendering as a map-scoped capability. Add-on modules resolve it
            // from the registry; this provider never learns that clustering exists.
            state.serviceRegistry.put(MarkerRenderingSupportKey.self, strategyManager)

            let controller = GoogleMapViewController(mapView: mapView)
            self.controller = controller
            state.setController(controller)
            // 拡張モジュール（ヒートマップ等）がオーバーレイコントローラを登録できるようにする。
            state.serviceRegistry.put(OverlayControllerRegistryKey.self, controller.overlayControllers)
            state.setMapViewHolder(controller.typedHolder)

            let markerController = GoogleMapMarkerController(mapView: mapView) { [weak self] id in
                self?.infoBubbleCoordinator?.updateInfoBubblePosition(for: id)
            }
            self.markerController = markerController

            let groundImageController = GoogleMapGroundImageController(mapView: mapView)
            self.groundImageController = groundImageController

            let rasterController = GoogleMapRasterLayerController(mapView: mapView)
            self.rasterController = rasterController

            let polylineController = GoogleMapPolylineController(mapView: mapView)
            self.polylineController = polylineController

            let polygonController = GoogleMapPolygonController(mapView: mapView)
            self.polygonController = polygonController
            self.hullPolygonController = GoogleMapPolygonController(mapView: mapView)

            let circleController = GoogleMapCircleController(mapView: mapView)
            self.circleController = circleController

            // Route the simple overlays through the shared collector so each
            // controller subscribes to one source of truth instead of the map
            // host re-diffing arrays every render.
            let overlayScope = MapOverlayScope()
            self.overlayScope = overlayScope
            bindOverlayCollector(overlayScope.circleCollector, to: circleController)
            bindOverlayCollector(overlayScope.polylineCollector, to: polylineController)
            bindOverlayCollector(overlayScope.polygonCollector, to: polygonController)
            bindOverlayCollector(overlayScope.rasterLayerCollector, to: rasterController)
            bindOverlayCollector(overlayScope.groundImageCollector, to: groundImageController)

            self.infoBubbleCoordinator = InfoBubbleOverlayCoordinator(
                container: infoBubbleContainer,
                project: { [weak self] point in
                    guard let mapView = self?.mapView else { return nil }
                    let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                    return mapView.projection.point(for: coordinate)
                },
                projectionGate: screenProjectionGate(feature: "InfoBubble"),
                resolveMarkerStateForIcon: { [weak markerController] id, bubbleMarker in
                    markerController?.getMarkerState(for: id) ?? bubbleMarker
                },
                iconMetrics: { [weak markerController] markerState in
                    let icon = markerController?.getIcon(for: markerState) ?? (markerState.icon ?? DefaultMarkerIcon()).toBitmapIcon()
                    return MarkerIconMetrics(size: icon.size, anchor: icon.anchor, infoAnchor: icon.infoAnchor)
                }
            )

            // Screen-space marker animation layer: shares the info-bubble
            // container (inserted below the bubbles) and the same projection.
            markerController.renderer.animationOverlay = MarkerAnimationOverlayCoordinator(
                container: infoBubbleContainer,
                project: { [weak self] point in
                    guard let mapView = self?.mapView else { return nil }
                    let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
                    return mapView.projection.point(for: coordinate)
                },
                projectionGate: screenProjectionGate(feature: "marker animation overlay")
            )
        }

        func unbind() {
            // 登録した capability を取り下げる。レジストリの持ち主は state で、ビューより長生きするため、
            // ここで外さないと破棄済みのコントローラを掴んだまま残る。
            state.serviceRegistry.removeProviderRegistrations()
            // 登録済みオーバーレイコントローラ（拡張モジュール含む）を破棄する。
            controller?.destroy()
            state.setController(nil)
            state.setMapViewHolder(nil)
            controller = nil
            markerController?.renderer.animationOverlay?.unbind()
            markerController?.renderer.animationOverlay = nil
            markerController?.unbind()
            markerController = nil
            groundImageController?.unbind()
            groundImageController = nil
            rasterController?.unbind()
            rasterController = nil
            polylineController?.unbind()
            polylineController = nil
            polygonController?.unbind()
            polygonController = nil
            hullPolygonController?.unbind()
            hullPolygonController = nil
            circleController?.unbind()
            circleController = nil
            overlayScope?.clear()
            overlayScope = nil
            infoBubbleCoordinator?.unbind()
            infoBubbleCoordinator = nil
            strategyManager.clear()
        }

        func updateContent(_ content: MapViewContent) {
            if let mapView {
                polylineController?.setCurrentCameraPosition(currentCameraPosition(from: mapView))
            }
            infoBubbleCoordinator?.syncInfoBubbles(content.infoBubbles)
            markerController?.tilingOptions = content.markerTilingOptions
            markerController?.syncMarkers(content.markers)
            overlayScope?.circleCollector.sync(content.circles.map { $0.state })
            overlayScope?.polylineCollector.sync(content.polylines.map { $0.state })
            overlayScope?.polygonCollector.sync(content.polygons.map { $0.state })
            overlayScope?.rasterLayerCollector.sync(content.rasterLayers.map { $0.state })
            overlayScope?.groundImageCollector.sync(content.groundImages.map { $0.state })
            for handler in content.polygonSyncHandlers {
                let hullController = hullPolygonController
                handler.bindPolygonSync { [weak hullController] states in
                    await hullController?.add(data: states)
                }
            }
            infoBubbleCoordinator?.updateAllLayouts()
        }

        // MARK: - GMSMapViewDelegate

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            polylineController?.setCurrentCameraPosition(currentCameraPosition(from: mapView))
            // Tile-rendered markers have no native tap event; hit-test them by screen proximity.
            let screenPoint = mapView.projection.point(for: coordinate)
            if markerController?.handleTiledMarkerTap(at: screenPoint) == true {
                return
            }
            if circleController?.handleTap(at: coordinate) == true {
                return
            }
            if polylineController?.handleTap(at: coordinate) == true {
                return
            }
            if polygonController?.handleTap(at: coordinate) == true {
                return
            }
            if groundImageController?.handleTap(at: coordinate) == true {
                return
            }
            let point = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
            controller?.notifyMapClick(point)
            onMapClick?(point)
        }

        func mapView(_ mapView: GMSMapView, didLongPressAt coordinate: CLLocationCoordinate2D) {
            let point = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
            controller?.notifyMapLongClick(point)
            onMapLongClick?(point)
        }

        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            let camera = currentCameraPosition(from: mapView)
            controller?.notifyCameraMoveStart(camera)
            onCameraMoveStart?(camera)
            Task { [weak self] in
                await self?.rasterController?.onCameraChanged(mapCameraPosition: camera)
                await self?.polylineController?.onCameraChanged(mapCameraPosition: camera)
                await self?.strategyManager.onCameraChanged(camera)
            }
            updateInfoBubbleLayouts()
        }

        func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
            let camera = currentCameraPosition(from: mapView)
            state.updateCameraPosition(camera)
            controller?.notifyCameraMove(camera)
            onCameraMove?(camera)
            Task { [weak self] in
                await self?.rasterController?.onCameraChanged(mapCameraPosition: camera)
                await self?.polylineController?.onCameraChanged(mapCameraPosition: camera)
                await self?.strategyManager.onCameraChanged(camera)
            }
            updateInfoBubbleLayouts()
        }

        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            let camera = currentCameraPosition(from: mapView)
            state.updateCameraPosition(camera)
            controller?.notifyCameraMoveEnd(camera)
            onCameraMoveEnd?(camera)
            Task { [weak self] in
                await self?.rasterController?.onCameraChanged(mapCameraPosition: camera)
                await self?.polylineController?.onCameraChanged(mapCameraPosition: camera)
                await self?.strategyManager.onCameraChanged(camera)
            }
            updateInfoBubbleLayouts()

            performMapLoadedOnce {
                controller?.notifyMapInitialized()
                onMapLoaded?(state)
            }
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let id = marker.userData as? String else { return true }
            if let state = markerController?.getMarkerState(for: id) {
                markerController?.dispatchClick(state: state)
            } else if let state = strategyManager.controller?.markerManager.getEntity(id)?.state {
                strategyManager.controller?.dispatchClick(state)
            }
            return true
        }

        func mapView(_ mapView: GMSMapView, didBeginDragging marker: GMSMarker) {
            guard let id = marker.userData as? String else { return }
            let state = markerController?.getMarkerState(for: id) ??
                strategyManager.controller?.markerManager.getEntity(id)?.state
            guard let state else { return }
            state.position = GeoPoint(
                latitude: marker.position.latitude,
                longitude: marker.position.longitude,
                altitude: 0
            )
            infoBubbleCoordinator?.updateInfoBubblePosition(for: id)
            if markerController?.getMarkerState(for: id) != nil {
                markerController?.dispatchDragStart(state: state)
            } else {
                strategyManager.controller?.dispatchDragStart(state)
            }
        }

        func mapView(_ mapView: GMSMapView, didDrag marker: GMSMarker) {
            guard let id = marker.userData as? String else { return }
            let state = markerController?.getMarkerState(for: id) ??
                strategyManager.controller?.markerManager.getEntity(id)?.state
            guard let state else { return }
            state.position = GeoPoint(
                latitude: marker.position.latitude,
                longitude: marker.position.longitude,
                altitude: 0
            )
            infoBubbleCoordinator?.updateInfoBubblePosition(for: id)
            if markerController?.getMarkerState(for: id) != nil {
                markerController?.dispatchDrag(state: state)
            } else {
                strategyManager.controller?.dispatchDrag(state)
            }
        }

        func mapView(_ mapView: GMSMapView, didEndDragging marker: GMSMarker) {
            guard let id = marker.userData as? String else { return }
            let state = markerController?.getMarkerState(for: id) ??
                strategyManager.controller?.markerManager.getEntity(id)?.state
            guard let state else { return }
            state.position = GeoPoint(
                latitude: marker.position.latitude,
                longitude: marker.position.longitude,
                altitude: 0
            )
            infoBubbleCoordinator?.updateInfoBubblePosition(for: id)
            if markerController?.getMarkerState(for: id) != nil {
                markerController?.dispatchDragEnd(state: state)
            } else {
                strategyManager.controller?.dispatchDragEnd(state)
            }
        }

        func mapView(_ mapView: GMSMapView, markerInfoContents marker: GMSMarker) -> UIView? {
            nil
        }

        // MARK: - Helper Methods

        private func currentCameraPosition(from mapView: GMSMapView) -> MapCameraPosition {
            let camera = mapView.camera
            let region = mapView.projection.visibleRegion()
            let bounds = GMSCoordinateBounds(region: region)
            let visibleRegion = VisibleRegion(
                bounds: GeoRectBounds(
                    southWest: GeoPoint(
                        latitude: bounds.southWest.latitude,
                        longitude: bounds.southWest.longitude,
                        altitude: 0
                    ),
                    northEast: GeoPoint(
                        latitude: bounds.northEast.latitude,
                        longitude: bounds.northEast.longitude,
                        altitude: 0
                    )
                ),
                nearLeft: GeoPoint(
                    latitude: region.nearLeft.latitude,
                    longitude: region.nearLeft.longitude,
                    altitude: 0
                ),
                nearRight: GeoPoint(
                    latitude: region.nearRight.latitude,
                    longitude: region.nearRight.longitude,
                    altitude: 0
                ),
                farLeft: GeoPoint(
                    latitude: region.farLeft.latitude,
                    longitude: region.farLeft.longitude,
                    altitude: 0
                ),
                farRight: GeoPoint(
                    latitude: region.farRight.latitude,
                    longitude: region.farRight.longitude,
                    altitude: 0
                )
            )
            return camera.toMapCameraPosition(
                logicalTiltHint: controller?.lastLogicalTilt,
                visibleRegion: visibleRegion
            )
        }

        fileprivate func updateInfoBubbleLayouts() {
            infoBubbleCoordinator?.updateAllLayouts()
        }
    }
}
