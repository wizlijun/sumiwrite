import Foundation
import os

/// 把内核给出的增量字节按顺序交给内核存储;只在一条串行队列上写。
final class PagePersistence: CommitSink {
    private static let log = Logger(subsystem: "app.sumiwrite", category: "persistence")
    private let store: CoreStore
    private let queue = DispatchQueue(label: "sumi.persistence")
    private var failed = false          // 只在 queue 上读写
    private var reported = false        // 只在 queue 上读写
    var onFailure: ((String) -> Void)?  // 主线程上调用

    static var applicationDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SumiWrite", isDirectory: true)
    }

    init(store: CoreStore) { self.store = store }

    /// 在队列上同步执行,排在已入队的增量之后;抛错与增量失败同样置为失败并通知 `onFailure`。
    func perform<T>(_ body: (CoreStore) throws -> T) throws -> T {
        try queue.sync {
            do { return try body(store) }
            catch {
                fail("perform: \(error)")
                throw error
            }
        }
    }

    func committed(_ commit: EditCommit, page: CorePage) {
        let pageId = page.pageId(), epoch = page.epoch()
        queue.async { [self] in
            if failed { return }
            do {
                try store.commitDelta(pageId: pageId, epoch: epoch, revision: commit.revision,
                                      opId: UUID().uuidString, update: commit.update)
            } catch {
                fail("delta commit: \(error)")
            }
        }
    }

    func flushAndCheckpoint(page: CorePage, completion: @escaping (Bool) -> Void) {
        queue.async { [self] in
            var ok = !failed
            if ok {
                do { try store.checkpoint(page: page) }
                catch CoreError.StaleRevision {
                    Self.log.info("checkpoint skipped: stale revision")
                } catch {
                    fail("checkpoint: \(error)")
                    ok = false
                }
            }
            DispatchQueue.main.async { completion(ok) }
        }
    }

    /// 只给测试用。
    func waitUntilIdle() { queue.sync {} }

    /// 必须在 queue 上调用。
    private func fail(_ why: String) {
        Self.log.error("write failed: \(why)")
        failed = true
        if reported { return }
        reported = true
        DispatchQueue.main.async { [weak self] in self?.onFailure?("保存失败") }
    }
}
