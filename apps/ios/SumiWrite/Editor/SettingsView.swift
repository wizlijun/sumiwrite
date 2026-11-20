import SwiftUI

/// 外观与打字音设置弹层。每次改动都交给 `onChange`,由编辑面校验、应用并持久化。
struct SettingsView: View {
    @State private var prefs: EditorPrefs
    private let onChange: (EditorPrefs) -> Void
    @Environment(\.dismiss) private var dismiss

    init(prefs: EditorPrefs, onChange: @escaping (EditorPrefs) -> Void) {
        _prefs = State(initialValue: prefs)
        self.onChange = onChange
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("主题") {
                    Picker("主题", selection: $prefs.theme) {
                        ForEach(ThemeID.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("排版") {
                    Stepper(value: $prefs.fontSize, in: EditorPrefs.fontSizeRange, step: 1) {
                        Text("字号 \(Int(prefs.fontSize))")
                    }
                    VStack(alignment: .leading) {
                        Text("行距 \(String(format: "%.1f", prefs.lineSpacing))")
                        Slider(value: lineSpacing, in: EditorPrefs.lineSpacingRange, step: 0.1)
                    }
                }
                Section("光标") {
                    Picker("光标动态", selection: $prefs.caretMotion) {
                        Text("平缓呼吸").tag(CaretMotion.breathing)
                        Text("常亮").tag(CaretMotion.steady)
                    }
                    Toggle("聚焦打字", isOn: $prefs.focusTyping)
                }
                Section("打字音") {
                    Toggle("打字音", isOn: $prefs.typingSound)
                    Picker("音色", selection: $prefs.soundPack) {
                        ForEach(SoundPack.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .disabled(!prefs.typingSound)
                }
            }
            .navigationTitle("外观")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .onChange(of: prefs) { _, new in onChange(new) }
    }

    /// 滑块按 0.1 取值,存一位小数,避免 1.6000000000000001 这类值。
    private var lineSpacing: Binding<Double> {
        Binding(get: { prefs.lineSpacing },
                set: { prefs.lineSpacing = ($0 * 10).rounded() / 10 })
    }
}

private extension ThemeID {
    /// 名称按 04「主题」。
    var displayName: String {
        switch self {
        case .ink: return "黑底白字"
        case .dim: return "黑底灰字"
        case .paper: return "白底黑字"
        case .sepia: return "米色深灰"
        case .crt: return "复古绿磷 CRT"
        case .crtBlue: return "复古蓝磷 CRT"
        }
    }
}

private extension SoundPack {
    /// 名称按 04「打字音」。
    var displayName: String {
        switch self {
        case .typewriter: return "打字机"
        case .thock: return "低沉机械键"
        }
    }
}
