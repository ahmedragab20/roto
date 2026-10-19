import Testing
@testable import RotoCore

struct CommandConfigTests {
    @Test func existingConfigsGetDisplaySleepWithoutMigration() throws {
        #expect(try ConfigLoader.parse("").commands == [.sleepDisplay])
        #expect(try ConfigLoader.parse(ConfigLoader.defaultTOML).commands == [.sleepDisplay])
    }

    @Test func customCommandsReplaceDefaultsAndPreserveShellSyntax() throws {
        let config = try ConfigLoader.parse("""
            [[commands]]
            name = "  My Task  "
            command = 'printf "%s" "$HOME" | cat'
            keywords = ["task", "work"]
            [[commands]]
            name = "Second"
            command = "true"
            """)
        #expect(config.commands == [
            LauncherCommand(name: "My Task", command: "printf \"%s\" \"$HOME\" | cat", keywords: ["task", "work"]),
            LauncherCommand(name: "Second", command: "true"),
        ])
        #expect(try ConfigLoader.parse("commands = []").commands.isEmpty)
    }

    @Test(arguments: [
        "commands = 'bad'", "[commands]\nname = 'Wrong table'", "commands = [42]",
        "[[commands]]\ncommand = 'true'", "[[commands]]\nname = 'Missing command'",
        "[[commands]]\nname = ' '\ncommand = 'true'", "[[commands]]\nname = 'A'\ncommand = ' '",
        "[[commands]]\nname = 42\ncommand = 'true'", "[[commands]]\nname = 'A'\ncommand = false",
        "[[commands]]\nname = 'A'\ncommand = 'true'\nkeywords = 'wrong'",
        "[[commands]]\nname = 'A'\ncommand = 'true'\nkeywords = ['ok', 42]",
        "[[commands]]\nname = 'A'\ncommand = \"true\\u0000ignored\"",
        "[[commands]]\nname = \"A\\u0000B\"\ncommand = 'true'",
        "[[commands]]\nname = 'Task'\ncommand = 'true'\n[[commands]]\nname = ' task '\ncommand = 'false'",
    ])
    func rejectsMalformedCommands(source: String) {
        #expect(throws: ConfigError.self) { try ConfigLoader.parse(source) }
    }

    @Test func shortcutEditorPreservesCommandsVerbatim() throws {
        let commands = """
            [[commands]]
            name = "Run Task"
            command = '''
            echo '[hotkeys]'
            echo done
            '''
            keywords = ["task"]
            """
        let source = "[hotkeys]\nlauncher = 'cmd+space'\n" + commands
        let edited = try KeymapEditor.updating(source, bindings: [.init(kind: .launcher, shortcut: "alt+space")])
        #expect(edited.contains(commands))
        #expect(try ConfigLoader.parse(edited).commands == ConfigLoader.parse(source).commands)
        #expect(try ConfigLoader.parse(edited).hotkeys.launcher == "alt+space")
    }
}
