import Foundation
import GoogleMaps
import MapConductorCore
import UIKit

/// Generated tiles are already in this process. Using the URL loader makes
/// obsolete zoom requests occupy its HTTP connections until their sources
/// arrive; the loader exposes no cancellation to our provider.
@MainActor
final class GoogleLocalTileLayer: GMSTileLayer {
    var onCacheRefresh: (() -> Void)?

    private let source: GoogleRasterTileURLSource
    private let logicalTileSize: Int
    private let requests: GoogleLocalTileRequestQueue
    private var deliveredTiles = GoogleTileCacheBudget()
    private var trimWork: DispatchWorkItem?
    private var memoryWarningObserver: NSObjectProtocol?
    private var recovery = GoogleTileRecovery()
    private var lastCameraZoom: Double?
    private var lastCamera: GMSCameraPosition?

    nonisolated static func sourceZoomOffset(requestedZoom: UInt, cameraZoom: Double, logicalTileSize: Int) -> Int {
        let nominal = Double(requestedZoom) + log2(Double(max(1, logicalTileSize)) / 512.0)
        return max(0, min(8, Int(nominal - floor(cameraZoom - 1))))
    }

    init(source: GoogleRasterTileURLSource, server: LocalTileServer, logicalTileSize: Int) {
        self.source = source
        self.logicalTileSize = logicalTileSize
        requests = GoogleLocalTileRequestQueue { url, cancellation in
            server.renderLocalTile(url: url, isCancelled: cancellation)
        }
        super.init()
        requests.onCancelled = { [weak self] in
            guard let self else { return }
            self.recovery.cancelled()
            self.scheduleCacheTrim()
        }
        requests.onIdle = { [weak self] in self?.scheduleCacheTrim() }
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.recovery.memoryWarning()
                self.scheduleCacheTrim()
            }
        }
    }

    deinit {
        trimWork?.cancel()
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
    }

    nonisolated override func requestTileFor(x: UInt, y: UInt, zoom: UInt, receiver: GMSTileReceiver) {
        // Physical-device SDK callbacks can arrive off main. MainActor does
        // not dispatch Objective-C calls, so enter the queue explicitly before
        // reading the source or touching pending/active requests.
        DispatchQueue.main.async {
            self.requestTileOnMain(x: x, y: y, zoom: zoom, receiver: receiver)
        }
    }

    private func requestTileOnMain(x: UInt, y: UInt, zoom: UInt, receiver: GMSTileReceiver) {
        guard var url = source.url(x: x, y: y, zoom: zoom) else {
            receiver.receiveTileWith(x: x, y: y, zoom: zoom, image: kGMSTileLayerNoTile)
            return
        }
        // Google rounds the target raster level; vector sources use floor.
        // Render each subdivision with the parent's data, style zoom and paint scale.
        if let cameraZoom = map.map({ Double($0.camera.zoom) }) ?? lastCameraZoom {
            let offset = Self.sourceZoomOffset(requestedZoom: zoom, cameraZoom: cameraZoom, logicalTileSize: logicalTileSize)
            if offset > 0, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "sourceZoomOffset", value: String(offset))]
                url = components.url ?? url
            }
        }
        // A new delivery can still be rendering when the last successful
        // tile is more than one second old. Never trim that in-flight batch.
        trimWork?.cancel()
        requests.enqueue(url: url, zoom: zoom) { bytes in
            // Nil means retryable. A cancelled request must never be cached
            // as "no tile", or revisiting that zoom would leave a hole.
            let image = bytes.flatMap { UIImage(data: $0) }
            receiver.receiveTileWith(x: x, y: y, zoom: zoom, image: image)
            if let image, let pixels = image.cgImage {
                let cost = pixels.bytesPerRow * pixels.height
                // A large/3x display must fit its visible grid; otherwise a
                // refresh alone would exceed the limit and trigger a loop.
                if let map = self.map {
                    let edge = Double(max(1, self.logicalTileSize))
                    let columns = Int(ceil(Double(map.bounds.width) / edge)) + 1
                    let rows = Int(ceil(Double(map.bounds.height) / edge)) + 1
                    self.deliveredTiles.minimumByteLimit = columns * rows * cost
                }
                self.deliveredTiles.record(
                    key: "\(zoom)/\(x)/\(y)", cost: cost
                )
                self.scheduleCacheTrim()
            }
        }
    }

    func cameraChanged(zoom: Double) {
        // Larger tiles cover a coarser grid. Allow adjacent levels too: Google
        // uses them during zoom transitions and may cap the native tile size.
        if let camera = map?.camera {
            if let previous = lastCamera {
                if camera.target.latitude != previous.target.latitude
                    || camera.target.longitude != previous.target.longitude
                    || camera.zoom != previous.zoom || camera.bearing != previous.bearing
                    || camera.viewingAngle != previous.viewingAngle {
                    recovery.cameraMoved()
                }
            } else {
                recovery.cameraMoved()
            }
            lastCamera = camera
        } else if lastCameraZoom.map({ abs(zoom - $0) > 0.05 }) ?? true {
            recovery.cameraMoved()
        }
        if let previous = lastCameraZoom, floor(previous) != floor(zoom) {
            // The SDK may reuse the same rounded target grid across this
            // boundary. Refresh after the surviving requests settle.
            recovery.memoryWarning()
        }
        lastCameraZoom = zoom
        requests.updateZoom(zoom + log2(256.0 / Double(max(1, logicalTileSize))))
        scheduleCacheTrim()
    }

    // Google's image cache has no per-entry eviction API. Bound each cache
    // generation and refresh only after camera/tile activity settles. The
    // provider's LRU/disk caches supply the visible tiles without refetching.
    private func scheduleCacheTrim() {
        trimWork?.cancel()
        trimWork = nil
        guard ((deliveredTiles.shouldTrim && recovery.canRefresh) || recovery.needsRefresh),
              requests.isIdle else { return }
        let work = DispatchWorkItem { [weak self] in self?.trimTileCache() }
        trimWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func trimTileCache() {
        trimWork?.cancel()
        trimWork = nil
        guard requests.isIdle else { return }
        deliveredTiles.reset()
        recovery.refreshed()
        // Cancelling active requests here used to deliver nil into the newly
        // cleared SDK cache. Google does not promptly retry every such tile,
        // leaving fallback images or holes after rapid zoom gestures.
        // Clearing/reusing this SDK layer leaves decoded fallback textures
        // behind on physical devices. The renderer replaces the SDK object.
        onCacheRefresh?()
    }

    func inheritRefreshState(from previous: GoogleLocalTileLayer) {
        recovery = previous.recovery
        lastCameraZoom = previous.lastCameraZoom
        lastCamera = previous.lastCamera
    }

    func cancelRequests() {
        trimWork?.cancel()
        trimWork = nil
        requests.cancelAll()
    }
}

