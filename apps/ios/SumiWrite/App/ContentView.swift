import SwiftUI

/// 编辑面的 SwiftUI 外壳;控制器只建一次,由外部持有。
struct EditorHost: UIViewControllerRepresentable {
    let controller: EditorController

    func makeUIViewController(context: Context) -> EditorController { controller }
    func updateUIViewController(_ controller: EditorController, context: Context) {}
}

/// 纸页库打不开时的界面:只读编辑面加一行状态,没有菜单。
struct FailureView: View {
    let controller: EditorController
    @ObservedObject var prefs: PrefsModel
    @State private var status: String?

    var body: some View {
        let fg = Color(prefs.prefs.theme.foreground)
        ZStack {
            Color(prefs.prefs.theme.background).ignoresSafeArea()
            VStack(spacing: 0) {
                EditorHost(controller: controller)
                if let status { StatusLine(text: status, color: fg) }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(prefs.prefs.theme.isDark ? .dark : .light)
        .onAppear {
            status = controller.statusText
            controller.onStatusChange = { status = $0 }
        }
    }
}

/// 保存失败、打不开纸页:常驻在菜单条上方,不盖住正文。
private struct StatusLine: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(color.opacity(0.7))
            .padding(.vertical, 4)
            .accessibilityLabel(text)
    }
}

struct ContentView: View {
    let controller: EditorController
    @ObservedObject var library: PageLibrary
    @ObservedObject var prefs: PrefsModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var chromeOpen = false
    @State private var typingRecently = false
    @State private var typingWork: DispatchWorkItem?
    @State private var showOverview = false
    @State private var showAppearance = false
    @State private var toast: String?
    @State private var status: String?

    private var fg: Color { Color(prefs.prefs.theme.foreground) }
    private var scheme: ColorScheme { prefs.prefs.theme.isDark ? .dark : .light }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(prefs.prefs.theme.background).ignoresSafeArea()
            // 「···」放在编辑区下方的独立一条里,不叠在 UITextView 上:
            // 叠在上面时,点按会先被文本视图的手势接走,按钮收不到。
            VStack(spacing: 0) {
                EditorHost(controller: controller)
                if let status { StatusLine(text: status, color: fg) }
                chrome
                    .frame(height: 48)
                    .padding(.bottom, 4)
            }
            if let toast {
                Text(toast)
                    .font(.footnote)
                    .foregroundStyle(fg)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(fg.opacity(0.12)))
                    .padding(.bottom, 64)
                    .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(scheme)
        .onAppear {
            controller.onCommand = handle
            status = controller.statusText
            controller.onStatusChange = { status = $0 }
        }
        .onChange(of: scenePhase) { _, phase in
            // 退到后台走后台任务包装;只是失去活跃(控制中心、来电)直接存。
            if phase == .background { controller.sceneDidEnterBackground() }
            else if phase != .active { controller.saveNow() }
        }
        .sheet(isPresented: $showOverview, onDismiss: refocus) {
            OverviewView(library: library, onOpen: { id in
                guard id != library.currentID else { return true }
                return switchPage { library.open(id) }
            }, onTrash: { id in
                if switchPage({ library.moveToTrash(id) }) { flash("已移到废纸篓,可在总览里恢复") }
            }, onRestore: { id in library.restore(id) })
            .presentationDetents([.medium, .large])
            .preferredColorScheme(scheme)
        }
        .sheet(isPresented: $showAppearance, onDismiss: refocus) {
            AppearanceView(prefs: prefs)
                .presentationDetents([.medium, .large])
                .preferredColorScheme(scheme)
        }
    }

    // 底部按需工具:平时只有一个淡淡的「···」,打字时隐藏。
    @ViewBuilder private var chrome: some View {
        HStack(spacing: 6) {
            if chromeOpen {
                let pos = library.position
                chromeButton("chevron.left", "上一页") { switchPage { library.prev() } }
                Text("\(pos.index) / \(pos.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(fg.opacity(0.7))
                chromeButton("chevron.right", "下一页") { switchPage { library.next() } }
                chromeButton("plus", "新建") { switchPage { library.newPage() } }
                chromeButton("square.grid.2x2", "总览") { openOverview() }
                chromeButton("gearshape", "设置") { showAppearance = true }
                chromeButton("trash", "移到废纸篓") {
                    if switchPage({ library.moveToTrash(library.currentID) }) {
                        flash("已移到废纸篓,可在总览里恢复")
                    }
                }
            }
            chromeButton(chromeOpen ? "xmark" : "ellipsis", chromeOpen ? "收起" : "菜单") {
                withAnimation(.easeOut(duration: 0.15)) { chromeOpen.toggle() }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 2)
        .background(Capsule().fill(fg.opacity(chromeOpen ? 0.10 : 0)))
        .opacity(typingRecently && !chromeOpen ? 0 : (chromeOpen ? 1 : 0.35))
        .animation(.easeOut(duration: 0.3), value: typingRecently)
    }

    private func chromeButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(fg)
                .frame(width: 44, height: 44)
                // 细线图标(尤其「···」)本身只有几个像素,不加这句只有点中笔画才算点到。
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// 组字中不切页;否则先存,再调纸页库,有目标页才重建编辑面。返回是否真的执行了。
    @discardableResult
    private func switchPage(_ change: () -> CorePage?) -> Bool {
        guard controller.canSwitchPage else {
            flash("请先完成输入")
            return false
        }
        controller.saveNow()
        if let page = change() { controller.show(page: page) }
        controller.focusEditor()
        return true
    }

    private func openOverview() {
        controller.saveNow()
        library.refresh()
        showOverview = true
    }

    private func handle(_ cmd: EditorCommand) {
        switch cmd {
        case .newPage: switchPage { library.newPage() }
        case .prev: switchPage { library.prev() }
        case .next: switchPage { library.next() }
        case .overview: openOverview()
        case .appearance: showAppearance = true
        case .menu: withAnimation(.easeOut(duration: 0.15)) { chromeOpen.toggle() }
        case .typing:
            if chromeOpen { chromeOpen = false }
            typingRecently = true
            typingWork?.cancel()
            let w = DispatchWorkItem { typingRecently = false }
            typingWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: w)
        }
    }

    private func refocus() { controller.focusEditor() }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { if toast == text { toast = nil } }
        }
    }
}
