import Foundation

/// Bounds waiting for read-only filesystem calls, including calls blocked inside
/// the OS. A timeout does not cancel the syscall: its worker keeps its slot until
/// it exits. Repeated requests for the same key cannot accumulate blocked workers.
/// Never use this wrapper for mutations, since work may outlive the caller.
enum BoundedFilesystemRead {
    private static let lock = NSLock()
    private static var activeKeys: Set<String> = []
    private static let maximumWorkers = 8

    private final class ResultBox<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Value?
        func store(_ value: Value) { lock.lock(); self.value = value; lock.unlock() }
        func load() -> Value? { lock.lock(); defer { lock.unlock() }; return value }
    }

    static func run<Value: Sendable>(key: String, timeout: TimeInterval,
                                    read: @escaping @Sendable () -> Value) -> Value? {
        guard timeout > 0 else { return nil }
        lock.lock()
        guard activeKeys.count < maximumWorkers, activeKeys.insert(key).inserted else {
            lock.unlock(); return nil
        }
        lock.unlock()
        let result = ResultBox<Value>()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            result.store(read())
            lock.lock(); activeKeys.remove(key); lock.unlock()
            finished.signal()
        }
        guard finished.wait(timeout: .now() + timeout) == .success else { return nil }
        return result.load()
    }
}
