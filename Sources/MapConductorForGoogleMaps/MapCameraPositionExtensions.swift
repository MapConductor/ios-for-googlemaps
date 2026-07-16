import Foundation
import GoogleMaps
import MapConductorCore

private let converter = GoogleMapsZoomAltitudeConverter(zoom0Altitude: 171_319_879.0)

// Convert from MapCameraPosition to GMSCameraPosition
public extension MapCameraPosition {
    func toCameraPosition() -> GMSCameraPosition {
        if tilt >= 0 {
            NSLog("Google (in)position=\(position),(in)tilt=\(tilt) / (out)center=\(position), (out)zoom=\(zoom), (out)viewingAngle=\(tilt)")
            return GMSCameraPosition(
                latitude: position.latitude,
                longitude: position.longitude,
                zoom: Float(zoom),
                bearing: bearing,
                viewingAngle: tilt
            )
        }

        let tiltAbsDeg = min(max(abs(tilt), 0.0), 60)
        let tiltAbsRad = tiltAbsDeg * .pi / 180.0
        let altitude = converter.zoomLevelToAltitude(
            zoomLevel: zoom,
            latitude: position.latitude,
            tilt: 0.0
        )
        let target = Spherical.computeOffset(
            origin: position,
            distance: altitude * tan(tiltAbsRad),
            heading: bearing
        )
        
        NSLog("Google (in)position=\(position),(in)tilt=\(tilt), (out)target=\(target), (out)zoom=\(zoom), (out)viewingAngle=\(tiltAbsDeg)")
        return GMSCameraPosition(
            target: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude),
            zoom: Float(zoom),
            bearing: bearing,
            viewingAngle: tiltAbsDeg
        )
    }
}

// Convert from GMSCameraPosition to MapCameraPosition
public extension GMSCameraPosition {
    func toMapCameraPosition(
        logicalTiltHint: Double? = nil,
        visibleRegion: VisibleRegion? = nil
    ) -> MapCameraPosition {
        let nativeTilt = Double(viewingAngle)
        let altitude = converter.zoomLevelToAltitude(
            zoomLevel: Double(zoom),
            latitude: target.latitude,
            tilt: 0.0
        )
        var position = GeoPoint(
            latitude: target.latitude,
            longitude: target.longitude,
            altitude: altitude
        )
        var logicalTilt = nativeTilt

        if let logicalTiltHint, logicalTiltHint < 0.0, nativeTilt > 0.0 {
            let tiltRadians = nativeTilt * .pi / 180.0
            let recovered = Spherical.computeOffset(
                origin: position,
                distance: altitude * tan(tiltRadians),
                heading: bearing + 180.0
            )
            position = GeoPoint(
                latitude: recovered.latitude,
                longitude: recovered.longitude,
                altitude: altitude
            )
            logicalTilt = -nativeTilt
        }

        return MapCameraPosition(
            position: position,
            zoom: Double(zoom),
            bearing: bearing,
            tilt: logicalTilt,
            visibleRegion: visibleRegion
        )
    }
}
