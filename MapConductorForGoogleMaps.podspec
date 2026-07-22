Pod::Spec.new do |s|
  s.name = "MapConductorForGoogleMaps"
  s.version = "1.1.4"
  s.summary = "MapConductor's Google Maps provider."
  s.license = { :type => "Apache-2.0", :file => "LICENSE" }
  s.author = "MapConductor"
  s.homepage = "https://github.com/MapConductor/ios-for-googlemaps"
  s.source = { :path => __dir__ }
  s.platform = :ios, "16.0"
  s.swift_version = "5.9"
  s.source_files = "Sources/MapConductorForGoogleMaps/**/*.swift"

  # Compiled from source against the real, officially-published GoogleMaps pod so CocoaPods
  # installs Google's own binary directly into the consuming app - this podspec (and
  # MapConductorCore, also source-compiled) must never be distributed as a prebuilt xcframework,
  # since a prebuilt binary would have to statically embed GoogleMaps' own static library at
  # archive time, redistributing Google's proprietary compiled SDK under a different name.
  s.dependency "GoogleMaps", "~> 10.0"
  s.dependency "MapConductorCore"
end
