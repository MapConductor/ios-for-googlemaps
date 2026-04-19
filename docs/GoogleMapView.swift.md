# GoogleMapView

`GoogleMapView` is a SwiftUI `View` that displays a Google Map. It provides a declarative way to
manage the map's state, handle user interactions, and draw overlays such as markers, polylines,
and polygons. The view is lifecycle-aware and integrates seamlessly with SwiftUI.

## Signature

```swift
public struct GoogleMapView: View {
    public init(
        state: GoogleMapViewState,
        onMapLoaded: OnMapLoadedHandler<GoogleMapViewState>? = nil,
        onMapClick: OnMapEventHandler? = nil,
        onCameraMoveStart: OnCameraMoveHandler? = nil,
        onCameraMove: OnCameraMoveHandler? = nil,
        onCameraMoveEnd: OnCameraMoveHandler? = nil,
        sdkInitialize: (() -> Void)? = nil,
        @MapViewContentBuilder content: @escaping () -> MapViewContent = { MapViewContent() }
    )
}
```

## Description

Renders a Google Map and manages its lifecycle. Serves as the root container for all map-related
UI, including overlays and controls. Map overlays such as markers and shapes are added
declaratively via the `content` result builder.

## Parameters

- `state`
    - Type: `GoogleMapViewState`
    - Description: **Required.** Manages the map's state, including camera position and map design
      type. Create an instance with `GoogleMapViewState()` and hold it with `@StateObject`.
- `onMapLoaded`
    - Type: `OnMapLoadedHandler<GoogleMapViewState>?`
    - Default: `nil`
    - Description: A callback invoked once the map has finished loading and is ready for
      interaction. Receives the `GoogleMapViewState` instance.
- `onMapClick`
    - Type: `OnMapEventHandler?`
    - Default: `nil`
    - Description: A callback invoked when the user taps on the map. Receives the `GeoPoint` of
      the tap location.
- `onCameraMoveStart`
    - Type: `OnCameraMoveHandler?`
    - Default: `nil`
    - Description: A callback invoked when the map camera begins moving. Receives the current
      `MapCameraPosition`.
- `onCameraMove`
    - Type: `OnCameraMoveHandler?`
    - Default: `nil`
    - Description: A callback invoked repeatedly while the map camera is moving. Receives the
      current `MapCameraPosition`.
- `onCameraMoveEnd`
    - Type: `OnCameraMoveHandler?`
    - Default: `nil`
    - Description: A callback invoked when the map camera finishes moving. Receives the final
      `MapCameraPosition`.
- `sdkInitialize`
    - Type: `(() -> Void)?`
    - Default: `nil`
    - Description: An optional closure to initialize the Google Maps SDK (e.g. call
      `GMSServices.provideAPIKey`). Called only once per app session regardless of how many
      `GoogleMapView` instances are created.
- `content`
    - Type: `@MapViewContentBuilder () -> MapViewContent`
    - Default: `{ MapViewContent() }` (empty)
    - Description: A result builder closure where map overlays are declared. Supports markers,
      polylines, polygons, circles, ground images, and raster layers.

## Example

```swift
import MapConductorForGoogleMaps
import SwiftUI

struct MyMapScreen: View {
    @StateObject private var mapState = GoogleMapViewState(
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 40.7128, longitude: -74.0060),
            zoom: 12.0
        )
    )

    var body: some View {
        GoogleMapView(
            state: mapState,
            sdkInitialize: {
                GMSServices.provideAPIKey("YOUR_API_KEY")
            },
            onMapClick: { geoPoint in
                print("Tapped at \(geoPoint.latitude), \(geoPoint.longitude)")
            }
        )
        .ignoresSafeArea()
    }
}
```
