import SwiftUI
import UIKit

@main
struct SumiWriteApp: App {
    @State private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            if let library = env.library {
                ContentView(controller: env.controller, library: library, prefs: env.prefs)
            } else {
                FailureView(controller: env.controller, prefs: env.prefs)
            }
        }
    }
}

private final class WeakController { weak var controller: EditorController? }

/// 进程里只建一个编辑面;纸页库归它持有。库打不开时 `library` 为 nil,编辑面只读并显示状态。
@MainActor
final class AppEnvironment {
    let controller: EditorController
    let library: PageLibrary?
    let prefs: PrefsModel

    init() {
        let defaults = UserDefaults.standard
        prefs = PrefsModel(store: PrefsStore(defaults: defaults))
        // 每次发声读编辑面内存里的最新偏好(不在输入路径上解码);弱引用,不与编辑面成环。
        let live = WeakController()
        let sound = TypingSound(bundle: .main, prefs: { live.controller?.prefs ?? EditorPrefs() })
        let persistence: PagePersistence?
        let page: CorePage?
        switch PageLibrary.open(directory: PagePersistence.applicationDirectory, defaults: defaults) {
        case .ready(let lib, let p, let pg):
            library = lib
            persistence = p
            page = pg
        case .failed:
            library = nil
            persistence = nil
            page = nil
        }
        controller = EditorController(persistence: persistence, page: page, prefs: prefs,
                                      selection: SelectionStore(defaults: defaults), sound: sound)
        live.controller = controller
    }
}
