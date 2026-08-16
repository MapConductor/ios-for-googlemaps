import Combine
import Foundation
import MapConductorCore

/// Google Maps の state。
///
/// カメラの保持と委譲、`uiSettings`、`id` はコアの ``MapViewState`` が持つ。
/// ここに残るのは **Google Maps 固有のもの**だけ:
///  - `mapDesignType`（プロバイダ固有の型）
///  - プロバイダ型のホルダーと、それを返す `getMapViewHolder()` の絞り込み
public final class GoogleMapViewState: MapViewState<GoogleMapDesignType> {
    @Published private var _mapDesignType: GoogleMapDesignType

    /// Provider-typed holder: `map`/`mapView` are `GMSMapView`, no cast needed.
    public private(set) var mapViewHolder: GoogleMapViewHolder?

    public override var mapDesignType: GoogleMapDesignType {
        get { _mapDesignType }
        set { _mapDesignType = newValue }
    }

    public init(
        id: String,
        mapDesignType: GoogleMapDesignType = GoogleMapDesign.Normal,
        cameraPosition: MapCameraPosition = .Default,
        uiSettings: MapUISettings = MapUISettings()
    ) {
        self._mapDesignType = mapDesignType
        super.init(id: id, initialCameraPosition: cameraPosition, uiSettings: uiSettings)
    }

    public convenience init(
        mapDesignType: GoogleMapDesignType = GoogleMapDesign.Normal,
        cameraPosition: MapCameraPosition = .Default,
        uiSettings: MapUISettings = MapUISettings()
    ) {
        self.init(id: UUID().uuidString, mapDesignType: mapDesignType, cameraPosition: cameraPosition, uiSettings: uiSettings)
    }

    /// アプリが `state.getMapViewHolder()?.map` でネイティブの地図を取れる形を保つための絞り込み。
    public override func getMapViewHolder() -> AnyMapViewHolder? {
        mapViewHolder.map { AnyMapViewHolder($0) }
    }

    func setController(_ controller: (any MapViewControllerProtocol)?) {
        attachController(controller)
    }

    func setMapViewHolder(_ holder: GoogleMapViewHolder?) {
        mapViewHolder = holder
    }

    func updateCameraPosition(_ cameraPosition: MapCameraPosition) {
        setCameraPositionInternal(cameraPosition)
    }
}
