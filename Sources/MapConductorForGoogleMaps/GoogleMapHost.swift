import Foundation
import GoogleMaps
import MapConductorCore
import UIKit

/// 地図一式（`GMSMapView` + コントローラ群 + オーバーレイ結線）を保持するホスト。
///
/// SwiftUI の `UIViewRepresentable.Coordinator` としても、React Native のように
/// SwiftUI を介さないホストからも同じものを使える。android-for-googlemaps の
/// `createGoogleMapViewController` に対応し、`GoogleMapView` はこの薄いラッパー。
///
/// アプリ開発者向けの API ではないので `@_spi(MapConductorDriver)` を付ける。
@_spi(MapConductorDriver)
@MainActor
public final class GoogleMapHost: MapViewCoordinatorBase<GoogleMapViewState>, GMSMapViewDelegate {
    public private(set) weak var mapView: GMSMapView?
    // updateUIView から applyUISettings を呼ぶため private を外している。
    private(set) var controller: GoogleMapViewController?

    /// android-sdk の `cameraRestriction?.let { controller.setCameraRestriction(it) }` 相当。
    /// 変化検知は `MapViewCoordinatorBase.applyCameraRestriction(_:to:)` が行う。
    public func applyCameraRestriction(_ restriction: CameraRestriction?) {
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
        // クリックカスケードとスロット解決がここから kind で引く。
        // **登録を忘れるとタップに反応しなくなる。**
        controller.registerOverlayController(markerController)
        controller.registerOverlayController(circleController)
        controller.registerOverlayController(polylineController)
        controller.registerOverlayController(polygonController)
        controller.registerOverlayController(groundImageController)
        controller.registerOverlayController(rasterController)

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

    public func unbind() {
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

    public func updateContent(_ content: MapViewContent) {
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


    /// 非 SwiftUI ホスト向け。`UIView` として返す（`GoogleMapWrapperView` はモジュール内部型）。
    public func makeMapView(cameraRestriction: CameraRestriction?, content: MapViewContent) -> UIView {
        makeWrapperView(cameraRestriction: cameraRestriction, content: content)
    }

    /// `updateUIView` のうちネイティブビューへ直接書く分。非 SwiftUI ホストは state を変えたあとに呼ぶ。
    public func syncNativeViewSettings(cameraRestriction: CameraRestriction? = nil) {
        guard let mapView else { return }
        mapView.mapType = state.mapDesignType.getValue()
        mapView.settings.scrollGestures = state.uiSettings.scrollGesture
        mapView.settings.zoomGestures = state.uiSettings.zoomGesture
        mapView.settings.rotateGestures = state.uiSettings.rotateGesture
        mapView.settings.tiltGestures = state.uiSettings.tiltGesture
        applyCameraRestriction(cameraRestriction)
    }

    private func makeCamera(from camera: MapCameraPosition) -> GMSCameraPosition {
        camera.toCameraPosition()
    }

    /// 地図の組み立て手順。SwiftUI の `makeUIView` から移したもの。
    func makeWrapperView(cameraRestriction: CameraRestriction?, content: MapViewContent) -> GoogleMapWrapperView {
        if let sdkInitialize = handlers.sdkInitialize {
            Self.runOnce(sdkInitialize)
        }

        let camera = makeCamera(from: state.cameraPosition)
        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.mapType = state.mapDesignType.getValue()
        mapView.settings.scrollGestures = state.uiSettings.scrollGesture
        mapView.settings.zoomGestures = state.uiSettings.zoomGesture
        mapView.settings.rotateGestures = state.uiSettings.rotateGesture
        mapView.settings.tiltGestures = state.uiSettings.tiltGesture
        mapView.delegate = self

        let wrapper = GoogleMapWrapperView(mapView: mapView, overlayContainer: infoBubbleContainer)
        wrapper.backgroundColor = .clear

        attachInfoBubbleContainer(to: wrapper)
        self.mapView = mapView
        bind(state: state, mapView: mapView)
        // android-for-googlemaps の GoogleMapView.kt がコントローラ生成直後に
        // setCameraRestriction するのと同じ位置。
        applyCameraRestriction(cameraRestriction)
        // Ensure overlay controllers subscribe immediately (before the first updateUIView),
        // so early UI actions (e.g. tapping animation buttons) are not missed.
        MCLog.map("GoogleMapHost.makeMapView updateContent markers=\(content.markers.count) bubbles=\(content.infoBubbles.count)")
        updateContent(content)
        updateInfoBubbleLayouts()
        return wrapper
    }

    // MARK: - GMSMapViewDelegate

    public func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
        polylineController?.setCurrentCameraPosition(currentCameraPosition(from: mapView))
        // Tile-rendered markers have no native tap event; hit-test them by screen proximity.
        let screenPoint = mapView.projection.point(for: coordinate)
        if markerController?.handleTiledMarkerTap(at: screenPoint) == true {
            return
        }
        let point = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        // circle → groundImage → polyline → polygon の一本道。
        // 順序と先勝ちはコアの dispatchOverlayTap が持つ。
        // 移行前はここで circle → polyline → polygon → groundImage の独自順だった。
        if controller?.dispatchOverlayTap(position: point) == true {
            return
        }
        controller?.notifyMapClick(point)
        onMapClick?(point)
    }

    public func mapView(_ mapView: GMSMapView, didLongPressAt coordinate: CLLocationCoordinate2D) {
        let point = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        controller?.notifyMapLongClick(point)
        onMapLongClick?(point)
    }

    public func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
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

    public func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
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

    public func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
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

    public func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
        guard let id = marker.userData as? String else { return true }
        if let state = markerController?.getMarkerState(for: id) {
            markerController?.dispatchClick(state: state)
        } else if let state = strategyManager.controller?.markerManager.getEntity(id)?.state {
            strategyManager.controller?.dispatchClick(state)
        }
        return true
    }

    public func mapView(_ mapView: GMSMapView, didBeginDragging marker: GMSMarker) {
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

    public func mapView(_ mapView: GMSMapView, didDrag marker: GMSMarker) {
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

    public func mapView(_ mapView: GMSMapView, didEndDragging marker: GMSMarker) {
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

    public func mapView(_ mapView: GMSMapView, markerInfoContents marker: GMSMarker) -> UIView? {
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

    public func updateInfoBubbleLayouts() {
        infoBubbleCoordinator?.updateAllLayouts()
    }
}
