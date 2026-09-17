import Foundation

enum ResourceLoader {
    static func url(_ name: String) -> URL? {
        let noExt = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        if let url = Bundle.module.url(forResource: noExt, withExtension: ext.isEmpty ? nil : ext) {
            return url
        }
        if let url = Bundle.main.url(forResource: noExt, withExtension: ext.isEmpty ? nil : ext) {
            return url
        }
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func defaultConfigText() -> String? {
        guard let url = url("config.default.toml") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func emojiJSON() -> Data? {
        guard let url = url("emoji.json") else { return nil }
        return try? Data(contentsOf: url)
    }
}
