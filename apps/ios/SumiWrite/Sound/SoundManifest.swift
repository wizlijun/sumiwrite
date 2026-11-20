import Foundation

/// 打字音资源清单(`sounds/manifest.json`)。只解码用到的字段,未知键与未知 role 一律忽略。
struct SoundManifest: Decodable {
    private struct Pack: Decodable {
        let id: String
        let roles: [String: [String]]
    }

    private let packs: [Pack]

    static func load(from directory: URL) throws -> SoundManifest {
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        return try JSONDecoder().decode(SoundManifest.self, from: data)
    }

    /// 相对 `sounds/` 的文件路径;没有该音色或该 role 时为空。
    func files(pack: SoundPack, kind: KeyKind) -> [String] {
        packs.first { $0.id == pack.rawValue }?.roles[kind.role] ?? []
    }
}
