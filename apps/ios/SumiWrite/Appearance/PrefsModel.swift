import Foundation

/// 可观察的偏好模型;每次改动落盘,落盘失败则回退。
@MainActor
final class PrefsModel: ObservableObject {
    private let store: PrefsStore

    @Published var prefs: EditorPrefs {
        didSet {
            guard prefs != oldValue else { return }
            if !store.save(prefs) { prefs = oldValue }
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
