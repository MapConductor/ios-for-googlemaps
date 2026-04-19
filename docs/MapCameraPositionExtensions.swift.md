# MapCameraPositionExtensions

Extensions that convert between the SDK's `MapCameraPosition` type and the Google Maps SDK's
`GMSCameraPosition` type.

---

# MapCameraPosition extension

## `toCameraPosition()`

Converts a `MapCameraPosition` to a `GMSCameraPosition` for use with the Google Maps SDK.

### Signature

```swift
public extension MapCameraPosition {
    func toCameraPosition() -> GMSCameraPosition
}
```

### Returns

- Type: `GMSCameraPosition`
- Description: A Google Maps camera position with latitude, longitude, zoom, bearing, and tilt
  derived from the `MapCameraPosition` values.

### Example

```swift
let camera: MapCameraPosition = MapCameraPosition(
    position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
    zoom: 13.0
)
let gmsCameraPosition = camera.toCameraPosition()
mapView.moveCamera(GMSCameraUpdate.setCamera(gmsCameraPosition))
```

---

# GMSCameraPosition extension

## `toMapCameraPosition(visibleRegion:)`

Converts a `GMSCameraPosition` to a `MapCameraPosition`. Altitude is estimated from the zoom
level using `GoogleMapsZoomAltitudeConverter`.

### Signature

```swift
public extension GMSCameraPosition {
    func toMapCameraPosition(visibleRegion: VisibleRegion? = nil) -> MapCameraPosition
}
```

### Parameters

- `visibleRegion`
    - Type: `VisibleRegion?`
    - Default: `nil`
    - Description: The visible map region at the time of conversion. When provided, the resulting
      `MapCameraPosition` includes accurate `visibleRegion` bounds for use in overlay rendering
      and culling.

### Returns

- Type: `MapCameraPosition`
- Description: A `MapCameraPosition` with position, zoom, bearing, tilt, and optionally
  `visibleRegion` populated from the `GMSCameraPosition`.
