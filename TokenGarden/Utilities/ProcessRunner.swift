import Foundation

/// Common wrapper for `Process` execution used across the app.
/// Replaces the repeated `Process() + Pipe + waitUntilExit` pattern
/// in TokenDataStore, CredentialsManager, and ProfileManager.
enum ProcessRunner {
    struct Result: Sendable {
        let output: Data
        let exitCode: Int32

        var outputString: String? {
            String(data: output, encoding: .utf8)
        }

        var succeeded: Bool { exitCode == 0 }
    }

    /// Synchronous execution. Blocks the calling thread until the process exits.
    /// Use only from background contexts — never from the main thread.
    nonisolated static func runSync(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> Result {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        if let environment {
            process.environment = environment
        }

        do {
            try process.run()
        } catch {
            return Result(output: Data(), exitCode: -1)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(output: data, exitCode: process.terminationStatus)
    }

    /// Async execution via `terminationHandler`. Does not block any thread.
    nonisolated static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) async -> Result {
        await withCheckedContinuation { continuation in
            let pipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            if let environment {
                process.environment = environment
            }

            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(
                    returning: Result(output: data, exitCode: proc.terminationStatus)
                )
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: Result(output: Data(), exitCode: -1))
            }
        }
    }
}
