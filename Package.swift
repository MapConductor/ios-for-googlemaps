// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "mapconductor-for-googlemaps",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MapConductorForGoogleMaps",
            targets: ["MapConductorForGoogleMaps"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/MapConductor/ios-sdk-core", from: "1.0.0"),
        .package(url: "https://github.com/googlemaps/ios-maps-sdk", from: "10.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MapConductorForGoogleMaps",
            dependencies: [
                .product(name: "MapConductorCore", package: "ios-sdk-core"),
                .product(name: "GoogleMaps", package: "ios-maps-sdk"),
            ],
        ),
    ]
)
