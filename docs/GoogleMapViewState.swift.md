# GoogleMapViewState

`GoogleMapViewState` manages the state of a `GoogleMapView`, including the camera position and the
map design type. It is an `ObservableObject` — changes to its published properties automatically
trigger SwiftUI view updates.

Typically held with `@StateObject` in the parent view and passed to `GoogleMapView`.

## Signature

```swift
public final class GoogleMapViewState: MapViewState<GoogleMapDesignType>
```

## Initializers

### `init(id:mapDesignType:cameraPosition:)`

Creates an instance with an explicit identifier.

```swift
public init(
    id: String,
    mapDesignType: GoogleMapDesignType = GoogleMapDesign.Normal,
    cameraPosition: MapCameraPosition = .Default
)
```

### `init(mapDesignType:cameraPosition:)`

Creates an instance with an auto-generated UUID identifier.

```swift
public convenience init(
    mapDesignType: GoogleMapDesignType = GoogleMapDesign.Normal,
    cameraPosition: MapCameraPosition = .Default
)
```

**Parameters (shared)**

- `id`
    - Type: `String`
    - Description: A stable identifier for this state instance. Must be unique among all active
      map states. The convenience initializer generates a `UUID` automatically.
- `mapDesignType`
    - Type: `GoogleMapDesignType`
    - Default: `GoogleMapDesign.Normal`
    - Description: The initial base map tile style.
- `cameraPosition`
    - Type: `MapCameraPosition`
    - Default: `.Default`
    - Description: The initial camera position (location, zoom, bearing, tilt).

## Properties

- `id` — Type: `String` — The unique identifier of this state instance.
- `cameraPosition` — Type: `MapCameraPosition` — The current camera position. Updated
  automatically as the user pans or zooms the map.
- `mapDesignType` — Type: `GoogleMapDesignType` — The active base map tile style. Setting this
  property updates the map immediately.

## Methods

### `moveCameraTo(cameraPosition:durationMillis:)`

Moves or animates the camera to the specified position.

**Signature**

```swift
public override func moveCameraTo(
    cameraPosition: MapCameraPosition,
    durationMillis: Long? = 0
)
```

**Parameters**

- `cameraPosition`
    - Type: `MapCameraPosition`
    - Description: The target camera position.
- `durationMillis`
    - Type: `Long?`
    - Default: `0`
    - Description: Animation duration in milliseconds. `0` or `nil` moves the camera instantly.
      Positive values animate the transition.

---

### `moveCameraTo(position:durationMillis:)`

Moves or animates the camera to center on the specified geographic point, keeping the current
zoom, bearing, and tilt.

**Signature**

```swift
public override func moveCameraTo(
    position: GeoPoint,
    durationMillis: Long? = 0
)
```

**Parameters**

- `position`
    - Type: `GeoPoint`
    - Description: The target geographic coordinate.
- `durationMillis`
    - Type: `Long?`
    - Default: `0`
    - Description: Animation duration in milliseconds. `0` or `nil` moves the camera instantly.

## Example

```swift
import MapConductorForGoogleMaps
import SwiftUI

struct MyMapScreen: View {
    @StateObject private var mapState = GoogleMapViewState(
        mapDesignType: GoogleMapDesign.Satellite,
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 34.0522, longitude: -118.2437),
            zoom: 14.0
        )
    )

    var body: some View {
        VStack {
            GoogleMapView(state: mapState)
                .ignoresSafeArea()
            Button("Go to New York") {
                mapState.moveCameraTo(
                    position: GeoPoint(latitude: 40.7128, longitude: -74.0060),
                    durationMillis: 500
                )
            }
        }
    }
}
```
