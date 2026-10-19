import AppKit
import RotoCore

@MainActor
enum CommandRunner {
    /// Launch without blocking the popup or piping unbounded command output.
    /// Only the configured string reaches the shell, never the search query.
    static func run(
        _ command: LauncherCommand,
        completion: @escaping @MainActor @Sendable (String?) -> Void = reportFailure
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command.command]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { process in
            let failure: String?
            if process.terminationReason == .uncaughtSignal {
                failure = "“\(command.name)” was stopped by signal \(process.terminationStatus)."
            } else if process.terminationStatus != 0 {
                failure = "“\(command.name)” exited with status \(process.terminationStatus)."
            } else {
                failure = nil
            }
            DispatchQueue.main.async { completion(failure) }
        }
        do {
            try process.run()
        } catch {
            completion("Could not run “\(command.name)”: \(error.localizedDescription)")
        }
    }

    private static func reportFailure(_ message: String?) {
        guard let message else { return }
        let alert = NSAlert()
        alert.messageText = "Command failed"
        alert.informativeText = message + "\nCheck the command in config.toml."
        alert.runModal()
    }
}
