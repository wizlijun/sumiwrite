import UIKit

/// 把内核给出的样式跨度映射成属性;不解析 Markdown。跨度范围是 `rendered.text` 的 UTF-16 偏移。
enum Styler {
    static func base(prefs: EditorPrefs, baseFont: UIFont) -> [NSAttributedString.Key: Any] {
        [.font: baseFont,
         .foregroundColor: prefs.theme.foreground,
         .paragraphStyle: paragraph(prefs: prefs, headIndent: 0)]
    }

    static func attributes(for rendered: RenderedText, prefs: EditorPrefs, baseFont: UIFont) -> [(NSRange, [NSAttributedString.Key: Any])] {
        let length = (rendered.text as NSString).length
        var out: [(NSRange, [NSAttributedString.Key: Any])] = []
        for s in rendered.spans {
            let range = NSRange(location: Int(s.start), length: Int(s.length))
            guard range.length > 0, NSMaxRange(range) <= length else { continue }
            var a: [NSAttributedString.Key: Any] = [:]

            var traits: UIFontDescriptor.SymbolicTraits = []
            if s.bold || s.heading > 0 { traits.insert(.traitBold) }
            if s.italic { traits.insert(.traitItalic) }
            let mult = headingScale(s.heading)
            if !traits.isEmpty || mult != 1 {
                var d = baseFont.fontDescriptor
                if let t = d.withSymbolicTraits(d.symbolicTraits.union(traits)) { d = t }
                a[.font] = UIFont(descriptor: d, size: baseFont.pointSize * mult)
            }
            if s.strike { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if s.link != nil { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if s.quote {
                a[.foregroundColor] = prefs.theme.foreground.withAlphaComponent(0.7)
                a[.paragraphStyle] = paragraph(prefs: prefs, headIndent: baseFont.pointSize)
            }
            if !a.isEmpty { out.append((range, a)) }
        }
        return out
    }

    private static func headingScale(_ level: UInt8) -> CGFloat {
        switch level {
        case 1: return 1.5
        case 2: return 1.3
        case 3: return 1.15
        default: return 1.0
        }
    }

    private static func paragraph(prefs: EditorPrefs, headIndent: CGFloat) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = CGFloat(prefs.lineSpacing)
        p.headIndent = headIndent
        return p
    }
}
