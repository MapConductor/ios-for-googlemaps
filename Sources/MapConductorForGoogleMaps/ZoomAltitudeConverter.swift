import Foundation
import MapConductorCore

/// 統一ズーム（Google Maps 基準・256px タイル）⇄ 高度の変換。
///
/// Google Maps のネイティブズームは統一ズームそのものなのでオフセットは 0。
/// 換算式はコアの ``WebMercatorZoomAltitudeConverter`` にある。
public class GoogleMapsZoomAltitudeConverter: WebMercatorZoomAltitudeConverter {
    public init(zoom0Altitude: Double = AbstractZoomAltitudeConverter.defaultZoom0Altitude) {
        super.init(zoom0Altitude: zoom0Altitude, zoomOffset: 0.0)
    }
}
