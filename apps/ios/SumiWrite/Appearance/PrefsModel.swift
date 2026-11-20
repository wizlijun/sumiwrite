import Foundation

/// 可观察的偏好模型;每次改动落盘,落盘失败则回退。
@MainActor
final class PrefsModel: ObservableObject {
    private let store: PrefsStore

    @Published var prefs: EditorPrefs {
        didSet {
            guard prefs != oldValue else { return }
            // 行距滑块会给出 1.6000000000000001 这类值:落盘前取整到 0.1。
            var rounded = prefs
            rounded.lineSpacing = (rounded.lineSpacing * 10).rounded() / 10
            if rounded != prefs { prefs = rounded }
            if !store.save(rounded) { prefs = oldValue }
        }
    }

    init(store: PrefsStore) {
        self.store = store
        self.prefs = store.load()
    }

    func bumpSize(_ delta: Double) {
        prefs = prefs.bumpingFontSize(delta)
    }

    func resetSize() {
        prefs.fontSize = EditorPrefs.defaultFontSize
        prefs.lineSpacing = EditorPrefs.defaultLineSpacing
    }
}
