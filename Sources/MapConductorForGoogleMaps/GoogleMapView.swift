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

final class GoogleMapWrapperView: UIView {
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

    func makeCoordinator() -> GoogleMapHost {
        GoogleMapHost(state: state, handlers: handlers)
    }
    func makeUIView(context: Context) -> GoogleMapWrapperView {
        context.coordinator.makeWrapperView(cameraRestriction: cameraRestriction, content: content)
    }

    func updateUIView(_ uiView: GoogleMapWrapperView, context: Context) {
        context.coordinator.syncNativeViewSettings(cameraRestriction: cameraRestriction)
        MCLog.map("GoogleMapView.updateUIView updateContent markers=\(content.markers.count) bubbles=\(content.infoBubbles.count)")
        context.coordinator.updateContent(content)
        context.coordinator.updateInfoBubbleLayouts()
    }

    static func dismantleUIView(_ uiView: GoogleMapWrapperView, coordinator: GoogleMapHost) {
        coordinator.unbind()
        uiView.mapView.delegate = nil
    }
}
