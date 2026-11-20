import RimeKit
import SwiftUI

struct AppearanceView: View {
    @ObservedObject var prefs: PrefsModel
    /// 「复制全文」(ios.md §3.5.1):Markdown 原文与「已复制 N 字」的 N;系统输入法组字中为 nil。
    var copyText: () -> (markdown: String, characters: Int)? = { ("", 0) }
    /// 空页时按钮置灰;面板每次重算都问,要便宜。
    var pageIsEmpty: () -> Bool = { true }
    @State private var copyNote: String?
    /// 每点一次加一:1.5 秒后只清自己那次的提示。
    @State private var copySeq = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    let empty = pageIsEmpty()
                    Button {
                        copySeq += 1
                        let mine = copySeq
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copySeq == mine { copyNote = nil } }
                        guard let copy = copyText() else { copyNote = "请先完成输入"; return }
                        UIPasteboard.general.string = copy.markdown
                        copyNote = "已复制 \(copy.characters) 字"
                    } label: { Label("复制全文", systemImage: "doc.on.doc") }
                    .disabled(empty)
                    if empty { Text("本页是空的").font(.footnote).foregroundStyle(.secondary) }
                    else if let copyNote { Text(copyNote).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("本页") }
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
                    Text("试做版内置三组字体。油茶、朱雀仿宋、Unifont 在正式版里按需下载。")
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
                SwitchShortcutSection(shortcut: $prefs.prefs.switchShortcut)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// 「输入法」一组:实体键盘的内嵌输入法切换中 / 英的快捷键(ios.md §3.6)。
private struct SwitchShortcutSection: View {
    @Binding var shortcut: RimeSwitchShortcut

    var body: some View {
        Section {
            Picker("切换中 / 英", selection: $shortcut) {
                Text("Control + 空格").tag(RimeSwitchShortcut.controlSpace)
                Text("Option + 空格").tag(RimeSwitchShortcut.optionSpace)
                Text("Shift + 空格").tag(RimeSwitchShortcut.shiftSpace)
                Text("关").tag(RimeSwitchShortcut.off)
            }
        } header: { Text("输入法") } footer: {
            if shortcut == .shiftSpace {
                Text("接实体键盘时,内置输入法用它在中文与英文之间切换;单按左 Shift 也能切换。按着 Shift 打完大写字母紧接着按空格,也会切换。")
            } else {
                Text("接实体键盘时,内置输入法用它在中文与英文之间切换;单按左 Shift 也能切换。")
            }
        }
    }
}
