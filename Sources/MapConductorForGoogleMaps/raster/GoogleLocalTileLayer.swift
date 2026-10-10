import Foundation
import GoogleMaps
import MapConductorCore
import UIKit

/// Generated tiles are already in this process. Using the URL loader makes
/// obsolete zoom requests occupy its HTTP connections until their sources
/// arrive; the loader exposes no cancellation to our provider.
@MainActor
final class GoogleLocalTileLayer: GMSTileLayer {
    private let source: GoogleRasterTileURLSource
    private let logicalTileSize: Int
    private let requests: GoogleLocalTileRequestQueue

    init(source: GoogleRasterTileURLSource, server: LocalTileServer, logicalTileSize: Int) {
        self.source = source
        self.logicalTileSize = logicalTileSize
        requests = GoogleLocalTileRequestQueue { url, cancellation in
            server.renderLocalTile(url: url, isCancelled: cancellation)
        }
        super.init()
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
        guard let url = source.url(x: x, y: y, zoom: zoom) else {
            receiver.receiveTileWith(x: x, y: y, zoom: zoom, image: kGMSTileLayerNoTile)
            return
        }
        requests.enqueue(url: url, zoom: zoom) { bytes in
            // Nil means retryable. A cancelled request must never be cached
            // as "no tile", or revisiting that zoom would leave a hole.
            let image = bytes.flatMap { UIImage(data: $0) }
            receiver.receiveTileWith(x: x, y: y, zoom: zoom, image: image)
        }
    }

    func cameraChanged(zoom: Double) {
        // Larger tiles cover a coarser grid. Allow adjacent levels too: Google
        // uses them during zoom transitions and may cap the native tile size.
        requests.updateZoom(zoom + log2(256.0 / Double(max(1, logicalTileSize))))
    }

    func cancelRequests() { requests.cancelAll() }
}

/// Only active jobs enter GCD. Pending tiles wait without occupying threads
/// or the server's render slots, and the current zoom takes precedence.
@MainActor
final class GoogleLocalTileRequestQueue {
    typealias Render = @Sendable (URL, @escaping @Sendable () -> Bool) -> Data?
    private static let work = DispatchQueue(
        label: "MapConductorForGoogleMaps.localTiles", qos: .utility, attributes: .concurrent)

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
                    job.completion(job.cancellation.isCancelled ? nil : bytes)
                    self.drain()
                }
            }
        }
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
