import UIKit

enum ThemeID: String, CaseIterable, Codable {
    case ink, dim, paper, sepia, crt
    case crtBlue = "crt-blue"

    /// 仅纸白、米色为浅色主题。
    var isDark: Bool { self != .paper && self != .sepia }

    var name: String {
        switch self {
        case .ink: return "黑底白字"
        case .dim: return "黑底灰字"
        case .paper: return "白底黑字"
        case .sepia: return "米色深灰"
        case .crt: return "复古绿磷 CRT"
        case .crtBlue: return "复古蓝磷 CRT"
        }
    }

    var foregroundHex: String {
        switch self {
        case .ink: return "#ffffff"
        case .dim: return "#b8b8b8"
        case .paper: return "#111111"
        case .sepia: return "#44413c"
        case .crt: return "#0ccc68"
        case .crtBlue: return "#7fb4ff"
        }
    }

    var backgroundHex: String {
        switch self {
        case .ink, .crt, .crtBlue: return "#000000"
        case .dim: return "#111111"
        case .paper: return "#ffffff"
        case .sepia: return "#f3ead7"
        }
    }

    var foreground: UIColor { UIColor(hex: foregroundHex) }
    var background: UIColor { UIColor(hex: backgroundHex) }
    var selection: UIColor { foreground.withAlphaComponent(0.22) }
}

extension UIColor {
    /// 解析 `#rrggbb`;仅供主题常量使用。
    convenience init(hex: String) {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: CGFloat((v >> 16) & 0xff) / 255,
                  green: CGFloat((v >> 8) & 0xff) / 255,
                  blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}
