import Combine
import Foundation
import Security
import VoiceKit

/// AI 整理的接入点(ios.md §3.8「AI 整理」):地址存 `UserDefaults`,key 只存钥匙串(仅本机、解锁后可读),
/// 两者默认都是空的。key 不进 `UserDefaults`、不进日志;`LlmEndpoint` 打印时也只显示有没有。
@MainActor
final class TidyEndpointStore: ObservableObject {
    static let urlKey = "voice.llm.url"
    static let keyService = "voice.llm.key"

    /// 宿主与设置面板共用的一份。
    static let shared = TidyEndpointStore()

    @Published var url: String {
        didSet { if url != oldValue { defaults.set(url, forKey: Self.urlKey) } }
    }

    /// 第一次用到才读钥匙串:应用启动时不碰它。设备锁着读不到时当作空,下次再读。
    /// 设置面板在 key 填完(回车或离开输入框)时才写;写不进钥匙串时保持原来的值。
    var key: String {
        get {
            if let loaded { return loaded }
            switch Self.readKey() {
            case .found(let k):
                loaded = k
                return k
            case .missing:
                loaded = ""
                return ""
            case .unavailable:
                return ""
            }
        }
        set {
            guard newValue != key else { return }
            guard Self.writeKey(newValue) else { return }
            objectWillChange.send()
            loaded = newValue
        }
    }

    var endpoint: LlmEndpoint { LlmEndpoint(url: url, key: key) }

    private let defaults: UserDefaults
    private var loaded: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        url = defaults.string(forKey: Self.urlKey) ?? ""
    }

    /// 向填好的接入点发一次试探请求、不看结果:系统的本地网络询问就出现在设置里,而不是第一次长语音的中途
    /// (ios.md §3.8「AI 整理」)。不带 key。
    static func probe(_ url: String) {
        guard let base = normalizeLlmUrl(url), let u = URL(string: base) else { return }
        var request = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "HEAD"
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    private enum Read { case found(String), missing, unavailable }

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keyService]
    }

    private static func readKey() -> Read {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        switch SecItemCopyMatching(q as CFDictionary, &out) {
        case errSecSuccess:
            guard let data = out as? Data, let k = String(data: data, encoding: .utf8) else { return .missing }
            return .found(k)
        case errSecItemNotFound: return .missing
        default: return .unavailable  // 如设备锁着(errSecInteractionNotAllowed)
        }
    }

    /// 空的 key 删掉那一项;其余先更新,没有那一项再添加。返回是否写成。
    private static func writeKey(_ key: String) -> Bool {
        let q = query()
        guard !key.isEmpty else {
            let s = SecItemDelete(q as CFDictionary)
            return s == errSecSuccess || s == errSecItemNotFound
        }
        let attrs: [String: Any] = [kSecValueData as String: Data(key.utf8),
                                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let s = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if s == errSecSuccess { return true }
        guard s == errSecItemNotFound else { return false }
        var add = q
        add.merge(attrs) { _, new in new }
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
