import CoreLocation
import GoogleMaps
@_spi(MapConductorDriver) import MapConductorCore
import QuartzCore

final class GoogleMapViewController: MapViewControllerProtocol {
    let holder: AnyMapViewHolder
    let typedHolder: GoogleMapViewHolder
    let coroutine = CoroutineScope()

    /// この地図に紐づくオーバーレイコントローラの登録簿。
    /// 拡張モジュール（ヒートマップ、マーカークラスタリング等）がここに登録して
    /// カメラ変更を受け取る。`MapViewControllerProtocol` の要件。
    let overlayControllers = OverlayControllerRegistry()
    private weak var mapView: GMSMapView?
    private(set) var lastLogicalTilt: Double?
    /// 最後に指定されたパディング。パディングは地図に当てず、カメラの中心をずらして
    /// 再現し（``CameraPaddingEmulation``）、読み戻しで逆にずらすときに使う。
    /// android-for-googlemaps と同じく `GMSMapView.padding` は使わない（ロゴやコントロールまで
    /// 動き、アニメーションの最初でパディングだけが一気に切り替わるため）。
    private(set) var lastPaddings: MapPaddingsProtocol?

    private var cameraMoveStartListener: OnCameraMoveHandler?
    private var cameraMoveListener: OnCameraMoveHandler?
    private var cameraMoveEndListener: OnCameraMoveHandler?
    private var mapClickListener: OnMapEventHandler?
    private var mapLongClickListener: OnMapEventHandler?
    private var mapInitializedListener: OnMapInitializedHandler?

    init(mapView: GMSMapView) {
        self.mapView = mapView
        let typedHolder = GoogleMapViewHolder(mapView: mapView)
        self.typedHolder = typedHolder
        self.holder = AnyMapViewHolder(typedHolder)
    }

    /// ``clearOverlays()`` の中身。オーバーレイのコントローラはホストが持っているので、
    /// ホストが生成時に設定する（android-sdk と同じく、各コントローラの `clear()` を呼ぶ）。
    var clearOverlaysHandler: (@MainActor () async -> Void)?

    func clearOverlays() async {
        await clearOverlaysHandler?()
    }

    func setCameraMoveStartListener(listener: OnCameraMoveHandler?) {
        cameraMoveStartListener = listener
    }

    func setCameraMoveListener(listener: OnCameraMoveHandler?) {
        cameraMoveListener = listener
    }

    func setCameraMoveEndListener(listener: OnCameraMoveHandler?) {
        cameraMoveEndListener = listener
    }

    func setMapClickListener(listener: OnMapEventHandler?) {
        mapClickListener = listener
    }

    func setMapLongClickListener(listener: OnMapEventHandler?) {
        mapLongClickListener = listener
    }

    func setMapInitializedListener(listener: OnMapInitializedHandler?) {
        mapInitializedListener = listener
    }

    func moveCamera(position: MapCameraPosition) {
        guard let mapView = mapView else { return }
        lastLogicalTilt = position.tilt
        if let paddings = position.paddings { lastPaddings = paddings }
        let requested = position.copy(paddings: lastPaddings ?? MapPaddings.Zeros)
        let camera = paddingApplied(requested).toCameraPosition()
        mapView.moveCamera(GMSCameraUpdate.setCamera(camera))
        scheduleCorrection(requested)
    }

    func animateCamera(position: MapCameraPosition, duration: Long) {
        guard let mapView = mapView else { return }
        lastLogicalTilt = position.tilt
        if let paddings = position.paddings { lastPaddings = paddings }
        let requested = position.copy(paddings: lastPaddings ?? MapPaddings.Zeros)
        let camera = paddingApplied(requested).toCameraPosition()
        let update = GMSCameraUpdate.setCamera(camera)
        CATransaction.begin()
        CATransaction.setAnimationDuration(Double(duration) / 1000.0)
        CATransaction.setCompletionBlock { [weak self] in
            self?.scheduleCorrection(requested)
        }
        mapView.animate(with: update)
        CATransaction.commit()
    }

    /// Google Maps へ渡すカメラ。パディングの分だけ中心をずらす。
    private func paddingApplied(_ position: MapCameraPosition) -> MapCameraPosition {
        CameraPaddingEmulation.applied(
            to: position,
            fov: googleMapsVerticalFieldOfView,
            viewportSize: mapView?.bounds.size ?? .zero
        )
    }

    /// 補正の世代。新しい移動が始まったら、前の移動の補正は捨てる。
    private var correctionGeneration = 0

