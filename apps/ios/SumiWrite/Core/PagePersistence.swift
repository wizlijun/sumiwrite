import Foundation
import os

enum OpenResult {
    case ready(PagePersistence, CorePage)
    case failed(String)
}

/// 把内核给出的增量字节按顺序交给内核存储;只在一条串行队列上写。
final class PagePersistence: CommitSink {
    private static let log = Logger(subsystem: "app.sumiwrite", category: "persistence")
    private let store: CoreStore
    private let queue = DispatchQueue(label: "sumi.persistence")
    private var failed = false          // 只在 queue 上读写
    private var reported = false        // 只在 queue 上读写
    var onFailure: ((String) -> Void)?  // 主线程上调用

    private init(store: CoreStore) { self.store = store }

    static var applicationDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SumiWrite", isDirectory: true)
    }

    static func open(directory: URL) -> OpenResult {
        let unreadable = OpenResult.failed("打不开纸页")
        let file = directory.appendingPathComponent("page.sqlite3")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = try CoreStore.open(path: file.path)
            let p = PagePersistence(store: store)
            if let first = try store.pageIds().first {
                return .ready(p, try store.loadFresh(pageId: first))
            }
            let page = try CorePage.create(pageId: newPageId())
            p.queue.async {
                do { try store.commitInitial(page: page, opId: UUID().uuidString) }
                catch { p.fail("initial commit: \(error)") }
            }
            return .ready(p, page)
        } catch {
            log.error("open failed: \(String(describing: error))")
            return unreadable
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
