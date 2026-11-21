import Combine
import Foundation
import Security
import VoiceKit

/// AI 整理的接入点(ios.md §3.7「AI 整理」):地址存 `UserDefaults`,key 只存钥匙串(仅本机、解锁后可读),
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

    /// 第一次用到才读钥匙串:应用启动时不碰它。
    var key: String {
        get {
            if let loaded { return loaded }
            let k = Self.readKey() ?? ""
            loaded = k
            return k
        }
        set {
            guard newValue != key else { return }
            objectWillChange.send()
            loaded = newValue
            Self.writeKey(newValue)
        }
    }

    var endpoint: LlmEndpoint { LlmEndpoint(url: url, key: key) }

    private let defaults: UserDefaults
    private var loaded: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        url = defaults.string(forKey: Self.urlKey) ?? ""
    }

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keyService]
    }

    private static func readKey() -> String? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 空的 key 删掉那一项。
    private static func writeKey(_ key: String) {
        let q = query()
        SecItemDelete(q as CFDictionary)
        guard !key.isEmpty else { return }
        var add = q
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
