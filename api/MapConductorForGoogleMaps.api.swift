import Combine
import CoreGraphics
import CoreLocation
import Foundation
import GoogleMaps
import MapConductorCore
import QuartzCore
import Swift
import SwiftUI
import UIKit
import _Concurrency
import _StringProcessing
import _SwiftConcurrencyShims
public protocol GoogleMapDesignTypeProtocol : MapConductorCore.MapDesignTypeProtocol where Self.Identifier == GoogleMaps.GMSMapViewType {
}
public typealias GoogleMapDesignType = any MapConductorForGoogleMaps.GoogleMapDesignTypeProtocol
public struct GoogleMapDesign : MapConductorForGoogleMaps.GoogleMapDesignTypeProtocol, Swift.Hashable {
  public let id: GoogleMaps.GMSMapViewType
  public let attributionRules: [MapConductorCore.AttributionRule]
  public init(id: GoogleMaps.GMSMapViewType, attributionRules: [MapConductorCore.AttributionRule] = [])
  public func getValue() -> GoogleMaps.GMSMapViewType
  public static let Normal: MapConductorForGoogleMaps.GoogleMapDesign
  public static let Satellite: MapConductorForGoogleMaps.GoogleMapDesign
  public static let Hybrid: MapConductorForGoogleMaps.GoogleMapDesign
  public static let Terrain: MapConductorForGoogleMaps.GoogleMapDesign
  public static let None: MapConductorForGoogleMaps.GoogleMapDesign
  public static func Create(id: GoogleMaps.GMSMapViewType) -> MapConductorForGoogleMaps.GoogleMapDesign
  public static func toMapDesignType(id: GoogleMaps.GMSMapViewType) -> MapConductorForGoogleMaps.GoogleMapDesignType
  public static func == (a: MapConductorForGoogleMaps.GoogleMapDesign, b: MapConductorForGoogleMaps.GoogleMapDesign) -> Swift.Bool
  public typealias Identifier = GoogleMaps.GMSMapViewType
  public func hash(into hasher: inout Swift.Hasher)
  public var hashValue: Swift.Int {
    get
  }
}
public typealias GoogleMapActualMarker = GoogleMaps.GMSMarker
public typealias GoogleMapActualCircle = GoogleMaps.GMSCircle
public typealias GoogleMapActualPolyline = GoogleMaps.GMSPolyline
public typealias GoogleMapActualPolygon = GoogleMaps.GMSPolygon
public typealias GoogleMapActualGroundImage = GoogleMaps.GMSGroundOverlay
public typealias GoogleMapActualRasterLayer = GoogleMaps.GMSURLTileLayer
@_Concurrency.MainActor @preconcurrency public struct GoogleMapView : SwiftUICore.View {
  @_Concurrency.MainActor @preconcurrency public init(state: MapConductorForGoogleMaps.GoogleMapViewState, cameraRestriction: MapConductorCore.CameraRestriction? = nil, onMapLoaded: MapConductorCore.OnMapLoadedHandler<MapConductorForGoogleMaps.GoogleMapViewState>? = nil, onMapClick: MapConductorCore.OnMapEventHandler? = nil, onMapLongClick: MapConductorCore.OnMapEventHandler? = nil, onCameraMoveStart: MapConductorCore.OnCameraMoveHandler? = nil, onCameraMove: MapConductorCore.OnCameraMoveHandler? = nil, onCameraMoveEnd: MapConductorCore.OnCameraMoveHandler? = nil, sdkInitialize: (() -> Swift.Void)? = nil, @MapConductorCore.MapViewContentBuilder content: @escaping () -> MapConductorCore.MapViewContent = { MapViewContent() })
  @_Concurrency.MainActor @preconcurrency public var body: some SwiftUICore.View {
    get
  }
  public typealias Body = @_opaqueReturnTypeOf("$s25MapConductorForGoogleMaps0dA4ViewV4bodyQrvp", 0) __
}
final public class GoogleMapViewState : MapConductorCore.MapViewState<MapConductorForGoogleMaps.GoogleMapDesignType> {
  final public var mapViewHolder: MapConductorForGoogleMaps.GoogleMapViewHolder? {
    get
  }
  override final public var mapDesignType: MapConductorForGoogleMaps.GoogleMapDesignType {
    get
    set
  }
  public init(id: Swift.String, mapDesignType: MapConductorForGoogleMaps.GoogleMapDesignType = GoogleMapDesign.Normal, cameraPosition: MapConductorCore.MapCameraPosition = .Default, uiSettings: MapConductorCore.MapUISettings = MapUISettings())
  convenience public init(mapDesignType: MapConductorForGoogleMaps.GoogleMapDesignType = GoogleMapDesign.Normal, cameraPosition: MapConductorCore.MapCameraPosition = .Default, uiSettings: MapConductorCore.MapUISettings = MapUISettings())
  override final public func getMapViewHolder() -> MapConductorCore.AnyMapViewHolder?
  @objc deinit
}
extension MapConductorCore.MapCameraPosition {
  final public func toCameraPosition() -> GoogleMaps.GMSCameraPosition
}
extension GoogleMaps.GMSCameraPosition {
  public func toMapCameraPosition(logicalTiltHint: Swift.Double? = nil, visibleRegion: MapConductorCore.VisibleRegion? = nil) -> MapConductorCore.MapCameraPosition
}
public class GoogleMapsZoomAltitudeConverter : MapConductorCore.WebMercatorZoomAltitudeConverter {
  public init(zoom0Altitude: Swift.Double = AbstractZoomAltitudeConverter.defaultZoom0Altitude)
  @objc deinit
}
@_hasMissingDesignatedInitializers final public class GoogleMapViewHolder : MapConductorCore.MapViewHolderProtocol {
  final public let mapView: GoogleMaps.GMSMapView
  final public let map: GoogleMaps.GMSMapView
  final public func toScreenOffset(position: any MapConductorCore.GeoPointProtocol) -> CoreFoundation.CGPoint?
  final public func fromScreenOffsetSync(offset: CoreFoundation.CGPoint) -> MapConductorCore.GeoPoint?
  public typealias ActualMap = GoogleMaps.GMSMapView
  public typealias ActualMapView = GoogleMaps.GMSMapView
  @objc deinit
}
extension MapConductorForGoogleMaps.GoogleMapView : Swift.Sendable {}
