import Foundation
@testable import SumiWrite

/// golden.json 的行与快照,键沿用 snake_case,字段与 FFI 的 `LineInfo` / `PageSnapshot` 一一对应。
struct GoldenLine: Decodable, Equatable {
    let id: String
    let text: String
    let first_ms: Int64?
    let last_ms: Int64?
    let time_source: String
}

struct GoldenSnapshot: Decodable, Equatable {
    let page_id: String
    let epoch: UInt32
    let revision: UInt64
    let body: String
    let root_line_id: String
    let lines: [GoldenLine]
}

extension PageSnapshot {
    var golden: GoldenSnapshot {
        GoldenSnapshot(
            page_id: pageId, epoch: epoch, revision: revision, body: body, root_line_id: rootLineId,
            lines: lines.map {
                GoldenLine(id: $0.id, text: $0.text, first_ms: $0.firstMs, last_ms: $0.lastMs, time_source: $0.timeSource)
            })
    }
}

private final class BundleToken {}

enum Fixtures {
    /// 夹具以文件夹引用打进测试包的 `fixtures/` 下。
    static func url(_ name: String) -> URL {
        Bundle(for: BundleToken.self).resourceURL!.appendingPathComponent("fixtures/\(name)")
    }

    static func golden() -> [String: GoldenSnapshot] {
        let data = try! Data(contentsOf: url("golden.json"))
        return try! JSONDecoder().decode([String: GoldenSnapshot].self, from: data)
    }
}
