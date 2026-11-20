import UIKit

/// 内置三组字体;其余字体组不在本里程碑范围内。
enum SumiFont: String, Codable, CaseIterable, Identifiable {
    case plex, wenkai, zhaohua

    var id: String { rawValue }

    var name: String {
        switch self {
        case .plex: return "IBM Plex Mono Light + Plex Sans SC Light"
        case .wenkai: return "LXGW WenKai Mono Lite"
        case .zhaohua: return "朝华打字机"
        }
    }

    func uiFont(size: CGFloat) -> UIFont {
        switch self {
        case .plex:
            let cjk = UIFontDescriptor(fontAttributes: [.name: "IBMPlexSansSC-Light"])
            let d = UIFontDescriptor(fontAttributes: [.name: "IBMPlexMono-Light", .cascadeList: [cjk]])
            return UIFont(descriptor: d, size: size)
        case .wenkai:
            return UIFont(name: "LXGWWenKaiMonoLite-Regular", size: size)
                ?? .monospacedSystemFont(ofSize: size, weight: .light)
        case .zhaohua:
            return UIFont(name: "ZhaohuaTypeWriter-Light", size: size)
                ?? .monospacedSystemFont(ofSize: size, weight: .light)
        }
    }
}
