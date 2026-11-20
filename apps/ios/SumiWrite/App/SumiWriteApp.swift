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

/// M1 只有一页纸:进程里只建一个编辑面。
final class EditorShell {
    let controller: EditorController

    init() {
        let defaults = UserDefaults.standard
        controller = EditorController(
            open: PagePersistence.open(directory: PagePersistence.applicationDirectory),
            prefs: PrefsStore(defaults: defaults),
            selection: SelectionStore(defaults: defaults),
            sound: nil)
    }
}

private struct EditorScreen: UIViewControllerRepresentable {
    let controller: EditorController

    func makeUIViewController(context: Context) -> EditorController { controller }
    func updateUIViewController(_ controller: EditorController, context: Context) {}
}
