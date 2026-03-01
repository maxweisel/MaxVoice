import Foundation
import os.log

/// Thread-safe queue for audio data chunks
final class AudioQueue {
    private let logger = Logger(subsystem: "com.maxweisel.maxvoice", category: "AudioQueue")

    private var queue: [Data?] = []
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)

    private var totalBytesQueued: Int = 0
    private var chunkCount: Int = 0

    /// Push audio data to the queue. Pass nil to signal end of stream.
    func push(_ data: Data?) {
        lock.lock()
        queue.append(data)
        if let data = data {
            totalBytesQueued += data.count
            chunkCount += 1
            if chunkCount % 50 == 0 {
                logger.debug("AudioQueue: pushed chunk #\(self.chunkCount), total bytes: \(self.totalBytesQueued)")
            }
        } else {
            logger.info("AudioQueue: end-of-stream sentinel pushed (total chunks: \(self.chunkCount), total bytes: \(self.totalBytesQueued))")
        }
        lock.unlock()
        semaphore.signal()
    }

    /// Pop audio data from the queue. Returns nil for end of stream. Blocks if queue is empty.
    func pop() -> Data? {
        debugLog("AudioQueue.pop: Waiting on semaphore...")
        semaphore.wait()
        debugLog("AudioQueue.pop: Semaphore signaled, acquiring lock")

        lock.lock()
        // Safety check in case queue was cleared between semaphore signal and now
        guard !queue.isEmpty else {
            debugLog("AudioQueue.pop: Queue empty after semaphore! Returning nil")
            lock.unlock()
            return nil
        }
        let data = queue.removeFirst()
        let isNil = data == nil
        let size = data?.count ?? 0
        lock.unlock()

        debugLog("AudioQueue.pop: Returned \(isNil ? "nil (end sentinel)" : "\(size) bytes")")
        return data
    }

    /// Non-blocking pop. Returns the data, or nil if queue is empty.
    /// Use popResult to distinguish between empty queue and end-of-stream.
    func tryPop() -> Data? {
        lock.lock()
        defer { lock.unlock() }

        if queue.isEmpty {
            return nil
        }

        // Decrement semaphore since we're taking an item
        _ = semaphore.wait(timeout: .now())
        return queue.removeFirst()
    }

    /// Clear the queue
    func clear() {
        lock.lock()
        let count = queue.count
        debugLog("AudioQueue.clear: BEGIN - queue.count=\(count), totalBytesQueued=\(totalBytesQueued)")

        queue.removeAll()
        totalBytesQueued = 0
        chunkCount = 0
        lock.unlock()

        // Drain the semaphore to match the now-empty queue
        debugLog("AudioQueue.clear: Draining \(count) semaphore signals")
        var drained = 0
        for _ in 0..<count {
            if semaphore.wait(timeout: .now()) == .success {
                drained += 1
            }
        }
        debugLog("AudioQueue.clear: END - drained \(drained) signals")

        logger.info("AudioQueue: cleared \(count) items")
    }

    /// Check if queue is empty
    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return queue.isEmpty
    }

    /// Number of items in queue
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return queue.count
    }
}
