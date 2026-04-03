import Foundation

struct ClaudeAuthInfo {
    let email: String
    let plan: String
    let orgName: String?
}

struct UsageLimits {
    let fiveHourUtilization: Double   // 0.0–1.0
    let fiveHourResetAt: Date
    let sevenDayUtilization: Double   // 0.0–1.0
    let sevenDayResetAt: Date
    let fetchedAt: Date = Date()
}

struct CredentialsManager {
    private static let keychainService = "Claude Code-credentials"
    private static var keychainAccount: String { NSUserName() }

    func readCredentials() -> Data? {
        Self.currentKeychainData()
    }

    @discardableResult
    func writeCredentials(_ data: Data) -> Bool {
        guard let json = String(data: data, encoding: .utf8) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["add-generic-password", "-s", Self.keychainService, "-a", Self.keychainAccount, "-w", json, "-U"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func currentKeychainData() -> Data? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-a", keychainAccount, "-w"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let raw = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let str = String(data: raw, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !str.isEmpty else { return nil }
        return str.data(using: .utf8)
    }

    /// Finds the claude binary by checking common install locations
    private static func claudePath() -> String? {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs `claude auth status` CLI command to get current account info
    nonisolated static func fetchAuthStatus() -> ClaudeAuthInfo? {
        guard let claude = claudePath() else { return nil }

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claude)
        process.arguments = ["auth", "status"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let loggedIn = json["loggedIn"] as? Bool, loggedIn,
              let email = json["email"] as? String,
              let subscriptionType = json["subscriptionType"] as? String
        else { return nil }

        let plan: String
        switch subscriptionType.lowercased() {
        case "max": plan = "Max"
        case "pro": plan = "Pro"
        case "free": plan = "Free"
        default: plan = subscriptionType.capitalized
        }

        let orgName = json["orgName"] as? String
        return ClaudeAuthInfo(email: email, plan: plan, orgName: orgName)
    }

    /// Extracts OAuth access token from stored credentials JSON (keychain format)
    static func oauthToken(from credentialsJSON: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: credentialsJSON) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { return nil }
        return token
    }

    /// Reads the current keychain credentials and returns the OAuth token
    static func currentOAuthToken() -> String? {
        currentKeychainData().flatMap { oauthToken(from: $0) }
    }

    /// Fetches real-time rate limit utilization via a minimal API call.
    /// Parses `anthropic-ratelimit-unified-*` response headers.
    nonisolated static func fetchUsageLimits(oauthToken: String) -> UsageLimits? {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Bearer \(oauthToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("claude-code-20250219,oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let semaphore = DispatchSemaphore(value: 0)
        var result: UsageLimits?

        URLSession.shared.dataTask(with: request) { _, response, _ in
            defer { semaphore.signal() }
            guard let http = response as? HTTPURLResponse else { return }
            let h = http.allHeaderFields as? [String: String] ?? [:]

            func doubleHeader(_ key: String) -> Double? {
                h.first(where: { $0.key.lowercased() == key })
                    .flatMap { Double($0.value) }
            }
            func dateHeader(_ key: String) -> Date? {
                doubleHeader(key).map { Date(timeIntervalSince1970: $0) }
            }

            guard let fiveUtil = doubleHeader("anthropic-ratelimit-unified-5h-utilization"),
                  let fiveReset = dateHeader("anthropic-ratelimit-unified-5h-reset"),
                  let sevenUtil = doubleHeader("anthropic-ratelimit-unified-7d-utilization"),
                  let sevenReset = dateHeader("anthropic-ratelimit-unified-7d-reset")
            else { return }

            result = UsageLimits(
                fiveHourUtilization: fiveUtil,
                fiveHourResetAt: fiveReset,
                sevenDayUtilization: sevenUtil,
                sevenDayResetAt: sevenReset
            )
        }.resume()

        semaphore.wait()
        return result
    }
}
