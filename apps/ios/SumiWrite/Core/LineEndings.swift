import Foundation

/// 换行统一为 LF(04「粘贴」):先把 CRLF 换成 LF,再把剩下的单独 CR 换成 LF。
/// 内核拒绝任何含 CR 的正文,所以凡是交给内核的文字都先过这一步。
enum LineEndings {
    static func lf(_ s: String) -> String {
        guard s.utf8.contains(0x0D) else { return s }
        return s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
