import SwiftUI
import UIKit

@main
struct SumiWriteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var shell = EditorShell()

    var body: some Scene {
        WindowGroup {
            // 键盘避让由编辑面的 keyboardLayoutGuide 负责,SwiftUI 不再另外让位。
            EditorScreen(controller: shell.controller)
                .ignoresSafeArea()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { shell.controller.sceneDidEnterBackground() }
        }
    }
}

private final class WeakController { weak var controller: EditorController? }

/// M1 只有一页纸:进程里只建一个编辑面。
@MainActor
final class EditorShell {
    let controller: EditorController

    init() {
        let defaults = UserDefaults.standard
        let prefs = PrefsStore(defaults: defaults)
        // 每次发声读编辑面内存里的最新偏好(不在输入路径上解码);弱引用,不与编辑面成环。
        let live = WeakController()
        let sound = TypingSound(bundle: .main, prefs: { live.controller?.prefs ?? EditorPrefs() })
        controller = EditorController(
            open: PageLibrary.open(directory: PagePersistence.applicationDirectory, defaults: defaults),
            prefs: prefs,
            selection: SelectionStore(defaults: defaults),
            sound: sound)
        live.controller = controller
    }
}

private struct EditorScreen: UIViewControllerRepresentable {
    let controller: EditorController

    func makeUIViewController(context: Context) -> EditorController { controller }
    func updateUIViewController(_ controller: EditorController, context: Context) {}
}
