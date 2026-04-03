import Foundation

/// Reads and writes `~/.claude/settings.json` for model selection
struct ClaudeSettingsManager {
    static let settingsPath: String = {
        NSHomeDirectory() + "/.claude/settings.json"
    }()

    static func currentModel() -> String? {
        guard let data = FileManager.default.contents(atPath: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? String
        else { return nil }
        return model
    }

    @discardableResult
    static func setModel(_ model: String?) -> Bool {
        guard let data = FileManager.default.contents(atPath: settingsPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }

        if let model {
            json["model"] = model
        } else {
            json.removeValue(forKey: "model")
        }

        guard let updated = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return false }
        return FileManager.default.createFile(atPath: settingsPath, contents: updated)
    }
}