/// Cancelled zoom requests need one refresh after the surviving batch settles.
/// A refresh can itself request/preempt fallback tiles, so those cancellations
/// must not cause an endless refresh loop without another camera movement.
struct GoogleTileRecovery {
    private(set) var needsRefresh = false
    // Let a fresh SDK layer fill its visible/prefetched working set. That
    // batch alone must not exceed the budget and start another refresh loop.
    // A real pan/zoom re-enables eviction of accumulated offscreen tiles.
    private(set) var canRefresh = true

    mutating func cameraMoved() { canRefresh = true }
    mutating func memoryWarning() { needsRefresh = true }
    mutating func cancelled() { if canRefresh { needsRefresh = true } }
    mutating func refreshed() { needsRefresh = false; canRefresh = false }
}

/// Counts decoded images handed to the SDK, not the much smaller PNG bytes.
struct GoogleTileCacheBudget {
    private let byteLimit: Int
    private let countLimit: Int
    private let ttl: TimeInterval
    private let clock: () -> TimeInterval
    private var started: TimeInterval
    private var costs: [String: Int] = [:]
    private(set) var bytes = 0
    var minimumByteLimit = 0

    init(byteLimit: Int = 32 << 20, countLimit: Int = 256, ttl: TimeInterval = 60,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.byteLimit = byteLimit
        self.countLimit = countLimit
        self.ttl = ttl
        self.clock = clock
        self.started = clock()
    }

