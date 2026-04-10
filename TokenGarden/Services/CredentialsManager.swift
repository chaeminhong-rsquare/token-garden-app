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
        let result = ProcessRunner.runSync(
            executable: "/usr/bin/security",
            arguments: ["add-generic-password", "-s", Self.keychainService, "-a", Self.keychainAccount, "-w", json, "-U"]
        )
        return result.succeeded
    }

    private static func currentKeychainData() -> Data? {
        let result = ProcessRunner.runSync(
            executable: "/usr/bin/security",
            arguments: ["find-generic-password", "-s", keychainService, "-a", keychainAccount, "-w"]
        )
        guard let str = result.outputString?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !str.isEmpty else { return nil }
        return str.data(using: .utf8)
    }

    /// Finds the claude binary by checking common install locations and PATH
    private static func claudePath() -> String? {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        // Check direct paths first (including symlinks)
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    /// Runs `claude auth status` CLI command to get current account info
    nonisolated static func fetchAuthStatus() -> ClaudeAuthInfo? {
        guard let claude = claudePath() else {
            // Fallback: read plan from keychain if CLI not found
            return fetchAuthStatusFromKeychain()
        }

        let result = ProcessRunner.runSync(
            executable: claude,
            arguments: ["auth", "status"],
            environment: ProcessInfo.processInfo.environment
        )
        guard result.succeeded else {
            return fetchAuthStatusFromKeychain()
        }

        guard let json = try? JSONSerialization.jsonObject(with: result.output) as? [String: Any],
              let loggedIn = json["loggedIn"] as? Bool, loggedIn,
              let email = json["email"] as? String,
              let subscriptionType = json["subscriptionType"] as? String
        else {
            return fetchAuthStatusFromKeychain()
        }

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

    /// Fallback: reads plan from keychain when CLI is unavailable
    private nonisolated static func fetchAuthStatusFromKeychain() -> ClaudeAuthInfo? {
        guard let credsData = currentKeychainData(),
              let json = try? JSONSerialization.jsonObject(with: credsData) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any]
        else { return nil }

        let subscriptionType = oauth["subscriptionType"] as? String ?? "pro"
        let plan: String
        switch subscriptionType.lowercased() {
        case "max": plan = "Max"
        case "pro": plan = "Pro"
        case "free": plan = "Free"
        default: plan = subscriptionType.capitalized
        }

        return ClaudeAuthInfo(email: "claude.ai account", plan: plan, orgName: nil)
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
    nonisolated static func fetchUsageLimits(oauthToken: String) async -> UsageLimits? {
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

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }

        let headers = http.allHeaderFields as? [String: String] ?? [:]

        func doubleHeader(_ key: String) -> Double? {
            headers.first(where: { $0.key.lowercased() == key })
                .flatMap { Double($0.value) }
        }
        func dateHeader(_ key: String) -> Date? {
            doubleHeader(key).map { Date(timeIntervalSince1970: $0) }
        }

        guard let fiveUtil = doubleHeader("anthropic-ratelimit-unified-5h-utilization"),
              let fiveReset = dateHeader("anthropic-ratelimit-unified-5h-reset"),
              let sevenUtil = doubleHeader("anthropic-ratelimit-unified-7d-utilization"),
              let sevenReset = dateHeader("anthropic-ratelimit-unified-7d-reset")
        else { return nil }

        return UsageLimits(
            fiveHourUtilization: fiveUtil,
            fiveHourResetAt: fiveReset,
            sevenDayUtilization: sevenUtil,
            sevenDayResetAt: sevenReset
        )
    }
}
