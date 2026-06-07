// © Shimon Shmueli
import Foundation

/// Read-only subprocess helper used by every Headless backend.
/// Argument-array invocations only — never shell strings, so there is no
/// place for shell injection from a package name. Hard 15s default timeout
/// so a hung CLI can't pin the UI.
enum Shell {

    enum Failure: LocalizedError {
        case missingBinary(String)
        case launchFailed(String)
        case timedOut(seconds: TimeInterval, path: String)
        case nonZeroExit(status: Int32, path: String, stderr: String)

        var errorDescription: String? {
            switch self {
            case .missingBinary(let p):     return "Binary not found: \(p)"
            case .launchFailed(let msg):    return "Failed to launch process: \(msg)"
            case .timedOut(let s, let p):   return "\(p) timed out after \(Int(s))s"
            case .nonZeroExit(let st, let p, let err):
                return "\(p) exited \(st): \(err.prefix(200))"
            }
        }
    }

    /// Runs `executablePath` with the given arguments, returns stdout as String.
    /// Throws on missing binary, launch failure, timeout, or non-zero exit.
    /// Each call inherits the parent environment plus a PATH augmented with the
    /// common Homebrew/Apple-installed-CLI locations, so a tool spawned by
    /// `brew` (e.g. its bundled git) can find its peers regardless of where
    /// ZoneKey was launched from.
    static func run(_ executablePath: String,
                    _ arguments: [String],
                    timeout: TimeInterval = 15.0) async throws -> String {

        guard FileManager.default.fileExists(atPath: executablePath) else {
            throw Failure.missingBinary(executablePath)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            var env = ProcessInfo.processInfo.environment
            let extraPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            env["PATH"] = env["PATH"].map { "\($0):\(extraPath)" } ?? extraPath
            // Suppress Homebrew's incidental git-fetch on every invocation —
            // it can add 10–30s to otherwise fast read-only calls.
            env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
            env["HOMEBREW_NO_ANALYTICS"] = "1"
            process.environment = env

            // Guard against double-resume — both the timeout work item and
            // the termination handler can race to finish first.
            let resumeState = ResumeState()

            do {
                try process.run()
            } catch {
                resumeState.resume(throwing: Failure.launchFailed(error.localizedDescription),
                                   on: continuation)
                return
            }

            let timeoutItem = DispatchWorkItem {
                guard process.isRunning else { return }
                process.terminate()
                resumeState.resume(
                    throwing: Failure.timedOut(seconds: timeout, path: executablePath),
                    on: continuation
                )
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

            process.terminationHandler = { proc in
                timeoutItem.cancel()
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let outStr = String(data: outData, encoding: .utf8) ?? ""
                let errStr = String(data: errData, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    resumeState.resume(returning: outStr, on: continuation)
                } else {
                    resumeState.resume(
                        throwing: Failure.nonZeroExit(
                            status: proc.terminationStatus,
                            path: executablePath,
                            stderr: errStr
                        ),
                        on: continuation
                    )
                }
            }
        }
    }

    /// First path from `candidates` that exists on disk. Used to probe for
    /// CLI tools at known install locations without depending on $PATH.
    static func findBinary(candidates: [String]) -> String? {
        candidates.first { FileManager.default.fileExists(atPath: $0) }
    }
}

/// Thread-safe single-fire resume gate. Continuations may only be resumed
/// once; if the timeout fires and the terminationHandler then fires, the
/// second call would crash. This collapses them safely.
private final class ResumeState: @unchecked Sendable {
    private var hasResumed = false
    private let lock = NSLock()

    func resume(returning value: String,
                on continuation: CheckedContinuation<String, Error>) {
        lock.lock(); defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        continuation.resume(returning: value)
    }

    func resume(throwing error: Error,
                on continuation: CheckedContinuation<String, Error>) {
        lock.lock(); defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        continuation.resume(throwing: error)
    }
}
