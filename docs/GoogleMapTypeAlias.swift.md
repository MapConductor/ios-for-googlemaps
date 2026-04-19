# GoogleMapTypeAlias

Type aliases that map Google Maps SDK concrete types to the generic names used by the SDK's
overlay system. These allow overlay controllers and renderers to reference the underlying
Google Maps objects without coupling the rest of the SDK to `GoogleMaps` directly.

## Aliases

- `GoogleMapActualMarker`
    - Type: `GMSMarker`
    - Description: The Google Maps marker type used internally by the marker controller and
      renderer.
- `GoogleMapActualCircle`
    - Type: `GMSCircle`
    - Description: The Google Maps overlay type used for circle rendering. Note: circles are
      rendered as `GMSPolygon` approximations — this alias exists for API symmetry.
- `GoogleMapActualPolyline`
    - Type: `GMSPolyline`
    - Description: The Google Maps polyline type used by the polyline controller and renderer.
- `GoogleMapActualPolygon`
    - Type: `GMSPolygon`
    - Description: The Google Maps polygon type used by the polygon controller and renderer.
- `GoogleMapActualGroundImage`
    - Type: `GMSGroundOverlay`
    - Description: The Google Maps ground overlay type used for ground image rendering.
- `GoogleMapActualRasterLayer`
    - Type: `GMSURLTileLayer`
    - Description: The Google Maps tile layer type used for raster layer rendering.

## Signature

```swift
public typealias GoogleMapActualMarker      = GMSMarker
public typealias GoogleMapActualCircle      = GMSCircle
public typealias GoogleMapActualPolyline    = GMSPolyline
public typealias GoogleMapActualPolygon     = GMSPolygon
public typealias GoogleMapActualGroundImage = GMSGroundOverlay
public typealias GoogleMapActualRasterLayer = GMSURLTileLayer
```
