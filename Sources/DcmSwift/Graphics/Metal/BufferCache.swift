#if canImport(Metal)
import Metal
import Foundation

/// Simple cache for reusing `MTLBuffer` instances across frames.
/// Buffers are keyed by their length and stored in a pool so that
/// subsequent frames can reuse them without incurring allocation cost.
final class MetalBufferCache {
    static let shared = MetalBufferCache(device: MetalAccelerator.shared.device)

    private let device: MTLDevice?
    private var cache: [Int: [MTLBuffer]] = [:]
    private let lock = NSLock()

    init(device: MTLDevice?) {
        self.device = device
    }

    /// Retrieve a buffer of at least `length` bytes. A cached buffer will be
    /// returned if available, otherwise a new one is created.
    func buffer(length: Int) -> MTLBuffer? {
        lock.lock(); defer { lock.unlock() }
        if var existing = cache[length], !existing.isEmpty {
            let buf = existing.removeLast()
            cache[length] = existing
            return buf
        }
        return device?.makeBuffer(length: length, options: .storageModeShared)
    }

    /// Return a buffer to the cache for reuse.
    func recycle(_ buffer: MTLBuffer) {
        lock.lock()
        cache[buffer.length, default: []].append(buffer)
        lock.unlock()
    }

    /// Remove all cached buffers.
    func purge() {
        lock.lock(); cache.removeAll(); lock.unlock()
    }
}
#endif