    /// 補正は地図がカメラを描き終えてから測る（moveCamera の直後は投影がまだ古い）。
    private func scheduleCorrection(_ requested: MapCameraPosition) {
        correctionGeneration += 1
        let generation = correctionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.correctPaddedTarget(requested, generation: generation)
        }
    }

    /// 計算で置いた中心は、Google Maps の tilt の上限（ズームによって 60° より小さい）や
    /// 縮尺の丸めでずれる。地図の投影で実際の位置を測り、パディングの残りの中央に来るまで
    /// 中心だけを動かし直す。1 回ごとに反映を待ってから測り直す。
    private func correctPaddedTarget(_ requested: MapCameraPosition, generation: Int, remaining: Int = 4) {
        guard remaining > 0, generation == correctionGeneration, let mapView else { return }
        // GMSMapView はカメラの中心を安全領域の内側の中央に置く（ビューの中央とは限らない）。
        // ずれは「いまのカメラの中心が描かれている位置」から測って打ち消す。
        let projection = mapView.projection
        guard let desired = CameraPaddingEmulation.paddedCenterPoint(
            paddings: requested.paddings,
            viewportSize: mapView.bounds.size
        ) else { return }
        let actual = projection.point(for: CLLocationCoordinate2D(
            latitude: requested.position.latitude,
            longitude: requested.position.longitude
        ))
        let deltaX = actual.x - desired.x
        let deltaY = actual.y - desired.y
        guard abs(deltaX) >= 0.5 || abs(deltaY) >= 0.5 else { return }
        let currentCenter = projection.point(for: mapView.camera.target)
        let center = projection.coordinate(for: CGPoint(x: currentCenter.x + deltaX, y: currentCenter.y + deltaY))
        mapView.moveCamera(GMSCameraUpdate.setTarget(
            CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude)
        ))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.correctPaddedTarget(requested, generation: generation, remaining: remaining - 1)
        }
    }

    func setCameraRestriction(_ restriction: CameraRestriction?) {
        guard let mapView = mapView else { return }
        // Google Maps の統一ズームはネイティブズームそのものなので変換不要
        // （android-for-googlemaps と同一仕様）。
        if let sw = restriction?.bounds?.southWest, let ne = restriction?.bounds?.northEast {
            mapView.cameraTargetBounds = GMSCoordinateBounds(
                coordinate: CLLocationCoordinate2D(latitude: sw.latitude, longitude: sw.longitude),
                coordinate: CLLocationCoordinate2D(latitude: ne.latitude, longitude: ne.longitude)
            )
        } else {
            mapView.cameraTargetBounds = nil
        }
        // preference をクリアするには下限/上限に既定値を渡す必要があるため、
        // 未指定時は kGMSMinZoomLevel / kGMSMaxZoomLevel へ戻す。
        mapView.setMinZoom(
            Float(restriction?.minZoom ?? Double(kGMSMinZoomLevel)),
            maxZoom: Float(restriction?.maxZoom ?? Double(kGMSMaxZoomLevel))
        )
    }

    func fitBounds(bounds: GeoRectBounds, padding: Int) {
        guard let mapView = mapView,
              let sw = bounds.southWest,
              let ne = bounds.northEast else { return }
        let coordinateBounds = GMSCoordinateBounds(
            coordinate: CLLocationCoordinate2D(latitude: sw.latitude, longitude: sw.longitude),
            coordinate: CLLocationCoordinate2D(latitude: ne.latitude, longitude: ne.longitude)
        )
        let update = GMSCameraUpdate.fit(coordinateBounds, withPadding: CGFloat(padding))
        mapView.moveCamera(update)
    }

    func notifyCameraMoveStart(_ cameraPosition: MapCameraPosition) {
        cameraMoveStartListener?(cameraPosition)
    }

    func notifyCameraMove(_ cameraPosition: MapCameraPosition) {
        cameraMoveListener?(cameraPosition)
    }

    func notifyCameraMoveEnd(_ cameraPosition: MapCameraPosition) {
        // 登録済みオーバーレイ（拡張モジュール含む）へ伝播する。
        overlayControllers.dispatchCameraChanged(cameraPosition)
        cameraMoveEndListener?(cameraPosition)
    }

    func notifyMapClick(_ point: GeoPoint) {
        mapClickListener?(point)
    }

    func notifyMapLongClick(_ point: GeoPoint) {
        mapLongClickListener?(point)
    }

    func notifyMapInitialized() {
        mapInitializedListener?(.MapCreated)
    }

    /// ジェスチャの ON/OFF を地図へ適用する。
    /// android-sdk の `applyUISettings(settings:)` と同じ位置づけ。
    /// 初回適用はビュー生成時（`makeUIView`）に行い、以降の変更がここを通る。
    func applyUISettings(_ settings: MapUISettings) {
        guard let mapView else { return }
        mapView.settings.scrollGestures = settings.scrollGesture
        mapView.settings.zoomGestures = settings.zoomGesture
        mapView.settings.rotateGestures = settings.rotateGesture
        mapView.settings.tiltGestures = settings.tiltGesture
    }

}
