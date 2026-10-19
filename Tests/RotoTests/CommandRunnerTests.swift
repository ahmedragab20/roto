import Foundation
import Testing
import RotoCore
@testable import Roto

@MainActor
struct CommandRunnerTests {
    @Test(.timeLimit(.minutes(1))) func runsConfiguredShellSyntaxInHomeDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("roto-command-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("result")
        let command = LauncherCommand(name: "Test", command: "printf '%s' \"$PWD\" | /bin/cat > '\(output.path)'")
        let failure = await run(command)
        #expect(failure == nil)
        #expect(try String(contentsOf: output, encoding: .utf8) == FileManager.default.homeDirectoryForCurrentUser.path)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [("exit 23", "status 23"), ("kill -TERM $$", "signal 15"), ("/nonexistent/roto-command", "status 127")])
    func reportsNonzeroExitSignalsAndMissingExecutables(script: String, expected: String) async {
        let failure = await run(LauncherCommand(name: "Failed Task", command: script))
        #expect(failure?.contains("Failed Task") == true)
        #expect(failure?.contains(expected) == true)
    }

    @Test(.timeLimit(.minutes(1))) func discardsOutputWithoutFillingAPipeAndClosesStandardInput() async {
        let failure = await run(LauncherCommand(name: "Output", command: "/usr/bin/yes output | /usr/bin/head -c 200000; /bin/cat"))
        #expect(failure == nil)
    }

    private func run(_ command: LauncherCommand) async -> String? {
        await withCheckedContinuation { continuation in
            CommandRunner.run(command) { failure in continuation.resume(returning: failure) }
        }
    }
}
