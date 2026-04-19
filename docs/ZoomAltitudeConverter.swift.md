# GoogleMapsZoomAltitudeConverter

Converts between Google Maps zoom levels and the altitude-based camera model used internally by
the SDK. Implements `ZoomAltitudeConverterProtocol`.

The conversion uses the formula:
- `altitude = (zoom0Altitude × cos(latitude)) / 2^zoom × cos(tilt)`

This matches the historical behavior of Google Maps where altitude approximates the camera
distance from the Earth's surface.

## Signature

```swift
public class GoogleMapsZoomAltitudeConverter: ZoomAltitudeConverterProtocol {
    public let zoom0Altitude: Double

    public init(zoom0Altitude: Double = 171_319_879.0)
}
```

## Constructor Parameters

- `zoom0Altitude`
    - Type: `Double`
    - Default: `171_319_879.0`
    - Description: The reference altitude (in meters) at zoom level 0 near the equator. Override
      this only if you need to calibrate the converter for a specific display environment.

## Methods

### `zoomLevelToAltitude(zoomLevel:latitude:tilt:)`

Converts a zoom level to an altitude in meters.

**Signature**

```swift
public func zoomLevelToAltitude(
    zoomLevel: Double,
    latitude: Double,
    tilt: Double
) -> Double
```

**Parameters**

- `zoomLevel`
    - Type: `Double`
    - Description: The map zoom level. Clamped to `[0, 22]`.
- `latitude`
    - Type: `Double`
    - Description: The camera's latitude in degrees. Clamped to `[-85, 85]`.
- `tilt`
    - Type: `Double`
    - Description: The camera tilt angle in degrees. Clamped to `[0, 90]`.

**Returns**

- Type: `Double`
- Description: The estimated altitude in meters. Clamped to `[100, 50_000_000]`.

---

### `altitudeToZoomLevel(altitude:latitude:tilt:)`

Converts an altitude in meters to a zoom level.

**Signature**

```swift
public func altitudeToZoomLevel(
    altitude: Double,
    latitude: Double,
    tilt: Double
) -> Double
```

**Parameters**

- `altitude`
    - Type: `Double`
    - Description: The camera altitude in meters. Clamped to `[100, 50_000_000]`.
- `latitude`
    - Type: `Double`
    - Description: The camera's latitude in degrees. Clamped to `[-85, 85]`.
- `tilt`
    - Type: `Double`
    - Description: The camera tilt angle in degrees. Clamped to `[0, 90]`.

**Returns**

- Type: `Double`
- Description: The estimated zoom level. Clamped to `[0, 22]`.

## Example

```swift
let converter = GoogleMapsZoomAltitudeConverter()

// Convert zoom 14 at the equator with no tilt
let altitude = converter.zoomLevelToAltitude(zoomLevel: 14, latitude: 0, tilt: 0)

// Convert back
let zoom = converter.altitudeToZoomLevel(altitude: altitude, latitude: 0, tilt: 0)
// zoom ≈ 14.0
```
