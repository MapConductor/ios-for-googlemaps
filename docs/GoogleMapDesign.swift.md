# GoogleMapDesign

`GoogleMapDesign` is a struct that represents a base map tile style for Google Maps. It conforms to
`GoogleMapDesignTypeProtocol` and wraps a `GMSMapViewType` value.

Use the static presets (`Normal`, `Satellite`, etc.) in most cases. Use `Create(id:)` to construct
an instance from a raw `GMSMapViewType` value.

## Signature

```swift
public struct GoogleMapDesign: GoogleMapDesignTypeProtocol, Hashable {
    public let id: GMSMapViewType

    public init(id: GMSMapViewType)
}
```

## Static Presets

- `Normal` — Standard road map with streets, labels, and points of interest.
- `Satellite` — Satellite imagery without map labels.
- `Hybrid` — Satellite imagery overlaid with roads and labels.
- `Terrain` — Topographic map showing elevation and land contours.
- `None` — No base map tiles. Useful for custom tile overlays.

## Methods

### `getValue()`

Returns the underlying `GMSMapViewType` value.

**Signature**

```swift
public func getValue() -> GMSMapViewType
```

**Returns**

- Type: `GMSMapViewType`
- Description: The `GMSMapViewType` constant associated with this design.

---

### `Create(id:)`

Creates a `GoogleMapDesign` from a `GMSMapViewType` value. Returns the corresponding static preset
if the value matches a known type; otherwise wraps the raw value directly.

**Signature**

```swift
public static func Create(id: GMSMapViewType) -> GoogleMapDesign
```

**Parameters**

- `id`
    - Type: `GMSMapViewType`
    - Description: The `GMSMapViewType` constant to look up.

**Returns**

- Type: `GoogleMapDesign`
- Description: The matching preset, or a new instance wrapping the raw value.

---

### `toMapDesignType(id:)`

Creates a value conforming to `GoogleMapDesignType` from a `GMSMapViewType`. Equivalent to
`Create(id:)` but typed as the protocol.

**Signature**

```swift
public static func toMapDesignType(id: GMSMapViewType) -> GoogleMapDesignType
```

**Parameters**

- `id`
    - Type: `GMSMapViewType`
    - Description: The `GMSMapViewType` constant to look up.

**Returns**

- Type: `GoogleMapDesignType`
- Description: An object conforming to `GoogleMapDesignType`.

## Example

```swift
// Use a preset
mapState.mapDesignType = GoogleMapDesign.Satellite

// Create from a raw GMSMapViewType
let hybrid = GoogleMapDesign.Create(id: .hybrid)
mapState.mapDesignType = hybrid
```

---

# GoogleMapDesignType

A type alias for `any GoogleMapDesignTypeProtocol`. Used throughout the SDK to refer to a map
design type without pinning to the concrete `GoogleMapDesign` struct.

## Signature

```swift
public typealias GoogleMapDesignType = any GoogleMapDesignTypeProtocol
```

---

# GoogleMapDesignTypeProtocol

A protocol that extends `MapDesignTypeProtocol` and constrains `Identifier` to `GMSMapViewType`.
All conforming types provide a `GMSMapViewType` identifier representing a Google Maps tile style.

## Signature

```swift
public protocol GoogleMapDesignTypeProtocol: MapDesignTypeProtocol
    where Identifier == GMSMapViewType {}
```
