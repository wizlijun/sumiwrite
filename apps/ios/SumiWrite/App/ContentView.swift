import SwiftUI
import VoiceKit

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
    @State private var deskTop: CGFloat?

    var body: some View {
        let fg = Color(prefs.prefs.theme.foreground)
        ZStack {
            Color(prefs.prefs.theme.background).ignoresSafeArea()
            DeskTray(top: deskTop, color: fg)
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
            controller.onDeskChange = { top in DeskTray.animate { deskTop = top } }
        }
    }
}

/// iPhone Duo 半折时折痕以下的底座(ios.md §3.7):主题底色上叠 4% 前景色,从折痕铺到屏幕底;不接点按。
/// `top` 是折痕顶的窗口 y 坐标,nil 时不画。
private struct DeskTray: View {
    let top: CGFloat?
    let color: Color

    /// 与编辑面正文区的移动同步:0.25 秒 easeOut;「减少动态效果」时直接到位。
    static func animate(_ change: () -> Void) {
        withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .easeOut(duration: 0.25), change)
    }

    var body: some View {
        GeometryReader { geo in
            if let top {
                let y = max(0, top - geo.frame(in: .global).minY)
                color.opacity(0.04)
                    .frame(width: geo.size.width, height: max(0, geo.size.height - y))
                    .offset(y: y)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
    let voice: VoiceHost
    @ObservedObject var library: PageLibrary
    @ObservedObject var prefs: PrefsModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var chromeOpen = false
    @State private var typingRecently = false
    @State private var typingWork: DispatchWorkItem?
    @State private var showOverview = false
    @State private var showAppearance = false
    @State private var toast: String?
    /// 提示条是否带「去设置」(语音权限、识别语言)。
    @State private var toastSettings = VoiceSettings.none
    /// 每次 `flash` 加一:只让最后一次的计时收起提示条。
    @State private var toastSerial = 0
    @State private var status: String?
    @State private var deskTop: CGFloat?

    private var fg: Color { Color(prefs.prefs.theme.foreground) }
    private var scheme: ColorScheme { prefs.prefs.theme.isDark ? .dark : .light }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(prefs.prefs.theme.background).ignoresSafeArea()
            DeskTray(top: deskTop, color: fg)
            // 「···」放在编辑区下方的独立一条里,不叠在 UITextView 上:
            // 叠在上面时,点按会先被文本视图的手势接走,按钮收不到。
            VStack(spacing: 0) {
                EditorHost(controller: controller)
                if let status { StatusLine(text: status, color: fg) }
                // 麦克风在这一条的最右端(ios.md §3.8「入口」);「···」照旧居中。
                ZStack(alignment: .trailing) {
                    chrome.frame(maxWidth: .infinity)
                    MicButton(hold: voice.hold, host: voice, color: fg, enabled: controller.voiceAvailable)
                        .opacity(chromeOpen || typingRecently ? 0 : 0.35)
                        .animation(.easeOut(duration: 0.3), value: typingRecently)
                        .padding(.trailing, 6)
                }
                .frame(height: 48)
                .padding(.bottom, 4)
            }
            if let toast {
                HStack(spacing: 12) {
                    Text(toast)
                        .font(.footnote)
                        .foregroundStyle(fg)
                        .fixedSize(horizontal: false, vertical: true)
                    if toastSettings != .none {
                        let settings = toastSettings
                        Button("去设置") { voice.openSettings(settings) }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(fg)
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(fg.opacity(0.12)))
                .padding(.horizontal, 16)
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
            controller.onDeskChange = { top in DeskTray.animate { deskTop = top } }
            voice.onNotice = { text, settings in
                flash(text, life: VoiceHost.noticeLife(text, settings: settings), settings: settings)
            }
            // 上次没插入的语音放回本页末尾(ios.md §3.8「AI 整理」);切页时由编辑面通知。
            voice.restoreHeld()
        }
        .onChange(of: scenePhase) { _, phase in
            // 退到后台:整理卡上的字先落地,正在说的话按取消处理(ios.md §3.8「松手与落地」「AI 整理」)。
            // 只是失去活跃(控制中心、本地网络等系统弹窗)不动它;来电由音频会话的打断取消。
            if phase == .background {
                voice.landTidy()
                voice.interrupt()
            }
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
            AppearanceView(prefs: prefs,
                           copyText: { controller.pageTextForCopy().map { ($0, controller.pageCharacterCount) } },
                           pageIsEmpty: { controller.pageIsEmpty })
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
                chromeButton("gearshape", "设置") { openAppearance() }
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

    /// 系统输入法组字中不切页;内置输入法的组字先按原文上屏(ios.md §3.6),再存,再调纸页库,
    /// 有目标页才重建编辑面。返回是否真的执行了。
    @discardableResult
    private func switchPage(_ change: () -> CorePage?) -> Bool {
        guard controller.canSwitchPage else {
            flash("请先完成输入")
            return false
        }
        voice.landTidy()
        controller.prepareToSwitch()
        controller.saveNow()
        if let page = change() { controller.show(page: page) }
        controller.focusEditor()
        return true
    }

    private func openOverview() {
        voice.landTidy()
        controller.prepareToSwitch()
        controller.saveNow()
        library.refresh()
        showOverview = true
    }

    /// 设置面板盖住编辑面:内置输入法的组字先上屏。
    private func openAppearance() {
        voice.landTidy()
        controller.prepareToSwitch()
        showAppearance = true
    }

    private func handle(_ cmd: EditorCommand) {
        switch cmd {
        case .newPage: switchPage { library.newPage() }
        case .prev: switchPage { library.prev() }
        case .next: switchPage { library.next() }
        case .overview: openOverview()
        case .appearance: openAppearance()
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

    private func flash(_ text: String, life: Double = 1.8, settings: VoiceSettings = .none) {
        toastSerial += 1
        let serial = toastSerial
        withAnimation {
            toast = text
            toastSettings = settings
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + life) {
            guard toastSerial == serial else { return }
            withAnimation {
                toast = nil
                toastSettings = .none
            }
        }
    }
}

/// 底栏右端的麦克风:按住说话,不是开关(ios.md §3.8「入口」)。手指按下、移动、松开交给 `VoiceHost`;
/// 按住时 VoiceKit 的覆盖层从这里长出圆盘,并经 `hold.buttonOpacity` 把图标淡掉。
private struct MicButton: View {
    @ObservedObject var hold: VoiceHold
    let host: VoiceHost
    let color: Color
    /// 纸页不可写时变灰、不响应。
    let enabled: Bool
    @GestureState private var pressing = false

    var body: some View {
        Image(systemName: "mic")
            .font(.system(size: 17, weight: .light))
            .foregroundStyle(color)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .opacity(hold.buttonOpacity * (enabled ? 1 : 0.4))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($pressing) { _, state, _ in state = true }
                    .onChanged { host.finger(at: $0.location, start: $0.startLocation) }
                    .onEnded { _ in host.fingerUp() },
                including: enabled ? .all : .none)
            // 手势被系统取消时没有 `onEnded`,只有手势状态复位:晚一拍看手指是否还算按着,是就当打断。
            .onChange(of: pressing) { _, now in
                if !now { DispatchQueue.main.async { host.fingerGone() } }
            }
            .accessibilityElement()
            .accessibilityLabel("语音输入")
            .accessibilityHint("双击开始说话,再双击结束")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { host.accessibilityToggle() } }
    }
}
