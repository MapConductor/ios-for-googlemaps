Pod::Spec.new do |s|
  s.name = "MapConductorForGoogleMaps"
  s.version = "1.2.0"
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
  # Package.swift は 11.0.0 以上を要求する（docs の versions.ts と一致）。CocoaPods だけ
  # 下限が低いのは、Google が SPM(GitHub タグ)に先行公開し trunk への反映が遅れるため
  # ―― 2026-08 時点で trunk の最新は 10.15.0 で、11.x は存在しない。`~> 11.0` と書くと
  # CocoaPods 経路（RN の reactnative-for-googlemaps）が解決不能になる。上限を 12.0 未満に
  # しておけば、11.x が trunk に載った時点で自動的にそちらへ上がる。
  s.dependency "GoogleMaps", ">= 10.15", "< 12.0"
  s.dependency "MapConductorCore"
end