    mutating func record(key: String, cost: Int) {
        // Once a trim is due, further unique tiles need no retained metadata.
        if costs[key] == nil, shouldTrim { return }
        bytes -= costs[key] ?? 0
        costs[key] = cost
        bytes += cost
    }

    var shouldTrim: Bool {
        bytes > max(byteLimit, minimumByteLimit) || costs.count > countLimit
            || (!costs.isEmpty && clock() - started >= ttl)
    }

    mutating func reset() {
        costs.removeAll(keepingCapacity: true)
        bytes = 0
        started = clock()
    }
}

/// Only active jobs enter GCD. Pending tiles wait without occupying threads
/// or the server's render slots, and the current zoom takes precedence.
@MainActor
final class GoogleLocalTileRequestQueue {
    typealias Render = @Sendable (URL, @escaping @Sendable () -> Bool) -> Data?
    private static let work = DispatchQueue(
        label: "MapConductorForGoogleMaps.localTiles", qos: .utility, attributes: .concurrent)

    var onCancelled: (() -> Void)?
    var onIdle: (() -> Void)?
    var isIdle: Bool { pending.isEmpty && active.isEmpty }

    private let render: Render
    private let width: Int
    private var zoom: Double?
    private var pending: [Job] = []
    private var active: [UUID: Job] = [:]

    init(width: Int = 4, render: @escaping Render) {
        self.width = max(1, width)
        self.render = render
    }

    func enqueue(url: URL, zoom: UInt, completion: @escaping (Data?) -> Void) {
        pending.append(Job(url: url, zoom: zoom, completion: completion))
        drain()
    }

    func updateZoom(_ next: Double) {
        guard next.isFinite else { return }
        zoom = next
        let stale = pending.filter { abs(Double($0.zoom) - next) > 1.5 }
        pending.removeAll { abs(Double($0.zoom) - next) > 1.5 }
        for job in active.values where abs(Double(job.zoom) - next) > 1.5 {
            job.cancellation.cancel()
        }
        for job in stale { job.completion(nil) }
        if !stale.isEmpty { onCancelled?() }
        drain()
    }

    func cancelAll() {
        let stale = pending
        pending.removeAll()
        for job in active.values { job.cancellation.cancel() }
        for job in stale { job.completion(nil) }
    }

    private func drain() {
        if active.count >= width,
           let zoom, let closest = pending.map({ abs(Double($0.zoom) - zoom) }).min() {
            // Adjacent levels remain useful as fallbacks, but a slow fallback
            // must not occupy every lane when the current level is requested.
            let lessUrgent = active.values.filter {
                !$0.cancellation.isCancelled && abs(Double($0.zoom) - zoom) > closest + 0.25
            }
            for job in lessUrgent.prefix(pending.count) { job.cancellation.cancel() }
        }
        while active.count < width, !pending.isEmpty {
            let index = pending.indices.min { left, right in
                abs(Double(pending[left].zoom) - (zoom ?? Double(pending[left].zoom)))
                    < abs(Double(pending[right].zoom) - (zoom ?? Double(pending[right].zoom)))
            } ?? 0
            let job = pending.remove(at: index)
            active[job.id] = job
            let render = self.render
            Self.work.async {
                let bytes = render(job.url) { job.cancellation.isCancelled }
                DispatchQueue.main.async {
                    self.active.removeValue(forKey: job.id)
                    let cancelled = job.cancellation.isCancelled
                    job.completion(cancelled ? nil : bytes)
                    if cancelled { self.onCancelled?() }
                    self.drain()
                }
            }
        }
        if isIdle { onIdle?() }
    }

    // Immutable job data crosses to the worker; completion runs only on main.
    private final class Job: @unchecked Sendable {
        let id = UUID()
        let url: URL
        let zoom: UInt
        let completion: (Data?) -> Void
        let cancellation = Cancellation()

        init(url: URL, zoom: UInt, completion: @escaping (Data?) -> Void) {
            self.url = url
            self.zoom = zoom
            self.completion = completion
        }
    }

    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        func cancel() {
            lock.lock(); cancelled = true; lock.unlock()
        }

        var isCancelled: Bool {
            lock.lock(); defer { lock.unlock() }
            return cancelled
        }
    }
}
