import SwiftUI

struct AppearanceView: View {
    @ObservedObject var prefs: PrefsModel

    var body: some View {
        NavigationStack {
            Form {
                Section("主题") {
                    Picker("主题", selection: $prefs.prefs.theme) {
                        ForEach(ThemeID.allCases, id: \.self) { t in
                            HStack {
                                Circle().fill(Color(t.background))
                                    .overlay(Circle().stroke(Color(t.foreground), lineWidth: 3))
                                    .frame(width: 18, height: 18)
                                Text(t.name)
                            }.tag(t)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Picker("字体", selection: $prefs.prefs.font) {
                        ForEach(SumiFont.allCases) { f in Text(f.name).tag(f) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: { Text("字体") } footer: {
                    Text("试做版只内置两组字体。朝华、油茶、朱雀仿宋、Unifont 在正式版里按需下载。")
                }
                Section("排版") {
                    LabeledContent("字号 \(Int(prefs.prefs.fontSize)) pt") {
                        Slider(value: $prefs.prefs.fontSize, in: 8...96, step: 1)
                    }
                    LabeledContent("行距 \(prefs.prefs.lineSpacing, specifier: "%.1f")") {
                        Slider(value: $prefs.prefs.lineSpacing, in: 1...3, step: 0.1)
                    }
                    Button("恢复默认字号与行距") { prefs.resetSize() }
                }
                Section("书写") {
                    Picker("光标", selection: $prefs.prefs.caretMotion) {
                        Text("平缓呼吸").tag(CaretMotion.breathing)
                        Text("常亮").tag(CaretMotion.steady)
                    }
                    Toggle("聚焦打字", isOn: $prefs.prefs.focusTyping)
                    Toggle("打字音", isOn: $prefs.prefs.typingSound)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
